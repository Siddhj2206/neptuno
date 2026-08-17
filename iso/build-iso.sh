#!/usr/bin/bash
# iso/build-iso.sh — build the Neptuno hybrid live+install ISO.
#
# Pipeline (adapted from projectbluefin/dakota-iso's scripts/iso-sd-boot.sh
# + live/src/build-iso.sh, with a shim+GRUB2 Secure-Boot-capable ESP instead
# of systemd-boot):
#
#   1. Build the live-env container (iso/Containerfile) from the payload image
#   2. Inject bootc root-mount defaults into the payload (LABEL=root)
#   3. Commit the payload unsquashed to an oci-archive (ostree commits must
#      survive) and import it into an overlay containers-storage
#   4. Mount the live image, rsync the store into
#      <squashfs-root>/usr/lib/containers/storage, squash the whole tree
#   5. Export a boot tar (kernel modules + Fedora shim/GRUB binaries) and
#      assemble the ISO: FAT ESP (shim → grubx64.efi + grub.cfg) via mtools,
#      kernel/initramfs on the ISO root, xorriso, implantisomd5
#
# Requires root (uses podman image mounts and a privileged import). Run via
# `just build-iso` (which wraps this in sudo). Host deps: podman, buildah,
# skopeo, rsync, squashfs-tools, mtools, dosfstools, xorriso, isomd5sum.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: iso/build-iso.sh must run as root (use: just build-iso)" >&2
    exit 1
fi

# ── Config (single source of truth) ───────────────────────────────────────────
# shellcheck source=/dev/null
source iso/neptuno.conf

DEBUG="${DEBUG:-0}"
INSTALLER_CHANNEL="${INSTALLER_CHANNEL:-stable}"
COMPRESSION="${COMPRESSION:-fast}"   # fast | release
OUTPUT_DIR="${OUTPUT_DIR:-output}"
WORKDIR="${WORKDIR:-${OUTPUT_DIR}}"

LIVE_IMAGE="localhost/${OS_SLUG}-live:latest"
ISO_OUTPUT="${OUTPUT_DIR}/${ISO_OUTPUT##*/}"

REQUIRED_TOOLS=(podman buildah skopeo rsync mksquashfs mmd mcopy truncate mkfs.fat xorriso)
OPTIONAL_TOOLS=(implantisomd5)
MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "${tool}" >/dev/null 2>&1 || MISSING_TOOLS+=("${tool}")
done
if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "ERROR: missing host tools: ${MISSING_TOOLS[*]}" >&2
    exit 1
fi
for tool in "${OPTIONAL_TOOLS[@]}"; do
    command -v "${tool}" >/dev/null 2>&1 || echo "WARNING: ${tool} not found — ISO checksum will be skipped (install isomd5sum if you want it)"
done

mkdir -p "${OUTPUT_DIR}" "${WORKDIR}"
OUTPUT_DIR=$(realpath "${OUTPUT_DIR}")
WORKDIR=$(realpath "${WORKDIR}")
ISO_OUTPUT="${OUTPUT_DIR}/$(basename "${ISO_OUTPUT}")"

# Rebuild-state: the offline store (commit + import) only depends on the
# payload image ID. Keep the artifacts across runs and skip the multi-GB
# blob copies when the payload hasn't changed.
PAYLOAD_STATE="${WORKDIR}/.neptuno-payload-id"
PAYLOAD_OCI="${WORKDIR}/neptuno-payload.oci.tar"
SQUASHFS="${WORKDIR}/neptuno-rootfs.sfs"
BOOT_TAR="${WORKDIR}/neptuno-boot-files.tar"
SQUASHFS_ROOT="${WORKDIR}/neptuno-sfs-root"
CS_STAGING="${WORKDIR}/neptuno-cs-staging"

trap 'rm -rf "${SQUASHFS}" "${BOOT_TAR}" "${SQUASHFS_ROOT}" 2>/dev/null || true' EXIT

