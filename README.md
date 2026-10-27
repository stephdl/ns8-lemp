# ns8-lemp

Host one PHP web site on NethServer 8 with nginx, PHP-FPM, MariaDB and phpMyAdmin.
Each instance serves one host name and owns one site database.

The pod runs these containers:

| Container | Image | Role |
|---|---|---|
| `nginx-app` | `docker.io/nginx:1.30.6` | web server, listens on the module TCP port behind Traefik |
| `php-fpm-app` | `ghcr.io/stephdl/lemp-php8.x` | PHP-FPM of the selected version, built from `docker.io/php:8.x-fpm-trixie` |
| `cron-app` | same image as `php-fpm-app` | runs the site cron jobs |
| `mariadb-app` | `docker.io/mariadb:12.3.3` | MariaDB LTS, supported until June 2029 |
| `phpmyadmin-app` | `docker.io/phpmyadmin:5.2.3-fpm` | phpMyAdmin on `/phpmyadmin/`, enabled by default |

PHP 8.2, 8.3, 8.4 and 8.5 are available. Only the image of the selected version is pulled on the node.
The PHP image loads the same extensions as ns8-lamp (gd, intl, ldap, imagick, imap, apcu, memcached,
mysqli, pdo_mysql, opcache, soap, sockets, xsl, zip and more). The build fails if one is missing.
It also has composer, msmtp and the admin tools of ns8-lamp (vim, nano, git, wget, curl, zip, ftp,
rsync, ssh, sftp, scp, mariadb client).

## Install

    add-module ghcr.io/stephdl/lemp:latest 1

The output gives the instance name, for example `lemp1`.

## Configure

Use the Settings page, or `configure-module`. Feed the JSON from stdin, so the passwords stay out of the shell history:

    api-cli run module/lemp1/configure-module --data - <<'EOF'
    {
      "host": "www.example.org",
      "lets_encrypt": false,
      "php_version": "8.4",
      "document_root": "",
      "nginx_preset": "generic",
      "php_memory_limit": "512M",
      "php_upload_max_filesize": "100M",
      "php_max_execution_time": 600,
      "php_timezone": "Europe/Paris",
      "fpm_pm_max_children": 10,
      "phpmyadmin_enabled": true,
      "db_name": "app",
      "db_user": "app",
      "db_password": "<site database password>",
      "admin_password": "<MariaDB admin password>",
      "user_domain": "",
      "mail_from": ""
    }
    EOF

`db_password` and `admin_password` are required at the first configuration. Later, omit them to keep the current ones.
They need 8 characters with a lowercase letter, an uppercase letter, a digit and a symbol, like in the UI.
`db_name` and `db_user` cannot change after the first configuration.
`php_memory_limit` must be larger than `php_upload_max_filesize`. `php_max_execution_time` goes up to 3600 seconds,
and 0 removes the limit. The Settings page shows sliders for these values.

The module sizes the MariaDB InnoDB buffer pool from the node memory: 5%, between 128 MiB and 1 GiB.
Set `innodb_buffer_pool_size` in `mariadb/90-custom.cnf` to change it.

HTTPS is always forced on the route.

### nginx presets

nginx ignores `.htaccess` files. `nginx_preset` gives the rewrite rules:

- `generic`: every unknown path goes to `index.php`, which fits most PHP frameworks.
- `wordpress`: the same, plus WordPress hardening. `xmlrpc.php` is denied, and PHP files under `wp-content/uploads/` never run.

In both presets, hidden files (`.htaccess`, `.git`, `.env`) are never served.

`document_root` is a subdirectory of `/app`, for example `public` for Laravel or Symfony.

## Database

The module creates the site database and its user. PHP reads them in these environment variables:

    LEMP_DB_HOST  LEMP_DB_PORT  LEMP_DB_NAME  LEMP_DB_USER  LEMP_DB_PASSWORD

The `admin` account has all rights on every database, with grant option. Use it in phpMyAdmin at
`https://<host>/phpmyadmin/` to create other databases or users.

The MariaDB `root` account accepts connections only from inside the `mariadb-app` container.
The module scripts use it for the dumps and the account changes.

## Customize

Each service has custom files in the module state directory. The module creates them once, with a commented
example, and never overwrites them. They are loaded after the module settings, so they win.
The backup, the restore and the clone keep them.

