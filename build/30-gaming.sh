#!/usr/bin/bash

set -eoux pipefail

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Install Steam"

dnf5 install -y \
    steam \
    gamescope \
    mangohud

echo "::endgroup::"