echo "=== Building Neptuno live ISO (payload: ${IMGREF}) ==="
df -h "${WORKDIR}"

# ── Payload availability ──────────────────────────────────────────────────────
if ! podman image exists "${IMGREF}" 2>/dev/null; then
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "Copying ${IMGREF} from user storage into rootful storage..."
        if ! podman image scp "${SUDO_USER}@localhost::${IMGREF}" "root@localhost::${IMGREF}"; then
            echo "ERROR: could not find ${IMGREF} in user storage. Available images:" >&2
            podman images --format '  {{.Repository}}:{{.Tag}}' | grep -i "${OS_NAME}" || true
            echo "  (build it with 'just build', or set IMGREF in iso/neptuno.conf)" >&2
            exit 1
        fi
    else
        echo "ERROR: ${IMGREF} not found in rootful storage. Run 'just build' first." >&2
        exit 1
    fi
fi

# ── 1. Build the live-env container ───────────────────────────────────────────
echo "=== Building live environment container ${LIVE_IMAGE} ==="
podman build \
    --cap-add sys_admin \
    --security-opt label=disable \
    --build-arg "IMGREF=${IMGREF}" \
    --build-arg "DEBUG=${DEBUG}" \
    --build-arg "INSTALLER_CHANNEL=${INSTALLER_CHANNEL}" \
    --build-arg "CACHE_BUST=$(date +%Y%m%d)" \
    -t "${LIVE_IMAGE}" \
    -f iso/Containerfile iso/

# ── 2. Inject bootc root-mount defaults into the payload ──────────────────────
# bootc install defaults: root filesystem lives on the LABEL=root partition.
# ── 2/3. Bootc root-mount injection + unsquashed oci-archive + overlay store ─
# The offline store only depends on the payload image ID. When the payload
# hasn't changed since the last build, reuse the cached store and skip the
# multi-GB blob copies.
PAYLOAD_ID=$(podman image inspect --format '{{.Id}}' "${IMGREF}")
STORE_STALE=true
if [[ -f "${PAYLOAD_STATE}" && -f "${PAYLOAD_OCI}" && -d "${CS_STAGING}/usr/lib/containers/storage" ]]; then
    if [[ "$(cat "${PAYLOAD_STATE}")" == "${PAYLOAD_ID}" ]]; then
        STORE_STALE=false
        echo "=== Payload unchanged (${PAYLOAD_ID:0:12}…) — reusing cached offline store ==="
    fi
fi

if [[ "${STORE_STALE}" == "true" ]]; then
    # Non-composefs (bootcDirect): NO --squash — squashing flattens the
    # filesystem layer and breaks bootc's ostree unencapsulation. The overlay
    # import then preserves ostree commits; rsync strips overlay whiteout
    # char-devices below.
    printf '[install]\nroot-mount-spec = "LABEL=root"\n' > "${WORKDIR}/.bootc-root-mount.toml"
    INJECT_CTR=$(buildah from --pull-never "${IMGREF}")
    buildah copy "${INJECT_CTR}" "${WORKDIR}/.bootc-root-mount.toml" /tmp/.bootc-root-mount.toml
    buildah run "${INJECT_CTR}" -- sh -c 'mkdir -p /usr/lib/bootc/install && cp /tmp/.bootc-root-mount.toml /usr/lib/bootc/install/00-defaults.toml && rm /tmp/.bootc-root-mount.toml'
    rm -f "${WORKDIR}/.bootc-root-mount.toml"

    echo "=== Committing ${IMGREF} WITHOUT squash to preserve ostree commits ==="
    buildah commit "${INJECT_CTR}" "oci-archive:${PAYLOAD_OCI}:${IMGREF}"
    buildah rm "${INJECT_CTR}"

    SQUASHFS_STORAGE="${CS_STAGING}/usr/lib/containers/storage"
    STORAGE_CONF=$(mktemp "${WORKDIR}/live-storage-XXXXXX.conf")
    mkdir -p "${SQUASHFS_STORAGE}"
    printf '[storage]\ndriver = "overlay"\nrunroot = "/tmp/cs-runroot"\ngraphroot = "/vfs-storage"\n' > "${STORAGE_CONF}"
    echo "=== Importing OCI image into overlay containers-storage (additionalimagestore) ==="
    podman run --rm --privileged \
        -v "${PAYLOAD_OCI}:/payload.oci.tar:ro" \
        -v "${SQUASHFS_STORAGE}:/vfs-storage" \
        -v "${STORAGE_CONF}:/tmp/st.conf:ro" \
        "${LIVE_IMAGE}" \
        sh -c "mkdir -p /tmp/cs-runroot /var/tmp && CONTAINERS_STORAGE_CONF=/tmp/st.conf skopeo copy oci-archive:/payload.oci.tar:${IMGREF} containers-storage:${IMGREF}"
    rm -f "${PAYLOAD_OCI}" "${STORAGE_CONF}"
    echo "${PAYLOAD_ID}" > "${PAYLOAD_STATE}"
