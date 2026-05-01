#!/usr/bin/bash

set -eoux pipefail

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Install DMS"

dnf5 copr enable -y avengemedia/danklinux
dnf5 copr enable -y avengemedia/dms
dnf5 copr enable -y yalter/niri

dnf5 install -y \
	xdg-desktop-portal-gtk \
	accountsservice \
	xwayland-satellite \
	adw-gtk3-theme \
	qt6ct \
	qt6-qtmultimedia

dnf5 install -y --setopt=install_weak_deps=False \
	niri \
	quickshell \
	matugen \
	dgop \
	dsearch \
	cava \
	khal \
	ghostty \
	dms

dnf5 copr disable -y avengemedia/danklinux
dnf5 copr disable -y avengemedia/dms
dnf5 copr disable -y yalter/niri

systemctl --global add-wants niri.service dms
systemctl --global enable dsearch
systemctl --global enable niri

echo "::endgroup::"

echo "DMS installation complete!"
echo "After booting, select 'NIRI' session at the login screen"
