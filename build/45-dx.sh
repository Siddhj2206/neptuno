#!/usr/bin/bash

set -euo pipefail

###############################################################################
# DX Layer — host-level dev tooling (android-tools: adb/fastboot).
# User-level CLIs stay in the Brewfile.
# Manifest of record: build/packages/dx.toml ([fedora] section).
#
# Containers: podman (with buildah/skopeo) ships in the Silverblue base and is
# the supported runtime here. The docker-ce daemon and the libvirt/qemu host
# stack were removed from the image to keep it light — no dockerd, no
# docker.socket, no virtqemud/libvirtd. Use podman or a distrobox/toolbox
# container instead.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

PKGS_TOML=/ctx/build/packages/dx.toml

echo "::group:: Install DX Fedora Packages"

install_fedora_section "${PKGS_TOML}" "dx fedora packages"

echo "::endgroup::"

echo "DX layer complete!"
