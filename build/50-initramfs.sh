#!/usr/bin/env bash
# Rebuild the initramfs. base-atomic ships one generated before our removals
# and without /usr/lib/dracut/dracut.conf.d/90-neptuno.conf, so it still
# carries the NVIDIA drivers and firmware.
set -euo pipefail

echo "::group:: Rebuild the initramfs"
mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [[ ${#kernels[@]} -ne 1 ]]; then
	echo "ERROR: expected one kernel in /usr/lib/modules, found: ${kernels[*]:-none}" >&2
	exit 1
fi
kver="${kernels[0]}"
image="/usr/lib/modules/${kver}/initramfs.img"
before="$(stat -c %s "${image}")"

# base-atomic's own arguments (lsinitrd prints them); the atomic files in
# dracut.conf.d set the rest. No xattrs: the image layer cannot carry them.
DRACUT_NO_XATTR=1 dracut --reproducible --add ostree --no-hostonly \
	--kver "${kver}" --force "${image}"
chmod 0644 "${image}"

if lsinitrd "${image}" | grep -Eq 'nouveau|firmware/nvidia'; then
	echo "ERROR: the initramfs still carries NVIDIA drivers or firmware" >&2
	exit 1
fi
echo "initramfs: $((before / 1048576)) MiB -> $(($(stat -c %s "${image}") / 1048576)) MiB"
echo "::endgroup::"
