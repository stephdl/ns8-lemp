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
    ("phpmyadmin_enabled", "PHPMYADMIN_ENABLED", True, bool),
    ("db_name", "DB_NAME", "app", str),
    ("db_user", "DB_USER", "app", str),
    ("user_domain", "USER_DOMAIN", "", str),
    ("mail_from", "MAIL_FROM", "", str),
]

ENV_VARS = [var for _, var, _, _ in SETTINGS]

MAX_EXECUTION_TIME = 3600


def size_mib(size):
    # PHP size like 512M, 1G or 1536K, in MiB
    number, unit = int(size[:-1]), size[-1].upper()
    return number * {"K": 1 / 1024, "M": 1, "G": 1024}[unit]


def memory_fits_upload(data):
    # A whole request body must fit in memory_limit, with room for the script itself
    return size_mib(data["php_memory_limit"]) > size_mib(data["php_upload_max_filesize"])


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
    # Settings saved by an older release may break newer rules: bring them back in range,
    # so a clone or a restore of that release never fails its validation
    request["php_max_execution_time"] = min(request["php_max_execution_time"], MAX_EXECUTION_TIME)
    if not memory_fits_upload(request):
        request["php_memory_limit"] = f"{int(size_mib(request['php_upload_max_filesize'])) * 2}M"
    return request


def php_image(image_url, version):
    # Same registry and tag as the module image, e.g. ghcr.io/stephdl/lemp-php8.4:1.0.0
    repository, tag = image_url.rsplit(":", 1)
    return f"{repository}-php{version}:{tag}"
