#!/usr/bin/bash

set -eoux pipefail

echo "::group:: Set dnf options"
dnf5 config-manager setopt keepcache=1 install_weak_deps=0
echo "::endgroup::"

echo "::group:: Image Info"
/ctx/build/steps/00-image-info.sh
echo "::endgroup::"

echo "::group:: 10-build.sh"
/ctx/build/steps/10-build.sh
echo "::endgroup::"

echo "::group:: 20-base.sh"
/ctx/build/steps/20-base.sh
echo "::endgroup::"

echo "::group:: 30-dx.sh"
/ctx/build/steps/30-dx.sh
echo "::endgroup::"

echo "::group:: 40-dms.sh"
/ctx/build/steps/40-dms.sh
echo "::endgroup::"

echo "::group:: 60-initramfs.sh"
/ctx/build/steps/60-initramfs.sh
echo "::endgroup::"
