# ns8-lemp

Host one PHP web site on NethServer 8, with nginx, PHP-FPM, MariaDB and phpMyAdmin.

Each instance serves one host name and owns one site database.

## Containers

| Container | Image | Role |
|---|---|---|
| `nginx-app` | `docker.io/nginx:1.30.6` | web server, behind Traefik |
| `php-fpm-app` | `ghcr.io/stephdl/lemp-php8.x` | PHP of the selected version |
| `cron-app` | same image as `php-fpm-app` | cron jobs of the site |
| `mariadb-app` | `docker.io/mariadb:12.3.3` | MariaDB LTS, supported until June 2029 |
| `phpmyadmin-app` | `docker.io/phpmyadmin:5.2.3-fpm` | phpMyAdmin on a random path, see [phpMyAdmin](#phpmyadmin) |

PHP 8.2, 8.3, 8.4 and 8.5 are available. The node pulls only the selected version.

The PHP image is built from `docker.io/php:8.x-fpm-trixie`. It loads the same extensions as ns8-lamp:
gd, intl, ldap, imagick, imap, apcu, memcached, mysqli, pdo_mysql, opcache, soap, sockets, xsl, zip and more.
The build fails if one is missing.

It also ships composer, msmtp and the tools of ns8-lamp: vim, nano, git, wget, curl, zip, ftp, rsync,
ssh, sftp, scp and the mariadb client.

## Install

From the Software center, or on the leader node:

    add-module ghcr.io/stephdl/lemp:latest 1

- `latest` is the last release.
- `1` is the node that runs the instance.

The output gives the instance name, like `lemp1`.
The commands below use `lemp1`: replace it with yours.

## Configure

Use the Settings page, or `configure-module`.

Send the JSON on stdin, so the passwords stay out of the shell history:

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

HTTPS is always forced on the route.

### Passwords and database

- `db_password` and `admin_password` are required at the first configuration.
- Later, omit them to keep the current ones.
- They need 8 characters, with a lowercase letter, an uppercase letter, a digit and a symbol.
- `db_name` and `db_user` cannot change after the first configuration.

### PHP limits

The Settings page shows sliders for these values.

| Setting | Range |
|---|---|
| `php_memory_limit` | 128M to 4096M, larger than the upload limit |
| `php_upload_max_filesize` | 2M to 2048M |
| `php_max_execution_time` | 1 to 3600 seconds, or 0 for no limit |
| `fpm_pm_max_children` | 1 to 100 |

With no limit, PHP never stops the script. nginx still waits one day at most, and phpMyAdmin keeps its own 600 seconds.

An update brings values of an older release back inside these ranges.

### MariaDB memory

The module sizes the InnoDB buffer pool from the node memory: 5%, between 128 MiB and 1 GiB.

To change it, set `innodb_buffer_pool_size` in `mariadb/90-custom.cnf`.
An update moves a size set in an older release to that file.

### nginx presets

`nginx_preset` gives the rules of the application:

- `generic`: every unknown path goes to `index.php`. It fits most PHP frameworks.
- `wordpress`: the same, plus WordPress hardening. `xmlrpc.php` and `wp-config.php` are denied,
  PHP files under `wp-content/uploads/` never run, and the browser caches static files for 30 days.

In both presets:

- hidden files like `.htaccess`, `.git` and `.env` are never served;
- `.well-known/` stays served, for Let's Encrypt and other tools.

`document_root` is a subdirectory of `/app`, like `public` for Laravel or Symfony.

## Database

The module creates the site database and its user. PHP reads them in these variables:

    LEMP_DB_HOST  LEMP_DB_PORT  LEMP_DB_NAME  LEMP_DB_USER  LEMP_DB_PASSWORD

The `admin` account has all rights on every database. Use it in phpMyAdmin to create other databases or users.

The MariaDB `root` account works only inside `mariadb-app`. The module uses it for dumps and account changes.

## phpMyAdmin

phpMyAdmin is served on a random path of the site, like `https://<host>/phpmyadmin-1a2b3c4d/`.
The Status page shows the link. Bots that scan `/phpmyadmin/` do not find it.

Read the path from the command line:

    api-cli run module/lemp1/get-configuration | jq -r .phpmyadmin_path

To protect it more:

- install [CrowdSec](https://github.com/NethServer/ns8-crowdsec) on the node, it bans the clients that scan the site;
- disable phpMyAdmin in Settings when nobody uses it.

A failed phpMyAdmin login answers 200, so CrowdSec does not see a password guess on the login page.
The random path and a strong `admin` password are the real protection.

## Deploy a site

### Where the files go

The site lives in the `app` volume, on `/app`.

- `php-fpm-app` and `cron-app` can write to it.
- `nginx-app` reads it only, and has no git, curl or composer.

So always add files through `php-fpm-app`, even for a static site. nginx then serves the static files itself.

### Upload the site

Open a shell as `www-data`:

    runagent -m lemp1 podman exec -ti -u www-data -w /app php-fpm-app bash

Then download the site, with git, wget, curl, rsync, sftp, ftp or composer:

    git clone https://example.org/my/site.git .

A fresh instance has an `index.php` and a `phpinfo.php` page. Delete them once the site is installed.

`phpinfo.php` hides the Environment and Variables sections, which would show the database password.
Never call `phpinfo()` without arguments on a public page.

### Owner and modes

| What | Value | Why |
|---|---|---|
| Owner | `www-data:www-data` (uid and gid 33) | PHP-FPM and cron run as this user, and write uploads, cache and updates |
| Files | `644` | nginx runs as `nginx` (uid 101) and needs to read them |
| Folders | `755` | same reason |
| Secrets read by PHP only | `600` | like `wp-config.php`, nginx never serves them |

A static file at `600` answers 403: nginx cannot read it.

A shell opened without `-u www-data` runs as root. To fix the owner and the modes of the whole site,
use Reset permissions in Settings, under Advanced, or:

    api-cli run module/lemp1/reset-permissions

It sets the owner, `755` on folders and `644` on files, for all of `/app`.
A file that was executable, like a script run by cron, gets `755`. It works even when the site is stopped.
Run `chmod 600` again on the secrets you keep at `600`.

### WordPress

1. In Settings, open Advanced, set the nginx preset to WordPress, and save.

2. Open a shell as `www-data` and download WordPress:

       runagent -m lemp1 podman exec -ti -u www-data -w /app php-fpm-app bash
       rm -f index.php phpinfo.php
       curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1

3. In the same shell, create `wp-config.php` with [WP-CLI](https://wp-cli.org/):

       curl -sLo /tmp/wp https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar
       php /tmp/wp config create --dbname="$LEMP_DB_NAME" --dbuser="$LEMP_DB_USER" \
           --dbpass="$LEMP_DB_PASSWORD" --dbhost="$LEMP_DB_HOST:$LEMP_DB_PORT" --skip-check

   This step is optional. Without it, the browser installer asks for the database name, user and password,
   with `127.0.0.1` as the host.

4. Open `https://<host>/` and finish the install: site title, admin user and password.

   Without Let's Encrypt, the certificate is self-signed and the browser shows a warning first.

What works with the preset:

- pretty permalinks;
- WP-Cron and the Site Health loopback test, because the site reaches itself through Traefik;
- mail, through the cluster smarthost;
- phpMyAdmin, with the `admin` account.

WP-CLI lives in `/tmp`, so it goes away when the container restarts. Download it again to use it.

## Customize

### Custom files

Each service has a custom file in the module state directory.

- The module creates it once, with a commented example, and never overwrites it.
- It loads after the module settings, so it wins.
- Backup, restore and clone keep it.

| File | Service | Example |
|---|---|---|
| `nginx/custom.d/*.conf` | nginx, inside the `server` block | `location /private/ { deny all; }` |
| `php/php.d/90-custom.ini` | PHP | `max_input_vars = 5000` |
| `php/fpm.d/90-custom.conf` | PHP-FPM pool, start with `[www]` | `pm.max_requests = 500` |
| `mariadb/90-custom.cnf` | MariaDB, start with `[mysqld]` | `max_connections = 300` |
| `crontab` | cron jobs, see [Cron](#cron) | `*/5 * * * * www-data php /app/cron.php` |

### Edit and apply

Edit the files from the module environment:

    runagent -m lemp1
    vi php/php.d/90-custom.ini

Then save the Settings page, or run `configure-module` again.

The module tests nginx, PHP-FPM, PHP and MariaDB with the new files before the restart.
A broken file stops the action, with the error in the task log. The running site keeps its configuration.

Check the applied values:

    runagent -m lemp1 podman exec nginx-app nginx -T
    runagent -m lemp1 podman exec php-fpm-app php -i
    runagent -m lemp1 podman exec php-fpm-app php-fpm -tt
    runagent -m lemp1 podman exec mariadb-app mariadbd --print-defaults

### From .htaccess to nginx

nginx never reads a `.htaccess` file, and never serves it. It can stay in the site.

WordPress, and the frameworks that send every request to `index.php`, need no rule: the preset does it.

Other rules go in a file of `nginx/custom.d/`, like `50-app.conf`:

| Apache `.htaccess` | nginx `custom.d` |
|---|---|
| `RewriteRule ^old/(.*)$ /new/$1 [R=301,L]` | `rewrite ^/old/(.*)$ /new/$1 permanent;` |
| `Require all denied` in `private/` | `location ^~ /private/ { deny all; }` |
| `RewriteRule ^article/([0-9]+)$ index.php?id=$1 [L]` | `location ~ ^/article/([0-9]+)$ { try_files $uri /index.php?id=$1; }` |

A `php_value` line is not for nginx. Put it in `php/php.d/90-custom.ini`, without the prefix:
`php_value max_input_vars 5000` becomes `max_input_vars = 5000`.

### nginx examples

Each block goes in a file of `nginx/custom.d/`. They were tested together on one instance.

**Password on a folder.** Create the password file first, `editor` being the user name:

    runagent -m lemp1
    printf 'editor:%s\n' "$(podman exec -i php-fpm-app openssl passwd -apr1 -stdin <<<'<password>')" > nginx/custom.d/htpasswd

Then the rule:

    location ^~ /admin-area/ {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/lemp-custom.d/htpasswd;
    }

**One network only.** The module trusts the client address sent by Traefik, so the real address is checked:

    location ^~ /intranet/ {
        allow 192.168.1.0/24;
        deny all;
    }

**Browser cache for static files.** The `wordpress` preset already does it:

    location ~* \.(?:css|js|png|jpe?g|gif|svg|webp|woff2?)$ {
        expires 30d;
        access_log off;
    }

**Compression and security headers:**

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

A `location` with its own `add_header` loses the headers set outside it: repeat them inside.

**Fixed answer for a monitoring probe:**

    location = /health { return 200 "ok\n"; }

## Cron

The cron jobs are in the `crontab` file of the module state directory.
`cron-app` runs them with the PHP image of the site. Backup, restore and clone keep the file.

Edit it:

    runagent -m lemp1
    vi crontab

Use the `/etc/cron.d` format, with a user field. Run PHP jobs as `www-data`:

    */5 * * * * www-data php /app/cron.php

Apply it by saving the Settings page, or:

    runagent -m lemp1 systemctl --user restart cron-app.service

Do not use `crontab -e` in a container: that crontab is lost at the next restart.

The jobs see the `LEMP_*` variables, and `mail()` works from them. Their output goes to the journal:

    journalctl _UID=$(id -u lemp1) CONTAINER_NAME=cron-app

## Mail

PHP `mail()` sends through the cluster smarthost, with msmtp, when the smarthost is enabled.

- The sender is `mail_from`, or `noreply@<host>` when it is empty.
- The SMTP EHLO name is the host name.

## LDAP

Set `user_domain` to give the bind credentials of a user domain to PHP, like ns8-lamp:

    LEMP_LDAP_HOST  LEMP_LDAP_PORT  LEMP_LDAP_SCHEMA  LEMP_LDAP_BASE  LEMP_LDAP_USER  LEMP_LDAP_PASS

The site must handle the LDAP login itself.

## Backup, restore and clone

The backup holds:

- a dump of all databases, with the MariaDB accounts, so the passwords stay the same;
- the `app` volume;
- the secrets and the custom files.

A restore on a cluster without the user domain drops the LDAP variables, with a warning.

A restore keeps the host name, even when the original instance still runs on the same node.
Both then share the host until you remove the original, or set a new host name on one of them.

A clone keeps the host name of its source, but gets no web route. Set a new host name in Settings.

## Volumes

`app` and `mariadb-data` can go on an additional disk (`org.nethserver.volumes`).

## Uninstall

    remove-module --no-preserve lemp1

## Testing

    ./test-module.sh <NODE_ADDR> ghcr.io/stephdl/lemp:latest

The tests use [Robot Framework](https://robotframework.org/). The CI runs them on a QEMU node after each image build.

## Renovate

Renovate tracks every image of `build-images.sh`:

- MariaDB stays on 12.3;
- nginx stays on the 1.30 stable branch;
- each PHP image stays on its own minor version.

A new PHP minor version is added by hand.

## UI translation

The UI is in English, French, Italian, German, Spanish, Portuguese, Brazilian Portuguese, Basque, Dutch and Arabic.

The files are in `ui/public/i18n/`. The module is not on Weblate yet.
