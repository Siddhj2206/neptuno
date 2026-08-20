#!/usr/bin/bash

echo "::group:: Regenerate Initramfs"

set -eoux pipefail

# Regenerate the initramfs so runtime dracut config takes effect (VFIO
# 80-vfio.conf ships via custom/files) and the image stays bootable.
# Follows the bluefin 19-initramfs.sh pattern with an arch-qualified kver
# so we overwrite the real /usr/lib/modules/<kver>/initramfs.img.

QUALIFIED_KERNEL="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
INITRAMFS_MARKER="/lib/modules/${QUALIFIED_KERNEL}/.neptuno-initramfs-done"

# Skip when the marker is present and FORCE_INITRAMFS is unset, so
# content-only rebuilds don't pay 2–6 min of dracut time and the
# initramfs layer can be reused.
if [[ "${FORCE_INITRAMFS:-0}" != "1" ]] && [[ -f "${INITRAMFS_MARKER}" ]]; then
	echo "Initramfs already built for ${QUALIFIED_KERNEL} — skipping dracut (marker present)"
	echo "::endgroup::"
	exit 0
fi

echo "Regenerating initramfs for ${QUALIFIED_KERNEL}"
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${QUALIFIED_KERNEL}" --reproducible \
	-v --add "ostree dmsquash-live dmsquash-live-autooverlay" \
	-f "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"
chmod 0600 "/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"
touch "${INITRAMFS_MARKER}"

echo "::endgroup::"
