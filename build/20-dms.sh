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
systemctl --global enable niri

# Using isolated pattern to prevent COPR from persisting
# copr_install_isolated "avengemedia/danklinux" \
#     cosmic-session \
#     cosmic-greeter \
#     cosmic-comp \
#     cosmic-panel \
#     cosmic-launcher \
#     cosmic-applets \
#     cosmic-settings \
#     cosmic-files \
#     cosmic-edit \
#     cosmic-term \
#     cosmic-workspaces

# echo "COSMIC desktop installed successfully"
echo "::endgroup::"

echo "::group:: Configure Display Manager"

# Enable cosmic-greeter (COSMIC's display manager)
# systemctl enable cosmic-greeter

# Set COSMIC as default session
# mkdir -p /etc/X11/sessions
# cat > /etc/X11/sessions/cosmic.desktop << 'COSMICDESKTOP'
# [Desktop Entry]
# Name=COSMIC
# Comment=COSMIC Desktop Environment
# Exec=cosmic-session
# Type=Application
# DesktopNames=COSMIC
# COSMICDESKTOP

echo "Display manager configured"
echo "::endgroup::"

echo "::group:: Install Additional Utilities"

# Install additional utilities that work well with COSMIC
# dnf5 install -y \
#     kitty \
#     flatpak \
#     xdg-desktop-portal-cosmic

echo "Additional utilities installed"
echo "::endgroup::"

echo "DMS installation complete!"
echo "After booting, select 'NIR' session at the login screen"