fi

# ── 4. Squashfs root: live image + embedded store ─────────────────────────────
echo "=== Assembling squashfs root from ${LIVE_IMAGE} ==="
MOUNT=$(podman image mount "${LIVE_IMAGE}")
rm -rf "${SQUASHFS_ROOT}"
mkdir -p "${SQUASHFS_ROOT}"
echo "Copying live image into squashfs root (reflink on CoW filesystems)..."
# --reflink=auto: btrfs reflink makes the copy near-instant; falls back to a
# full copy elsewhere.
cp -a --reflink=auto "${MOUNT}/." "${SQUASHFS_ROOT}/"

mkdir -p "${SQUASHFS_ROOT}/usr/lib/containers/storage"
echo "Copying overlay store into squashfs root..."
# Overlay containers-storage contains character-device whiteout files that
# cp -a cannot create without privileges. Use rsync to skip them — they are
# write-layer artifacts not needed in the read-only additional store.
rsync -a --no-specials --no-devices "${CS_STAGING}/usr/lib/containers/storage/" "${SQUASHFS_ROOT}/usr/lib/containers/storage/"

mkdir -p "${SQUASHFS_ROOT}/proc" "${SQUASHFS_ROOT}/sys" "${SQUASHFS_ROOT}/dev"
SFS_LEVEL=3; SFS_BLOCK=131072
[[ "${COMPRESSION}" == "release" ]] && { SFS_LEVEL=15; SFS_BLOCK=1048576; }
echo "=== Squashing rootfs (zstd level ${SFS_LEVEL}, $(nproc) processors) ==="
mksquashfs "${SQUASHFS_ROOT}" "${SQUASHFS}" \
    -noappend -comp zstd -Xcompression-level "${SFS_LEVEL}" -b "${SFS_BLOCK}" \
    -processors "$(nproc)" \
    -wildcards -e "proc/*" -e "sys/*" -e "dev/*" -e run -e tmp

# Boot tar: kernel modules (vmlinuz + initramfs) and the Fedora shim/GRUB
# binaries from /boot/efi (needed for the Secure-Boot-capable ESP) plus the
# GRUB unicode font.
tar -C "${MOUNT}" \
    -cf "${BOOT_TAR}" \
    ./usr/lib/modules \
    ./boot/efi/EFI/fedora \
    ./usr/share/grub/unicode.pf2
podman image unmount "${LIVE_IMAGE}" || true

# ── 5. ISO assembly (shim + GRUB2 ESP, Secure Boot capable) ───────────────────
echo "=== Assembling ISO ==="
BOOT_DIR=$(mktemp -d "${WORKDIR}/neptuno-boot.XXXXXX")
tar -xf "${BOOT_TAR}" -C "${BOOT_DIR}" --no-same-owner

