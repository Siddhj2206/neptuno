#!/usr/bin/bash

set -eoux pipefail

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Install Asusctl"

dnf5 copr enable -y lukenukem/asus-linux

dnf5 install -y \
    asusctl \
    supergfxctl \
    asusctl-rog-gui

dnf5 copr disable -y lukenukem/asus-linux

echo "::endgroup::"
