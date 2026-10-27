#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# The module settings in one place: configure, clone and restore all read this list

# (configure-module field, environment variable, default, type)
SETTINGS = [
    ("host", "TRAEFIK_HOST", "", str),
    ("lets_encrypt", "TRAEFIK_LETS_ENCRYPT", False, bool),
    ("php_version", "PHP_VERSION", "8.4", str),
    ("document_root", "DOCUMENT_ROOT", "", str),
    ("nginx_preset", "NGINX_PRESET", "generic", str),
    ("php_memory_limit", "PHP_MEMORY_LIMIT", "512M", str),
    ("php_upload_max_filesize", "PHP_UPLOAD_MAX_FILESIZE", "100M", str),
    ("php_max_execution_time", "PHP_MAX_EXECUTION_TIME", 600, int),
    ("php_timezone", "PHP_TIMEZONE", "UTC", str),
    ("fpm_pm_max_children", "FPM_PM_MAX_CHILDREN", 10, int),
    ("mariadb_innodb_buffer_pool_size", "MARIADB_INNODB_BUFFER_POOL_SIZE", "256M", str),
    ("phpmyadmin_enabled", "PHPMYADMIN_ENABLED", True, bool),
    ("db_name", "DB_NAME", "app", str),
    ("db_user", "DB_USER", "app", str),
    ("user_domain", "USER_DOMAIN", "", str),
    ("mail_from", "MAIL_FROM", "", str),
]

ENV_VARS = [var for _, var, _, _ in SETTINGS]


def env_from_request(data):
    env = {var: str(data[field]) for field, var, _, _ in SETTINGS}
    env["DOCUMENT_ROOT"] = env["DOCUMENT_ROOT"].strip("/")
    return env


def request_from_env(env):
    request = {}
    for field, var, default, kind in SETTINGS:
        value = env.get(var)
        if value is None:
            request[field] = default
        elif kind is bool:
            request[field] = value == "True"
        else:
            request[field] = kind(value)
    return request


def php_image(image_url, version):
    # Same registry and tag as the module image, e.g. ghcr.io/stephdl/lemp-php8.4:1.0.0
    repository, tag = image_url.rsplit(":", 1)
    return f"{repository}-php{version}:{tag}"
