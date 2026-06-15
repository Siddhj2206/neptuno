#!/usr/bin/bash

set -eoux pipefail

echo "::group:: Regenerate Initramfs"

# Regenerate initramfs to include all changes from VFIO dracut config,
# kernel modules, and any other dracut modifications
dracut --regenerate-all --force 2>/dev/null

echo "::endgroup::"