# shellcheck disable=SC2012  # kernel version dirs have no special chars; ls|sort -V is correct
kernel=$(ls "${BOOT_DIR}/usr/lib/modules" | sort -V | tail -1)
VMLINUZ="${BOOT_DIR}/usr/lib/modules/${kernel}/vmlinuz"
INITRD="${BOOT_DIR}/usr/lib/modules/${kernel}/initramfs.img"
SHIM_SRC="${BOOT_DIR}/boot/efi/EFI/fedora/shimx64.efi"
GRUB_SRC="${BOOT_DIR}/boot/efi/EFI/fedora/grubx64.efi"
MM_SRC="${BOOT_DIR}/boot/efi/EFI/fedora/mmx64.efi"
UNICODE_SRC="${BOOT_DIR}/usr/share/grub/unicode.pf2"

for f in "${VMLINUZ}" "${INITRD}" "${SHIM_SRC}" "${GRUB_SRC}" "${MM_SRC}" "${UNICODE_SRC}"; do
    [[ -f "${f}" ]] || { echo "ERROR: missing boot file: ${f}"; exit 1; }
done
echo ">>> Kernel:    $(du -sh "${VMLINUZ}" | cut -f1)  (${kernel})"
echo ">>> Initramfs: $(du -sh "${INITRD}" | cut -f1)"
echo ">>> Shim:      ${SHIM_SRC}"
echo ">>> GRUB:      ${GRUB_SRC}"

ISO_ROOT=$(mktemp -d "${WORKDIR}/neptuno-iso-root.XXXXXX")
ESP_STAGING=$(mktemp -d "${WORKDIR}/neptuno-esp.XXXXXX")
mkdir -p \
    "${ISO_ROOT}/EFI/BOOT" "${ISO_ROOT}/LiveOS" "${ISO_ROOT}/images/pxeboot" "${ISO_ROOT}/boot/grub" \
    "${ESP_STAGING}/EFI/BOOT/fonts"

# ESP contents: shim (BOOTX64.EFI well-known path) + GRUB + MokManager + font.
# grub.cfg generated from the template with config values substituted.
cp "${SHIM_SRC}" "${ESP_STAGING}/EFI/BOOT/BOOTX64.EFI"
cp "${GRUB_SRC}" "${ESP_STAGING}/EFI/BOOT/grubx64.efi"
cp "${MM_SRC}"   "${ESP_STAGING}/EFI/BOOT/mmx64.efi"
cp "${UNICODE_SRC}" "${ESP_STAGING}/EFI/BOOT/fonts/unicode.pf2"
sed -e "s/@ISO_LABEL@/${ISO_LABEL}/g" -e "s/@OS_TITLE@/${OS_TITLE}/g" \
    iso/src/grub.cfg > "${ESP_STAGING}/EFI/BOOT/grub.cfg"

# ISO-root layout: kernel/initramfs (GRUB reads them from the ISO via its
# built-in iso9660 driver — they must NOT be inside the ESP), squashfs,
# and the EFI fallback path (shim+grub+mm+grub.cfg) for non-SB firmware /
# Ventoy-style boot.
cp "${VMLINUZ}" "${ISO_ROOT}/images/pxeboot/vmlinuz"
cp "${INITRD}"  "${ISO_ROOT}/images/pxeboot/initrd.img"
cp "${SQUASHFS}" "${ISO_ROOT}/LiveOS/squashfs.img"
cp "${SHIM_SRC}" "${ISO_ROOT}/EFI/BOOT/BOOTX64.EFI"
cp "${GRUB_SRC}" "${ISO_ROOT}/EFI/BOOT/grubx64.efi"
cp "${MM_SRC}"   "${ISO_ROOT}/EFI/BOOT/mmx64.efi"
mkdir -p "${ISO_ROOT}/EFI/BOOT/fonts"
cp "${UNICODE_SRC}" "${ISO_ROOT}/EFI/BOOT/fonts/unicode.pf2"
cp "${ESP_STAGING}/EFI/BOOT/grub.cfg" "${ISO_ROOT}/EFI/BOOT/grub.cfg"

