#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

echo "::group:: Disable Third-Party Repos"

# Disable all COPR repos added during build
for copr in avengemedia/danklinux avengemedia/dms yalter/niri; do
    dnf5 copr disable -y "$copr" 2>/dev/null || true
done

# Disable fedora-multimedia (negativo17)
dnf5 config-manager setopt fedora-multimedia.enabled=0 2>/dev/null || true

# Disable tailscale (used with --enablerepo during build)
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/tailscale.repo 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Validate Third-Party Repos"
# Ensure no third-party repos are left enabled
for repo_file in /etc/yum.repos.d/*.repo; do
    repo_name=$(basename "$repo_file" .repo)
    case "$repo_name" in
        fedora-cisco-openh264|fedora*)
            continue
            ;;
        *)
            if grep -q "^enabled=1" "$repo_file" 2>/dev/null; then
                echo "ERROR: Third-party repo $repo_file still enabled!"
                exit 1
            fi
            ;;
    esac
done
echo "All repos properly disabled."
echo "::endgroup::"

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
