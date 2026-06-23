#!/usr/bin/bash

set -eoux pipefail

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/steps/copr-helpers.sh

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: Remove Excluded Packages"

# Swap fedora-logos for generic (saves ~15-20 MB)
dnf5 -y swap fedora-logos generic-logos 2>/dev/null || true
rpm --erase --nodeps --nodb generic-logos 2>/dev/null || true

dnf5 remove -y \
	default-fonts-cjk-sans \
	fedora-bookmarks \
	fedora-chromium-config \
	fedora-chromium-config-gnome \
	fedora-third-party \
	firefox firefox-langpacks \
	gnome-extensions-app \
	gnome-shell-extension-background-logo \
	gnome-software gnome-software-rpm-ostree \
	gnome-terminal-nautilus \
	google-noto-sans-cjk-vf-fonts \
	podman-docker \
	ptyxis \
	totem-video-thumbnailer \
	yelp || true

echo "::endgroup::"

echo "::group:: Install Packages"

# Enable tailscale repo (disabled, used with --enablerepo for security)
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 config-manager setopt tailscale-stable.enabled=0

dnf5 install -y -x 'PackageKit*' \
	--enablerepo=tailscale-stable \
	git gum make unzip dnf-plugins-core libwayland-server golang-bin \
	fish zsh bash-color-prompt \
	vim tmux htop nvtop glow fastfetch just symlinks fzf \
	tailscale wireguard-tools iwd waypipe wl-clipboard \
	ddcutil input-remapper lm_sensors powertop smartmontools evtest \
	borgbackup restic rclone samba-client \
	gcc gcc-c++ python3-pip python3-pygit2 distrobox git-credential-libsecret \
	pam-u2f pamu2fcfg yubikey-manager openssh-askpass pam_yubico \
	ifuse libimobiledevice libimobiledevice-utils usbmuxd \
	hplip printer-driver-brlaser \
	containerd flatpak-spawn \
	gnome-tweaks adw-gtk3-theme xdg-terminal-exec \
	jetbrains-mono-fonts-all adwaita-fonts-all opendyslexic-fonts \
	alsa-firmware alsa-tools-firmware \
	nautilus-gsconnect \
	switcheroo-control \
	libratbag-ratbagd \
	solaar-udev \
	libcamera-gstreamer libcamera-tools \
	squashfs-tools \
	grub2-tools-extra \
	zenity \
	openrgb-udev-rules \
	powerstat \
	gnupg2-scdaemon \
	gnome-keyring \
	xdg-user-dirs

echo "::endgroup::"

echo "::group:: Install Multimedia Codecs"

# Enable negativo17 fedora-multimedia repo for hardware codec support
dnf5 config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo
dnf5 config-manager setopt fedora-multimedia.priority=90

# distro-sync mesa and Intel driver packages from negativo17
# (replaces Fedora's crippled versions with full codec support)
OVERRIDES=(
	intel-gmmlib
	intel-mediasdk
	intel-vpl-gpu-rt
	libheif
	libva
	libva-intel-media-driver
	mesa-dri-drivers
	mesa-filesystem
	mesa-libEGL
	mesa-libGL
	mesa-libgbm
	mesa-vulkan-drivers
)

dnf5 distro-sync --skip-unavailable -y --repo=fedora-multimedia "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

dnf5 install -y \
	ffmpeg ffmpeg-libs libavcodec @multimedia \
	gstreamer1-plugins-bad-free gstreamer1-plugins-bad-free-libs \
	gstreamer1-plugins-good gstreamer1-plugins-base \
	lame lame-libs \
	libfdk-aac \
	libjxl \
	ffmpegthumbnailer \
	intel-vaapi-driver \
	pipewire-libs-extra

# Disable third-party repo after install (packages are baked into the image)
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/fedora-multimedia.repo

echo "::endgroup::"

echo "::group:: Install COPR Packages"

# Nerd Fonts (che/nerd-fonts)
copr_install_isolated "che/nerd-fonts" nerd-fonts

# uupd auto-update service + steering wheel udev rules (ublue-os/packages)
copr_install_isolated "ublue-os/packages" uupd oversteer-udev

# Ghostty terminal
copr_install_isolated "scottames/ghostty" ghostty

echo "::endgroup::"

echo "::group:: Hide CLI Desktop Entries"

# Hide terminal app desktop entries from the application menu
for file in fish htop nvtop; do
	if [ -f "/usr/share/applications/${file}.desktop" ]; then
		sed -i 's@\[Desktop Entry\]@\[Desktop Entry\]\nHidden=true@g' "/usr/share/applications/${file}.desktop"
	fi
done

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable systemd services
systemctl enable podman.socket
systemctl enable brew-setup.service
systemctl enable flatpak-nuke-fedora.service
systemctl enable flatpak-preinstall.service
systemctl enable ublue-system-setup.service
systemctl enable input-remapper.service
systemctl enable tailscaled.service
systemctl enable uupd.timer
systemctl --global enable podman-auto-update.timer 2>/dev/null || true
systemctl enable dconf-update.service
systemctl enable bootc-unified-storage.service
systemctl --global enable ublue-user-setup.service
systemctl --global enable xdg-user-dirs.service
systemctl --global enable gnome-keyring-daemon.service

# Mask Fedora flatpak service (replaced by Flathub)
systemctl disable flatpak-add-fedora-repos.service 2>/dev/null || true
systemctl mask flatpak-add-fedora-repos.service 2>/dev/null || true

# Add Flathub remote
flatpak remote-add --system --if-not-exists flathub \
	https://flathub.org/repo/flathub.flatpakrepo

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Base system installation complete!"