# Ventoy/loopback metadata (requires a dracut isofile module on the image to
# actually find the ISO as a file — not shipped yet).
sed -e "s/@ISO_LABEL@/${ISO_LABEL}/g" -e "s/@OS_TITLE@/${OS_TITLE}/g" \
    iso/src/loopback.cfg > "${ISO_ROOT}/boot/grub/loopback.cfg"

echo ">>> Squashfs: $(du -sh "${ISO_ROOT}/LiveOS/squashfs.img" | cut -f1)"

# FAT ESP image, populated with mtools — no loop mount required.
ESP_IMG="${ISO_ROOT}/EFI/efi.img"
ESP_TOTAL_MB=20
echo ">>> Creating ${ESP_TOTAL_MB} MiB FAT ESP image..."
truncate -s "${ESP_TOTAL_MB}M" "${ESP_IMG}"
mkfs.fat -F 32 -n "ESP" "${ESP_IMG}"
export MTOOLS_SKIP_CHECK=1
mmd -i "${ESP_IMG}" ::/EFI ::/EFI/BOOT ::/EFI/BOOT/fonts
mcopy -i "${ESP_IMG}" "${ESP_STAGING}/EFI/BOOT/BOOTX64.EFI"   "::/EFI/BOOT/BOOTX64.EFI"
mcopy -i "${ESP_IMG}" "${ESP_STAGING}/EFI/BOOT/grubx64.efi"   "::/EFI/BOOT/grubx64.efi"
mcopy -i "${ESP_IMG}" "${ESP_STAGING}/EFI/BOOT/mmx64.efi"     "::/EFI/BOOT/mmx64.efi"
mcopy -i "${ESP_IMG}" "${ESP_STAGING}/EFI/BOOT/fonts/unicode.pf2" "::/EFI/BOOT/fonts/unicode.pf2"
mcopy -i "${ESP_IMG}" "${ESP_STAGING}/EFI/BOOT/grub.cfg"      "::/EFI/BOOT/grub.cfg"

# ISO assembly:
#   -iso-level 3    required for files >2 GiB (squashfs)
#   --efi-boot EFI/efi.img + -efi-boot-part + --efi-boot-image
#                   El Torito EFI entry AND a GPT partition with the EFI
#                   System Partition GUID so old firmware scanning for it
#                   auto-discovers the USB as a bootable EFI device
#                   (protective MBR, not hybrid — see dakota-iso issue #15)
echo ">>> Assembling ISO with xorriso..."
xorriso -as mkisofs \
    -iso-level 3 \
    -r \
    -J --joliet-long \
    -V "${ISO_LABEL}" \
    --efi-boot EFI/efi.img \
    -efi-boot-part \
    --efi-boot-image \
    -o "${ISO_OUTPUT}" \
    "${ISO_ROOT}"

implantisomd5 "${ISO_OUTPUT}" 2>/dev/null || true

# ── Verify protective MBR + GPT layout ───────────────────────────────────────
echo ">>> Partition layout:"
xorriso -indev "${ISO_OUTPUT}" -report_system_area plain 2>/dev/null | \
    grep -E '^(System area|ISO image size|MBR|GPT|Partition)' || true
xorriso -indev "${ISO_OUTPUT}" -report_system_area plain 2>/dev/null | \
    grep 'System area summary' | grep -q 'protective' && \
    echo ">>> Protective MBR + GPT: OK" || \
    echo ">>> WARNING: protective MBR not found — USB may not boot on older firmware"

rm -rf "${BOOT_DIR}" "${ISO_ROOT}" "${ESP_STAGING}"
echo ">>> Done: ${ISO_OUTPUT} ($(du -sh "${ISO_OUTPUT}" | cut -f1))"
echo ">>> Boot the ISO with Secure Boot enabled to verify (mokutil --sb-state inside the live session)"
