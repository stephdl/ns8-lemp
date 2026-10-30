#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# The module settings in one place: configure, clone and restore all read this list

import math
import re
import secrets

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

# Ranges of the Settings sliders, enforced by configure-module too
MEMORY_LIMIT_MIB = (128, 4096)
UPLOAD_MAX_FILESIZE_MIB = (2, 2048)
MAX_EXECUTION_TIME = 3600
FPM_MAX_CHILDREN = (1, 100)
# Same pattern as configure-module: no . or .. segment, so nginx stays inside /app
DOCUMENT_ROOT_PATTERN = re.compile(r"^(?!(.*/)?\.{1,2}(/|$))([A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*)?$")


def size_mib(size):
    # PHP size like 512M, 1G or 1536K, in MiB
    number, unit = int(size[:-1]), size[-1].upper()
    return number * {"K": 1 / 1024, "M": 1, "G": 1024}[unit]


def memory_fits_upload(data):
    # A whole request body must fit in memory_limit, with room for the script itself
    return size_mib(data["php_memory_limit"]) > size_mib(data["php_upload_max_filesize"])


def clamp_size(size, bounds):
    low, high = bounds
    return f"{min(max(math.ceil(size_mib(size)), low), high)}M"


def normalize(request):
    # Bring settings saved by an older release, or set through the API, inside the
    # current rules: the Settings page can show them and configure-module accepts them
    request["php_upload_max_filesize"] = clamp_size(request["php_upload_max_filesize"], UPLOAD_MAX_FILESIZE_MIB)
    request["php_memory_limit"] = clamp_size(request["php_memory_limit"], MEMORY_LIMIT_MIB)
    if not DOCUMENT_ROOT_PATTERN.match(request["document_root"]):
        request["document_root"] = ""
    if not memory_fits_upload(request):
        upload = size_mib(request["php_upload_max_filesize"])
        request["php_memory_limit"] = clamp_size(f"{int(upload) * 2}M", MEMORY_LIMIT_MIB)
    if request["php_max_execution_time"] != 0:
        request["php_max_execution_time"] = min(max(request["php_max_execution_time"], 1), MAX_EXECUTION_TIME)
    low, high = FPM_MAX_CHILDREN
    request["fpm_pm_max_children"] = min(max(request["fpm_pm_max_children"], low), high)
    return request


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
    return normalize(request)


def new_phpmyadmin_path():
    # A random path keeps phpMyAdmin out of the bots that scan /phpmyadmin/
    return "phpmyadmin-" + secrets.token_hex(4)


def phpmyadmin_path(env):
    # An instance without a path predates the random one
    return env.get("PHPMYADMIN_PATH") or "phpmyadmin"


def php_image(image_url, version):
    # Same registry and tag as the module image, e.g. ghcr.io/stephdl/lemp-php8.4:1.0.0
    repository, tag = image_url.rsplit(":", 1)
    return f"{repository}-php{version}:{tag}"
