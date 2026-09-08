#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Niri Layer — WM-SPECIFIC (compositor + DMS)
###############################################################################
# Installs the compositor stack from packages/niri.toml and wires the dynamic
# parts of the wm config. All static system files (systemd units/presets/wants,
# theme gschema) live as real files in
# custom/files/ (rsynced to / by 10-build.sh) — NOT as heredocs here.
#
# The wm-agnostic layers (10/20/25) never need to change for a compositor
# swap: replacing niri with hyprland = new packages/niri.toml + a
# 40-hyprland.sh written from this file's skeleton + files in custom/files.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

PKGS_TOML=/ctx/build/packages/niri.toml

echo "::group:: Install Niri Stack Packages"

install_fedora_section "${PKGS_TOML}" "niri fedora packages"
install_copr_sections "${PKGS_TOML}"

echo "::endgroup::"

echo "::group:: Graphical Session Wiring"

# GDM remains the display manager. The Fedora niri package supplies its
# Wayland session entry, so GNOME and Niri are both selectable at login.
systemctl set-default graphical.target

echo "::endgroup::"

echo "::group:: Enable First-Boot Units"

# Unit file ships via custom/files/; runs on first boot because
# /var/lib/flatpak is ephemeral (build-time runs would be lost).
systemctl enable flatpak-theming.service

echo "::endgroup::"

echo "::group:: DMS Autostart"

# Single autostart path (wants-symlink + preset via custom/files/) — NEVER
# also add spawn-at-startup "dms" "run" to the niri config: double start.
# Runs HERE, not 10-build.sh: 10-build's preset-all runs before the DMS/niri
# user units exist (they land via the COPR installs above).
systemctl --global preset-all 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Compile Theme Schemas"

# Compile the shipped gschema override in (DMS/matugen owns runtime theming).
glib-compile-schemas /usr/share/glib-2.0/schemas

echo "::endgroup::"

echo "Niri layer complete!"
