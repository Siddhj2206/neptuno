#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -eoux pipefail for strict error handling and debugging.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/steps/copr-helpers.sh

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: Overlay System Files from OCI Containers"

# Brew integration files (lowest priority)
rsync -rvK /ctx/oci/brew/ /

# Shared system files from projectbluefin/common (medium priority)
rsync -rvK /ctx/oci/common/shared/ /

echo "::endgroup::"

echo "::group:: Copy Bluefin Config from Common"

# Copy just files from @projectbluefin/common (includes 00-entry.just which imports 60-custom.just)
mkdir -p /usr/share/ublue-os/just/
shopt -s nullglob
cp -r /ctx/oci/common/bluefin/usr/share/ublue-os/just/* /usr/share/ublue-os/just/
shopt -u nullglob

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /etc/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /etc/flatpak/preinstall.d/

# Copy config files to skel
mkdir -p /etc/skel/
cp -r /ctx/custom/config/ /etc/skel/.config/

echo "::endgroup::"

echo "::group:: Remove Excluded Packages"

dnf5 remove -y \
	default-fonts-cjk-sans \
	fedora-bookmarks \
	fedora-third-party \
	firefox firefox-langpacks \
	gnome-extensions-app \
	gnome-software gnome-software-rpm-ostree \
	gnome-terminal-nautilus \
	google-noto-sans-cjk-vf-fonts \
	podman-docker \
	totem-video-thumbnailer \
	yelp || true

echo "::endgroup::"

echo "::group:: Install Packages"

dnf5 install -y -x PackageKit* \
	git gum make unzip dnf-plugins-core libwayland-server golang-bin \
	fish zsh bash-color-prompt \
	vim tmux htop nvtop glow fastfetch just symlinks \
	tailscale wireguard-tools iwd waypipe wl-clipboard \
	ddcutil input-remapper lm_sensors powertop smartmontools evtest \
	borgbackup restic rclone samba-client \
	gcc gcc-c++ python3-pip python3-pygit2 distrobox git-credential-libsecret \
	pam-u2f pamu2fcfg yubikey-manager openssh-askpass \
	ifuse libimobiledevice libimobiledevice-utils usbmuxd \
	hplip printer-driver-brlaser \
	containerd flatpak-spawn \
	gnome-tweaks adw-gtk3-theme xdg-terminal-exec \
	jetbrains-mono-fonts-all adwaita-fonts-all opendyslexic-fonts

echo "::endgroup::"

echo "::group:: Install Multimedia Codecs"

# Enable negativo17 fedora-multimedia repo for hardware codec support
dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo

dnf5 install -y \
	ffmpeg ffmpeg-libs libavcodec \
	gstreamer1-plugins-bad-free gstreamer1-plugins-bad-free-libs \
	gstreamer1-plugins-good gstreamer1-plugins-base \
	lame lame-libs \
	libfdk-aac \
	libjxl \
	ffmpegthumbnailer \
	mesa-dri-drivers mesa-vulkan-drivers mesa-libEGL mesa-libGL mesa-libgbm mesa-filesystem \
	libva libva-intel-media-driver intel-gmmlib intel-mediasdk intel-vpl-gpu-rt \
	intel-vaapi-driver \
	libheif

# Versionlock mesa packages from negativo17 to prevent accidental upgrades
dnf5 versionlock add \
	mesa-dri-drivers mesa-vulkan-drivers mesa-libEGL mesa-libGL mesa-libgbm mesa-filesystem

# Disable third-party repo after install (packages are baked into the image)
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/fedora-multimedia.repo

echo "::endgroup::"

echo "::group:: Install COPR Packages"

# Nerd Fonts (che/nerd-fonts)
copr_install_isolated "che/nerd-fonts" nerd-fonts

# uupd auto-update service (ublue-os/packages)
copr_install_isolated "ublue-os/packages" uupd

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable systemd services
systemctl enable podman.socket
systemctl enable brew-setup.service
systemctl enable flatpak-preinstall.service
systemctl enable ublue-system-setup.service
systemctl enable input-remapper.service
systemctl enable tailscaled.service
systemctl enable bootc-unified-storage.service
systemctl enable uupd.timer
systemctl enable podman-auto-update.timer --global 2>/dev/null || true

# Mask Fedora flatpak service (replaced by Flathub)
systemctl disable flatpak-add-fedora-repos.service 2>/dev/null || true
systemctl mask flatpak-add-fedora-repos.service 2>/dev/null || true

# Add Flathub remote
flatpak remote-add --system --if-not-exists flathub \
	https://flathub.org/repo/flathub.flatpakrepo

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"
