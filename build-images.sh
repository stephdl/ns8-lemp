#!/bin/bash

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error, also when a build fails behind the log prefix pipe
set -e -o pipefail

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/nethserver}"
# Configure the image name
reponame="lemp"

# Runtime images, pulled by the module
mariadb_image="docker.io/mariadb:12.3.3"
nginx_image="docker.io/nginx:1.30.6"
phpmyadmin_image="docker.io/phpmyadmin:5.2.3-fpm"

# Bases of the PHP-FPM images built below, one per supported PHP branch
php_images=(
    "docker.io/php:8.2.35-fpm-trixie"
    "docker.io/php:8.3.36-fpm-trixie"
    "docker.io/php:8.4.27-fpm-trixie"
    "docker.io/php:8.5.12-fpm-trixie"
)
composer_image="docker.io/composer:2.10.3"
node_image="docker.io/library/node:24.22.1"
extension_installer_image="docker.io/mlocati/php-extension-installer:2.12.3"

# The About page shows the stack versions: the module version does not tell them
metadata_file="ui/public/metadata.json"
metadata_backup=$(mktemp)
cleanup() {
    cp "${metadata_backup}" "${metadata_file}"
    rm -f "${metadata_backup}"
}
cp "${metadata_file}" "${metadata_backup}"
trap cleanup EXIT
jq --arg v "nginx ${nginx_image##*:}, MariaDB ${mariadb_image##*:}" \
   '.upstream_name |= gsub("version set automatically"; $v)' \
   "${metadata_file}" > "${metadata_file}.tmp" && mv "${metadata_file}.tmp" "${metadata_file}"

# Build the PHP-FPM images in parallel, their logs are prefixed by version
pids=()
for php_image in "${php_images[@]}"; do
    php_tag="${php_image#*:}"
    php_minor="${php_tag%.*}"
    (
        buildah build \
            --force-rm \
            --layers \
            --build-arg "PHP_IMAGE=${php_image}" \
            --build-arg "COMPOSER_IMAGE=${composer_image}" \
            --build-arg "EXTENSION_INSTALLER_IMAGE=${extension_installer_image}" \
            --tag "${repobase}/${reponame}-php${php_minor}" \
            --file container/Containerfile \
            container 2>&1 | sed -u "s/^/[PHP ${php_minor}] /"
    ) &
    pids+=("$!")
    images+=("${repobase}/${reponame}-php${php_minor}")
done
for pid in "${pids[@]}"; do
    wait "${pid}"
done

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-lemp container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-lemp; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-lemp -v "${PWD}:/usr/src:Z" "${node_image}"
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-lemp \
    sh -c "corepack enable && yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui

# The PHP-FPM images are not listed in org.nethserver.images: the module pulls
# only the one of the selected PHP version
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm cluster:accountconsumer" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.min-core=3.20.1" \
    --label="org.nethserver.images=${mariadb_image} ${nginx_image} ${phpmyadmin_image}" \
    --label="org.nethserver.volumes=app mariadb-data" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# Setup CI when pushing to Github.
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
