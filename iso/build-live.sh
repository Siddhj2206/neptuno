#!/usr/bin/bash
# iso/build-live.sh — purebuild live ISO (pure-Go, rootless, live-only)
#
# Portable to finpilot: no hard-coded neptuno, derives IMAGE_NAME from
# Justfile env or iso/live.conf. Keep this file as the single entry point;
# Justfile should only call `bash iso/build-live.sh`.
#
# Flow (plan §3):
#   1. ensure purebuild binary (cached by TACKLEBOX_SHA)
#   2. bake live container (Containerfile.live)
#   3. export rootfs tar
#   4. purebuild EROFS ISO
#
# Usage: bash iso/build-live.sh
#   Env: IMAGE_NAME, DEFAULT_TAG (from Justfile exports)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ── Config (single source: Justfile exports + Containerfile ARGs) ─────────
# No iso/*.conf — IMAGE_NAME/DEFAULT_TAG come from Justfile env, TACKLEBOX_SHA
# from Containerfile ARG default. This keeps iso/ directly transferable to
# finpilot (just copy iso/ + Justfile shim).
IMAGE_NAME="${IMAGE_NAME:-neptuno}"
DEFAULT_TAG="${DEFAULT_TAG:-stable}"
LIVE_IMAGE="localhost/${IMAGE_NAME}-live:${DEFAULT_TAG}"
ISO_LABEL="$(echo "${IMAGE_NAME}" | tr '[:lower:]' '[:upper:]')"
ISO_OUTPUT="output/${IMAGE_NAME}-live.iso"
PUREBUILD_BIN=".build/purebuild/purebuild"
# Read TACKLEBOX_SHA from Containerfile if not in env (single source)
TACKLEBOX_SHA="${TACKLEBOX_SHA:-$(grep -E '^ARG TACKLEBOX_SHA=' iso/Containerfile | head -n1 | sed -E 's/.*=//;s/"//g' | tr -d '[:space:]')}"
TACKLEBOX_SHA="${TACKLEBOX_SHA:-f3dd168bf15b235b554e497e7192a64a6563c4a4}"

echo "=== Building live ISO ${ISO_LABEL} (purebuild ${TACKLEBOX_SHA:0:7}, image ${LIVE_IMAGE}) ==="

# ── 1. Purebuild binary (cached, SHA-aware) ─────────────────────────────────
cached_sha=""
if [[ -f .build/purebuild/.tacklebox-sha ]]; then cached_sha=$(cat .build/purebuild/.tacklebox-sha); fi
if [[ ! -x "${PUREBUILD_BIN}" || "${cached_sha}" != "${TACKLEBOX_SHA}" ]]; then
    echo ">>> Building purebuild ${TACKLEBOX_SHA}..."
    mkdir -p .build/purebuild
    podman build -f iso/Containerfile --target purebuild-export \
        --build-arg "TACKLEBOX_SHA=${TACKLEBOX_SHA}" \
        --output type=local,dest=.build/purebuild iso
    chmod +x "${PUREBUILD_BIN}" 2>/dev/null || true
    echo "${TACKLEBOX_SHA}" > .build/purebuild/.tacklebox-sha
    ls -lh "${PUREBUILD_BIN}"
else
    echo ">>> Using cached purebuild ${PUREBUILD_BIN} ($(du -sh "${PUREBUILD_BIN}" | cut -f1)) [${TACKLEBOX_SHA:0:7}]"
fi

# ── 2. Live container ────────────────────────────────────────────────────────
echo ">>> Baking live container ${LIVE_IMAGE}..."
podman build -f iso/Containerfile --target live \
    --build-arg "IMAGE_NAME=${IMAGE_NAME}" \
    --build-arg "DEFAULT_TAG=${DEFAULT_TAG}" \
    -t "${LIVE_IMAGE}" iso

# ── 3. Export tar ────────────────────────────────────────────────────────────
mkdir -p .build/iso output
ctr_name="live-export-$$"
echo ">>> Exporting rootfs tar..."
ctr_id=$(podman create --name "${ctr_name}" "${LIVE_IMAGE}")
trap 'podman rm -f "${ctr_id}" "${ctr_name}" 2>/dev/null || true' EXIT
podman export "${ctr_id}" > .build/iso/rootfs.tar
podman rm -f "${ctr_id}" "${ctr_name}" 2>/dev/null || true
trap - EXIT
echo ">>> Rootfs tar: $(du -sh .build/iso/rootfs.tar | cut -f1)"
echo ">>> Verifying live bake..."
if ! tar tf .build/iso/rootfs.tar | grep -q "etc/gdm/custom.conf"; then
    echo "ERROR: gdm custom.conf not in tar" >&2; exit 1
fi
if ! tar tf .build/iso/rootfs.tar | grep -q "etc/accountsservice/user-templates/standard"; then
    echo "ERROR: AccountsService template not in tar" >&2; exit 1
fi
echo ">>> Live bake verified"

# ── 4. Purebuild ─────────────────────────────────────────────────────────────
pure_image="${LIVE_IMAGE#localhost/}"
if [[ "${pure_image}" != *:* ]]; then pure_image="${pure_image}:stable"; fi
echo ">>> Running purebuild --image ${pure_image} --label ${ISO_LABEL}..."
"${PUREBUILD_BIN}" \
    --image "${pure_image}" \
    --rootfs-tar .build/iso/rootfs.tar \
    --workdir .build/iso \
    --out "${ISO_OUTPUT}" \
    --label "${ISO_LABEL}"
rm -f .build/iso/rootfs.tar 2>/dev/null || true
echo ">>> ISO ready: ${ISO_OUTPUT} ($(du -sh "${ISO_OUTPUT}" | cut -f1))"
