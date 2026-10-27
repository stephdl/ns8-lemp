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

Install it from the Software center, or on the leader node:

    add-module ghcr.io/stephdl/lemp:latest 1

`latest` is the last release, and `1` is the node that runs the instance. The output gives the instance name,
for example `lemp1`. The commands below use `lemp1`: replace it with your instance name.

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
`php_memory_limit` goes from 128M to 4096M and must be larger than `php_upload_max_filesize`, which goes from 2M
to 2048M. `fpm_pm_max_children` goes from 1 to 100. `php_max_execution_time` goes up to 3600 seconds, and 0 removes
the PHP limit: nginx then waits one day for the response, and phpMyAdmin keeps its own 600 seconds.
The Settings page shows sliders for these values. An update brings older values inside these ranges.

The module sizes the MariaDB InnoDB buffer pool from the node memory: 5%, between 128 MiB and 1 GiB.
Set `innodb_buffer_pool_size` in `mariadb/90-custom.cnf` to change it. An update moves a buffer pool size set
in an older release to that file.

HTTPS is always forced on the route.

### nginx presets

nginx ignores `.htaccess` files. `nginx_preset` gives the rewrite rules:

- `generic`: every unknown path goes to `index.php`, which fits most PHP frameworks.
- `wordpress`: the same, plus WordPress hardening. `xmlrpc.php` is denied, and PHP files under `wp-content/uploads/` never run.

In both presets, hidden files (`.htaccess`, `.git`, `.env`) are never served. `.well-known/` stays served,
because Let's Encrypt and other tools need it.

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

nginx ignores `.htaccess` files. Put the rules of an application in a file of `nginx/custom.d/`, for example
`nginx/custom.d/50-app.conf`. Some Apache rules and their nginx form:

| Apache `.htaccess` | nginx `custom.d` |
|---|---|
| `RewriteRule ^old/(.*)$ /new/$1 [R=301,L]` | `rewrite ^/old/(.*)$ /new/$1 permanent;` |
| `Require all denied` in a `private/` folder | `location ^~ /private/ { deny all; }` |
| `RewriteRule ^article/([0-9]+)$ index.php?id=$1 [L]` | `location ~ ^/article/([0-9]+)$ { try_files $uri /index.php?id=$1; }` |
| `php_value max_input_vars 5000` | not in nginx: `max_input_vars = 5000` in `php/php.d/90-custom.ini` |

A `.htaccess` file can stay in the site: nginx never reads it and never serves it. WordPress and the frameworks
that send every request to `index.php` need no rule, the preset does it.

### nginx examples

Each block below goes in a file of `nginx/custom.d/`. They were tested together on one instance.

Ask for a password on a folder. Create the password file in the same directory, `editor` being the user name:

    runagent -m lemp1
    printf 'editor:%s\n' "$(podman exec -i php-fpm-app openssl passwd -apr1 -stdin <<<'<password>')" > nginx/custom.d/htpasswd

    location ^~ /admin-area/ {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/lemp-custom.d/htpasswd;
    }

Allow one network only. The module trusts the client address that Traefik sends, so the real address is checked:

    location ^~ /intranet/ {
        allow 192.168.1.0/24;
        deny all;
    }

Keep the static files one month in the browser cache. The `wordpress` preset already does it:

    location ~* \.(?:css|js|png|jpe?g|gif|svg|webp|woff2?)$ {
        expires 30d;
        access_log off;
    }

Compress text answers, and add security headers to every answer:

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

A `location` that sets its own `add_header` loses the headers set outside it: repeat them inside.

Answer a fixed text on one path, for a monitoring probe:

    location = /health { return 200 "ok\n"; }

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
The jobs see the `LEMP_*` variables, and `mail()` works from them. Their output goes to the journal:

    journalctl _UID=$(id -u lemp1) CONTAINER_NAME=cron-app

## Deploy a site

The site lives in the `app` volume. `php-fpm-app` and `cron-app` mount it on `/app` with write access.
`nginx-app` mounts it read only and has no tools, so always add files through `php-fpm-app`,
even for a static site with no PHP. nginx then serves the static files itself.

Open a shell as `www-data`, the user of the web server and of PHP:

    runagent -m lemp1 podman exec -ti -u www-data -w /app php-fpm-app bash

Download the site with git, wget, curl, rsync, sftp, ftp or composer:

    git clone https://example.org/my/site.git .

A shell opened without `-u www-data` runs as root. Then give the files to `www-data` at the end:

    chown -R www-data:www-data /app

The files belong to `www-data:www-data` (uid and gid 33): PHP-FPM and cron run as this user, and write the
uploads, the cache and the updates. Keep files at `644` and folders at `755`, the default of the shell.
nginx runs as another user, `nginx` (uid 101), and serves the static files itself, so it needs the read right
for others: a static file at `600` answers 403. A secret that only PHP reads, like `wp-config.php`, can be `600`.

To fix the owner and the modes of the whole site, run as root:

    runagent -m lemp1 podman exec php-fpm-app sh -c 'chown -R www-data:www-data /app && find /app -type d -exec chmod 755 {} + && find /app -type f -exec chmod 644 {} +'

It also sets the secrets back to `644`: run `chmod 600` on them again afterwards.

A fresh instance has an `index.php` page and a `phpinfo.php` page. Delete them once the site is installed.
`phpinfo.php` leaves out the Environment and Variables sections: they would show the database password
that PHP-FPM gives to the site. Never call `phpinfo()` without arguments on a public page.

### WordPress example

1. In Settings, open the Advanced section, set the nginx preset to WordPress, then save.

2. Open a shell as `www-data` and download WordPress into the `app` volume:

       runagent -m lemp1 podman exec -ti -u www-data -w /app php-fpm-app bash
       rm -f index.php phpinfo.php
       curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1

3. In the same shell, create `wp-config.php` from the module variables with [WP-CLI](https://wp-cli.org/):

       curl -sLo /tmp/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar
       php /tmp/wp config create --dbname="$LEMP_DB_NAME" --dbuser="$LEMP_DB_USER" \
           --dbpass="$LEMP_DB_PASSWORD" --dbhost="$LEMP_DB_HOST:$LEMP_DB_PORT" --skip-check

   You can skip this step: the browser installer then asks for the database name, user and password of the
   module, with `127.0.0.1` as the database host.

4. Open `https://<host>/` and finish the install: site title, admin user and password.
   Without Let's Encrypt the certificate is self-signed, and the browser shows a warning first.

Pretty permalinks work with the preset. The site reaches itself through Traefik, so WP-Cron and the Site Health
loopback test work, and WordPress sends mail through the cluster smarthost. phpMyAdmin stays on
`https://<host>/phpmyadmin/`, with the `admin` account.

WP-CLI lives in `/tmp` and goes away when the container restarts: download it again to use it.

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
