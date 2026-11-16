#!/usr/bin/env bats
# Contract tests for build/00-image-info.sh, run against a sandbox root.

SCRIPT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)/build/00-image-info.sh"

setup() {
	ROOT_DIR="${BATS_TEST_TMPDIR}/root"
	mkdir -p "${ROOT_DIR}/usr/lib"
	cat >"${ROOT_DIR}/usr/lib/os-release" <<'OS'
NAME="Fedora Linux"
VERSION_ID=45
ID=fedora
VARIANT_ID=atomic
PRETTY_NAME="Fedora Linux 45 (Atomic)"
OS
	export ROOT_DIR IMAGE_NAME=neptuno-testing IMAGE_VENDOR=siddhj2206 BASE_IMAGE_NAME=base-atomic
	unset VERSION FEDORA_MAJOR_VERSION
}

info() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "${ROOT_DIR}/usr/share/neptuno/image-info.json" "$1"; }

@test "image-info: writes an unverified update reference for this image name" {
	run "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ "$(info image-ref)" = "ostree-unverified-image:docker://ghcr.io/siddhj2206/neptuno-testing" ]
	[ "$(info fedora-version)" = "45" ]
}

@test "image-info: keeps ID=fedora and rewrites the names" {
	run "${SCRIPT}"
	[ "$status" -eq 0 ]
	grep -qx 'ID=fedora' "${ROOT_DIR}/usr/lib/os-release"
	grep -qx 'NAME="Neptuno"' "${ROOT_DIR}/usr/lib/os-release"
	grep -qx 'VARIANT_ID="neptuno-testing"' "${ROOT_DIR}/usr/lib/os-release"
	grep -qx 'IMAGE_VERSION="45"' "${ROOT_DIR}/usr/lib/os-release"
}

@test "image-info: an explicit VERSION is used" {
	VERSION=45.20261114 run "${SCRIPT}"
	[ "$status" -eq 0 ]
	grep -qx 'PRETTY_NAME="Neptuno 45.20261114"' "${ROOT_DIR}/usr/lib/os-release"
}

@test "image-info: is idempotent" {
	"${SCRIPT}"
	cp "${ROOT_DIR}/usr/lib/os-release" "${BATS_TEST_TMPDIR}/first"
	"${SCRIPT}"
	diff "${BATS_TEST_TMPDIR}/first" "${ROOT_DIR}/usr/lib/os-release"
}

@test "image-info: fails without the required identity" {
	IMAGE_NAME="" run "${SCRIPT}"
	[ "$status" -ne 0 ]
	[ ! -e "${ROOT_DIR}/usr/share/neptuno/image-info.json" ]
}
