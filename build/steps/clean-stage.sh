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

# Validation of all repo files moved to build/steps/validate-repos.sh,
# called from build.sh right after this step.

CLEAN_ROOT="${CLEAN_ROOT:-/}"

dnf5 versionlock clear

# Do NOT run `dnf5 clean all` or setopt keepcache=0 here.
# /var/cache/libdnf5 and /var/cache/rpm-ostree are buildah cache mounts
# (external to the image, wired in the Containerfile RUN), so the RPMs and
# repo metadata left there never end up in layers. The post-build
# bootc-build/dnf-cache save step tarballs them, so the next build restores
# ~1 GiB of packages instead of re-downloading (~10 min of cumulative speed).

systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f "${CLEAN_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"

rm -rf "${CLEAN_ROOT}/.gitkeep"
find "${CLEAN_ROOT}/var"/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find "${CLEAN_ROOT}/var/cache"/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;

rm -rf "${CLEAN_ROOT:?}/tmp"/* "${CLEAN_ROOT:?}/tmp"/.[!.]* 2>/dev/null || true
rm -rf "${CLEAN_ROOT:?}/boot"/* "${CLEAN_ROOT:?}/boot"/.[!.]* 2>/dev/null || true
rm -rf "${CLEAN_ROOT:?}/run"/* "${CLEAN_ROOT:?}/run"/.[!.]* 2>/dev/null || true

echo "::endgroup::"