| File | Service | Example |
|---|---|---|
| `nginx/custom.d/*.conf` | nginx, included in the `server` block | `location /private/ { deny all; }` |
| `php/php.d/90-custom.ini` | PHP | `max_input_vars = 5000` |
| `php/fpm.d/90-custom.conf` | PHP-FPM pool, start the file with `[www]` | `pm.max_requests = 500` |
| `mariadb/90-custom.cnf` | MariaDB server, start the file with `[mysqld]` | `max_connections = 300` |
| `crontab` | cron jobs, see [Cron](#cron) | `*/5 * * * * www-data php /app/cron.php` |

nginx ignores `.htaccess` files. Put the rewrite rules of an application in `nginx/custom.d/`.

Edit the files from the module environment:

    runagent -m lemp1
    vi php/php.d/90-custom.ini

Then save the Settings page, or run `configure-module` again. The module tests nginx, PHP-FPM, PHP and MariaDB
with the new files before the restart. A broken file stops the action with the error in the task log,
and the running site keeps its current configuration.

Check the applied values:

    runagent -m lemp1 podman exec nginx-app nginx -T
    runagent -m lemp1 podman exec php-fpm-app php -i
    runagent -m lemp1 podman exec php-fpm-app php-fpm -tt
    runagent -m lemp1 podman exec mariadb-app mariadbd --print-defaults

## Cron

The cron jobs of the site are in the `crontab` file of the module state directory. It is kept by backup,
restore and clone. The `cron-app` container runs them with the PHP image of the site.

    runagent -m lemp1
    vi crontab

Use the `/etc/cron.d` format, with a user field. Run PHP jobs as `www-data`:

    */5 * * * * www-data php /app/cron.php

Then restart the cron container, or save the Settings page:

    runagent -m lemp1 systemctl --user restart cron-app.service

Do not use `crontab -e` inside a container: that crontab is lost at the next restart.
The jobs see the `LEMP_*` variables, and `mail()` works from them. cron drops the output of the jobs:
send it to a file if you need it, outside `/app` so the web server never serves it.

## Deploy a site

The site lives in the `app` volume, mounted on `/app` in the PHP containers:

    runagent -m lemp1 podman exec -ti php-fpm-app bash

Download it with git, wget, curl, rsync, sftp, ftp or composer, then give the files to `www-data`:

    cd /app
    git clone https://example.org/my/site.git .
    chown -R www-data:www-data /app

A fresh instance has an `index.php` page and a `phpinfo.php` page. Delete them once the site is installed.
`phpinfo.php` leaves out the Environment and Variables sections: they would show the database password
that PHP-FPM gives to the site. Never call `phpinfo()` without arguments on a public page.

### WordPress example

Set `nginx_preset` to `wordpress` in the Advanced section of the Settings page, then save.

Download WordPress into the `app` volume, as `www-data`:

    runagent -m lemp1 podman exec -ti -u www-data -w /app php-fpm-app bash
    rm -f index.php phpinfo.php
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1

Create `wp-config.php` from the module variables with [WP-CLI](https://wp-cli.org/), in the same shell:

    curl -sLo /tmp/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar
    php /tmp/wp config create --dbname="$LEMP_DB_NAME" --dbuser="$LEMP_DB_USER" \
        --dbpass="$LEMP_DB_PASSWORD" --dbhost="$LEMP_DB_HOST:$LEMP_DB_PORT" --skip-check

Then open `https://<host>/` and finish the install in the browser. You can also skip WP-CLI:
the browser installer asks for the database name, user and password of the module, with `127.0.0.1` as the database host.

Pretty permalinks work with the preset. The site reaches itself through Traefik, so WP-Cron
and the Site Health loopback test work. WP-CLI in `/tmp` goes away when the container restarts.

## Mail

PHP `mail()` sends through the cluster smarthost with msmtp, when the smarthost is enabled.
The sender is `mail_from`, or `noreply@<host>` when it is empty. The SMTP EHLO name is the host name.

## LDAP

Set `user_domain` to give the bind credentials of a user domain to PHP, like ns8-lamp:

    LEMP_LDAP_HOST  LEMP_LDAP_PORT  LEMP_LDAP_SCHEMA  LEMP_LDAP_BASE  LEMP_LDAP_USER  LEMP_LDAP_PASS

The site must handle the LDAP login itself.

## Backup, restore and clone

The backup holds a dump of all databases, the `app` volume, the secrets and the custom files.
The dump keeps the MariaDB accounts, so the passwords stay the same after a restore.

A restore on a cluster without the user domain drops the LDAP variables with a warning.
A clone keeps the host name of its source but gets no web route: set a new host name in Settings.

## Volumes

`app` and `mariadb-data` can go on an additional disk (`org.nethserver.volumes`).

## Uninstall

    remove-module --no-preserve lemp1

## Testing

Test the module with the `test-module.sh` script:

    ./test-module.sh <NODE_ADDR> ghcr.io/stephdl/lemp:latest

The tests use [Robot Framework](https://robotframework.org/). The CI runs them on a QEMU node after each image build.

## Renovate

Renovate tracks every image of `build-images.sh`. MariaDB stays on 12.3, nginx on the 1.30 stable branch,
and each PHP image on its own minor version. A new PHP minor version is added by hand.

## UI translation

The UI is translated in English, French, Italian, German, Spanish, Portuguese, Brazilian Portuguese, Basque, Dutch and Arabic.
The files are in `ui/public/i18n/`. The module is not on Weblate yet.
