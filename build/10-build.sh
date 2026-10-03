#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Overlay & Wiring — OCI overlays + custom tree (wm-agnostic)
###############################################################################

shopt -s nullglob

echo "::group:: Overlay Brew Integration Files"
rsync -rvKl /ctx/oci/brew/ /
echo "::endgroup::"

echo "::group:: Overlay Common Shared Files"
rsync -rvKl /ctx/oci/common/shared/ /

# bluefin cherry-picks (higher priority, --relative like neptuno).
# Single source of truth: rsync consumes this array, the assert loop below
# derives dests from it (rsync --relative anchors at /./).
COMMON_CHERRY_PICKS=(
	/ctx/oci/common/bluefin/./usr/share/ublue-os/just/
	/ctx/oci/common/bluefin/./usr/libexec/bonedigger-report
	/ctx/oci/common/bluefin/./usr/lib/systemd/system/dconf-update.service
	/ctx/oci/common/bluefin/./usr/share/flatpak/preinstall.d/bazaar.preinstall
	/ctx/oci/common/bluefin/./etc/bazaar/
	/ctx/oci/common/bluefin/./usr/lib/systemd/user/bazaar.service
	/ctx/oci/common/bluefin/./usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar
	/ctx/oci/common/bluefin/./usr/lib/tmpfiles.d/bazaar-flatpak.conf
)
rsync -rvK --relative "${COMMON_CHERRY_PICKS[@]}" /

# Fail closed with a clear name if `common` drops a cherry-picked path
# (a bare rsync failure above names no names).
for src in "${COMMON_CHERRY_PICKS[@]}"; do
	common_path="/${src#/ctx/oci/common/bluefin/./}"
	test -e "${common_path}" || {
		echo "ERROR: common cherry-pick missing: ${common_path}" >&2
		exit 1
	}
done

# Neptuno has never used legacy rechunker. The common migration unit creates an
# ordering cycle between local-fs.target and systemd-sysusers.service on systems
# with separate /var mounts, which can send otherwise healthy boots to emergency
# mode. Keep a vendor mask so future common overlay updates cannot re-enable it.
RECHUNKER_UNIT="/usr/lib/systemd/system/rechunker-group-fix.service"
if [[ -e "${RECHUNKER_UNIT}" || -L "${RECHUNKER_UNIT}" ]]; then
	systemctl disable rechunker-group-fix.service
fi
ln -sfn /dev/null "${RECHUNKER_UNIT}"
[[ "$(readlink "${RECHUNKER_UNIT}")" == "/dev/null" ]] || {
	echo "ERROR: failed to mask rechunker-group-fix.service" >&2
	exit 1
}

# Enable the units the common/brew overlays ship, one by one. Deliberately NOT
# `systemctl preset-all`: that applies every preset in the image, including
# Fedora's catch-all "disable *" (redhat-systemd-presets-common), so a stray
# preset can silently flip a unit we do not own. An explicit list keeps the
# enabled set visible and fails closed if a unit disappears from the overlay.
#
# The overlay preset files (common system-preset 01/02/03, user-preset
# 01-brew-preinstall; brew system-preset 01-homebrew) are shipped but no longer
# the source of truth here.
systemctl enable flatpak-appstream-refresh.service
systemctl enable uupd.timer uupd-resume.timer
systemctl enable projectbluefin-countme.timer # common also ships its .wants symlink
systemctl enable flatpak-preinstall.service # no preset — enabled explicitly
systemctl enable brew-setup.service brew-update.timer brew-upgrade.timer
systemctl --global enable brew-preinstall.service

echo "::endgroup::"

echo "::group:: Copy Custom Files"
# brew: every Brewfile auto-installed at first login (hash-tracked)
mkdir -p /usr/share/ublue-os/homebrew/preinstall.d/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/preinstall.d/

# just: Neptuno recipes alongside 00-entry.just
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# flatpak: consumed by flatpak-preinstall.service on first boot
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/
echo "::endgroup::"

echo "::group:: Copy System Files"
# custom/files -> / (units, wants, gschema)
rsync -rvKl /ctx/custom/files/ /
echo "::endgroup::"

echo "::group:: Copy User Config Defaults"
# custom/config -> /etc/skel (new users, wins over common skel)
mkdir -p /etc/skel
rsync -rvKl /ctx/custom/config/ /etc/skel/

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Overlay layer complete!"
