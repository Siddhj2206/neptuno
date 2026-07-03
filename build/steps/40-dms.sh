#!/usr/bin/bash

set -eoux pipefail

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/steps/copr-helpers.sh

echo "::group:: Install DMS"

# Enable COPRs (disabled in clean-stage.sh)
dnf5 copr enable -y avengemedia/danklinux
dnf5 copr enable -y avengemedia/dms
dnf5 copr enable -y yalter/niri

dnf5 install -y \
	xdg-desktop-portal-gtk \
	xdg-desktop-portal-gnome \
	accountsservice \
	xwayland-satellite \
	adw-gtk3-theme \
	qt6ct \
	qt6-qtmultimedia

dnf5 install -y --setopt=install_weak_deps=False \
	niri \
	quickshell-git \
	matugen \
	dgop \
	dsearch \
	cava \
	khal \
	dms

systemctl --global add-wants niri.service dms
# systemctl --global enable dsearch
systemctl --global enable niri

echo "::endgroup::"

# Flatpak theme overrides
flatpak override --filesystem=xdg-data/themes
flatpak mask org.gtk.Gtk3theme.adw-gtk3
flatpak mask org.gtk.Gtk3theme.adw-gtk3-dark

echo "DMS installation complete!"
echo "After booting, select 'NIRI' session at the login screen"
