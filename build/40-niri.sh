#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Niri layer — compositor + DMS
###############################################################################
# Installs the compositor stack from build/packages/niri.toml and wires the
# dynamic parts of the wm config. Static system files (systemd units, gschema
# override, udev rule, xdg-terminals list) live under custom/files/ and are
# overlaid by 10-overlay.sh — not as heredocs here.
#
# The wm-agnostic layers (10/20/25) never change for a compositor swap:
# replacing niri with hyprland = a new manifest + this script edited from its
# skeleton + files in custom/files/.
###############################################################################

# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

PKGS_TOML=/ctx/build/packages/niri.toml

echo "::group:: Install Niri stack packages"

install_fedora_section "${PKGS_TOML}" "niri fedora packages"
install_copr_sections "${PKGS_TOML}"

echo "::endgroup::"

echo "::group:: Graphical session wiring"

# GDM remains the display manager. The Fedora niri package supplies its
# Wayland session entry, so GNOME and Niri are both selectable at login.
systemctl set-default graphical.target

echo "::endgroup::"

echo "::group:: Compile theme schemas"

# Compile the shipped gschema override in (DMS/matugen owns runtime theming).
glib-compile-schemas /usr/share/glib-2.0/schemas

echo "::endgroup::"

echo "::group:: Enable compositor services"

# System units and globally-enabled user units come from the manifest.
# dms.service and dsearch.service only exist after the COPR install above;
# flatpak-theming.service ships through custom/files/.
enable_services_section "${PKGS_TOML}" "niri services"

# Units that must start with a specific target (not for every session) come
# from [[wants]]; the manifest names the target, so this script stays
# compositor-agnostic.
link_wanted_units "${PKGS_TOML}" "niri wanted units"

echo "::endgroup::"

echo "Niri layer complete!"
