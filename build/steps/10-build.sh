#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -eoux pipefail for strict error handling and debugging.
###############################################################################

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

# Remove ublue-os base packages before rsyncing OCI container files
dnf5 remove -y \
    ublue-os-luks \
    ublue-os-just \
    ublue-os-udev-rules \
    ublue-os-signing \
    ublue-os-update-services \
    2>/dev/null || true

echo "::group:: Overlay System Files from OCI Containers"

# Brew integration files (lowest priority)
rsync -rvK /ctx/oci/brew/ /

# Shared system files from projectbluefin/common (medium priority)
rsync -rvK /ctx/oci/common/shared/ /

# Bluefin-specific non-GNOME configs (higher priority, overrides shared)
rsync -rvK --relative \
    /ctx/oci/common/bluefin/./etc/zsh/ \
    /ctx/oci/common/bluefin/./usr/bin/umotd \
    /ctx/oci/common/bluefin/./usr/share/fish/ \
    /ctx/oci/common/bluefin/./usr/lib/dracut/ \
    /

echo "::endgroup::"

echo "::group:: Copy Bluefin Config from Common"

# Copy just files from @projectbluefin/common (includes 00-entry.just which imports 60-custom.just)
mkdir -p /usr/share/ublue-os/just/
shopt -s nullglob
cp -r /ctx/oci/common/bluefin/usr/share/ublue-os/just/* /usr/share/ublue-os/just/
shopt -u nullglob

echo "::endgroup::"

echo "::group:: Copy Local Files"

# Blanket rsync of custom files (overrides OCI containers and RPMs)
rsync -rvK /ctx/custom/files/ / 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

# Copy Flatpak system overrides (Bazaar needs host-etc for remote management)
mkdir -p /etc/flatpak/overrides/
cp -r /ctx/oci/common/bluefin/usr/share/ublue-os/flatpak-overrides/* /etc/flatpak/overrides/ 2>/dev/null || true

# Copy config files to skel
mkdir -p /etc/skel/
cp -r /ctx/custom/config/ /etc/skel/.config/

# Restore default glob behavior
shopt -u nullglob

echo "Custom files overlay complete!"
