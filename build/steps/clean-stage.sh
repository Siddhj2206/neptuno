#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

CLEAN_ROOT="${CLEAN_ROOT:-/}"

dnf5 config-manager setopt keepcache=0
dnf5 versionlock clear
dnf5 clean all

systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f "${CLEAN_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"

rm -rf "${CLEAN_ROOT}/.gitkeep"
find "${CLEAN_ROOT}/var"/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find "${CLEAN_ROOT}/var/cache"/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;

rm -rf "${CLEAN_ROOT:?}/tmp" && mkdir -p "${CLEAN_ROOT:?}/tmp"
rm -rf "${CLEAN_ROOT:?}/boot" && mkdir -p "${CLEAN_ROOT:?}/boot"
rm -rf "${CLEAN_ROOT:?}/run" && mkdir -p "${CLEAN_ROOT:?}/run"

echo "::endgroup::"
