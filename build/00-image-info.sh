#!/usr/bin/env bash
# Image identity: os-release and /usr/share/neptuno/image-info.json.
#
# ID=fedora and ID_LIKE stay as the base set them, so dnf (in toolbox), fwupd
# and distrobox keep treating the system as Fedora. Only the names, variant and
# IMAGE_* fields change.
#
# The update source is deliberately `ostree-unverified-image:`. Signing is
# keyless and checked in CI before a tag moves (doc/product.md section 11);
# containers/image cannot match a GitHub Actions Fulcio identity on the device,
# so a signed transport would only claim a check that never happens.
set -euo pipefail

: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${IMAGE_VENDOR:?IMAGE_VENDOR must be set}"
: "${BASE_IMAGE_NAME:?BASE_IMAGE_NAME must be set}"

# ROOT_DIR is a test seam; it is empty in the image build.
ROOT_DIR="${ROOT_DIR:-}"
IMAGE_INFO="${ROOT_DIR}/usr/share/neptuno/image-info.json"
OS_RELEASE="${ROOT_DIR}/usr/lib/os-release"

if [[ -z "${FEDORA_MAJOR_VERSION:-}" && -r "${OS_RELEASE}" ]]; then
	FEDORA_MAJOR_VERSION="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${OS_RELEASE}")"
fi
: "${FEDORA_MAJOR_VERSION:?FEDORA_MAJOR_VERSION must be set or derivable from ${OS_RELEASE}}"

VERSION="${VERSION:-${FEDORA_MAJOR_VERSION}}"
HOME_URL="https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}"
IMAGE_REF="ostree-unverified-image:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

json_escape() {
	local value=$1
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	value=${value//$'\n'/\\n}
	value=${value//$'\t'/\\t}
	printf '%s' "${value}"
}

set_os_release_value() {
	local key=$1 value=$2 escaped
	if grep -q "^${key}=" "${OS_RELEASE}"; then
		escaped=${value//\\/\\\\}
		escaped=${escaped//\"/\\\"}
		escaped=${escaped//&/\\&}
		escaped=${escaped//|/\\|}
		sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "${OS_RELEASE}"
	else
		printf '%s="%s"\n' "${key}" "${value}" >>"${OS_RELEASE}"
	fi
}

install -d "$(dirname "${IMAGE_INFO}")"
cat >"${IMAGE_INFO}" <<JSON
{
  "image-name": "$(json_escape "${IMAGE_NAME}")",
  "image-vendor": "$(json_escape "${IMAGE_VENDOR}")",
  "image-ref": "$(json_escape "${IMAGE_REF}")",
  "base-image-name": "$(json_escape "${BASE_IMAGE_NAME}")",
  "fedora-version": "$(json_escape "${FEDORA_MAJOR_VERSION}")"
}
JSON

if [[ -f "${OS_RELEASE}" ]]; then
	set_os_release_value NAME "Neptuno"
	set_os_release_value PRETTY_NAME "Neptuno ${VERSION}"
	set_os_release_value VARIANT "Neptuno"
	set_os_release_value VARIANT_ID "${IMAGE_NAME}"
	# GNOME/DMS shell branding: icon lookup name used by About,
	# app launchers and shell greeters (bluefin convention).
	set_os_release_value LOGO "distributor-logo"
	set_os_release_value VERSION "${VERSION} (${BASE_IMAGE_NAME})"
	set_os_release_value OSTREE_VERSION "${VERSION}"
	set_os_release_value IMAGE_ID "${IMAGE_NAME}"
	set_os_release_value IMAGE_VERSION "${VERSION}"
	set_os_release_value HOME_URL "${HOME_URL}"
	set_os_release_value DOCUMENTATION_URL "${HOME_URL}/blob/main/README.md"
	set_os_release_value SUPPORT_URL "${HOME_URL}/issues"
	set_os_release_value BUG_REPORT_URL "${HOME_URL}/issues/new"
fi

printf 'Wrote %s for %s (%s)\n' "${IMAGE_INFO}" "${IMAGE_NAME}" "${IMAGE_REF}"
