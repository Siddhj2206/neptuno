#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Base Packages — WM-AGNOSTIC Neptuno additions on the Silverblue GNOME base.
# Silverblue supplies the kernel, drivers, firmware, GNOME desktop, audio,
# graphics, portals, Flatpak, and other desktop fundamentals.
# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

PKGS_TOML=/ctx/build/packages/base.toml

echo "::group:: Remove Fedora Desktop Defaults"

# The [remove] manifest section is the source of truth. It deliberately keeps
# fedora-logos: without a replacement, DNF removes GDM and GNOME Shell.
remove_fedora_section "${PKGS_TOML}" "Fedora desktop defaults"

echo "::endgroup::"

echo "::group:: Install Homebrew Build Prerequisites"

# Homebrew's Fedora prerequisite (the Fedora equivalent of build-essential).
install_fedora_groups "${PKGS_TOML}" fedora "Homebrew build prerequisites"

echo "::endgroup::"

echo "::group:: Install Base Packages"

install_fedora_section "${PKGS_TOML}" "base packages"

echo "::endgroup::"

echo "::group:: Install Tailscale"

install_third_party_repo_section \
	"${PKGS_TOML}" \
	"third-party:tailscale-stable" \
	"Tailscale"

echo "::endgroup::"

echo "::group:: Install COPR Packages"

# ghostty from the scottames/ghostty COPR (base.toml ["copr:..."] section).
install_copr_sections "${PKGS_TOML}"

echo "::endgroup::"

echo "::group:: Configure Flathub Remote"

# flatpak-preinstall.service (common overlay) needs a defined remote.
flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo

echo "::endgroup::"

echo "::group:: Enable Display Manager"

# Silverblue ships GDM and GNOME. Niri is an additional GDM Wayland session.
systemctl enable gdm.service

echo "::endgroup::"

echo "::group:: Enable ublue Setup Framework"

# No presets for these (bluefin enables them per-build) — enabled here so
# the hooks run for every user on login, rebasers included.
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service

echo "::endgroup::"

echo "::group:: ZRAM + Firmware Updates"

# Silverblue's zram generator — zram0 sized min(ram, 8192).
# System location so it survives /etc reset; users can override in /etc.
cat >/usr/lib/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram, 8192)
EOF

# Silverblue owns power policy through tuned-ppd. Do not replace it with the
# mutually exclusive power-profiles-daemon package from Pluto's minimal base.

# LVFS firmware metadata refresh (fwupd.service itself is D-Bus activated).
systemctl enable fwupd-refresh.timer

echo "::endgroup::"

echo "Base layer complete!"
