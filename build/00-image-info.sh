#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Image info — writes image-info.json and brands os-release (bluefin pattern)
###############################################################################

# Branding (:- defaults mirror the Containerfile ARG defaults, so the
# script is also runnable outside the build for linting/inspection).
IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Neptuno}"
IMAGE_LIKE="${IMAGE_LIKE:-fedora}"
HOME_URL="${HOME_URL:-https://github.com/${IMAGE_VENDOR:-siddhj2206}/${IMAGE_NAME:-neptuno}}"
DOCUMENTATION_URL="${DOCUMENTATION_URL:-https://github.com/${IMAGE_VENDOR:-siddhj2206}/${IMAGE_NAME:-neptuno}/blob/main/README.md}"
SUPPORT_URL="${SUPPORT_URL:-https://github.com/${IMAGE_VENDOR:-siddhj2206}/${IMAGE_NAME:-neptuno}/issues}"
BUG_REPORT_URL="${BUG_REPORT_URL:-https://github.com/${IMAGE_VENDOR:-siddhj2206}/${IMAGE_NAME:-neptuno}/issues/new}"

# ghcr.io requires lowercase
IMAGE_VENDOR="${IMAGE_VENDOR,,}"
IMAGE_NAME="${IMAGE_NAME,,}"

# Paths
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
OS_RELEASE="/usr/lib/os-release"

# Single flavor (no nvidia variant exists — see finpilot-build skill).
IMAGE_FLAVOR="main"

# Image ref (used by bootc for upgrade source)
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

###############################################################################
# Write image-info.json
###############################################################################
mkdir -p /usr/share/ublue-os
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-flavor": "${IMAGE_FLAVOR}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "${UBLUE_IMAGE_TAG}",
  "base-image-name": "${BASE_IMAGE_NAME}",
  "fedora-version": "${FEDORA_MAJOR_VERSION}"
}
EOF

echo "Wrote ${IMAGE_INFO}"
echo "  image-name: ${IMAGE_NAME}"
echo "  image-flavor: ${IMAGE_FLAVOR}"
echo "  image-vendor: ${IMAGE_VENDOR}"

# Customize /usr/lib/os-release. Silverblue already declares a variant, so
# replace its identity fields rather than skipping Neptuno branding.
if [[ -f "${OS_RELEASE}" ]]; then
	if [[ -n "${VERSION:-}" ]]; then
		OS_VERSION="${VERSION}"
	else
		OS_VERSION="${UBLUE_IMAGE_TAG}"
	fi

	sed -i -E '/^(VARIANT|VARIANT_ID|PRETTY_NAME|NAME|IMAGE_ID|IMAGE_VERSION|VERSION|OSTREE_VERSION|ID_LIKE|HOME_URL|DOCUMENTATION_URL|SUPPORT_URL|BUG_REPORT_URL)=/d' "${OS_RELEASE}"

	cat >>"${OS_RELEASE}" <<EOF

# ${IMAGE_NAME} image identity
VARIANT="${IMAGE_PRETTY_NAME}"
VARIANT_ID="${IMAGE_NAME}"
PRETTY_NAME="${IMAGE_PRETTY_NAME} (Version: ${OS_VERSION})"
NAME="${IMAGE_PRETTY_NAME}"
IMAGE_ID="${IMAGE_NAME}"
IMAGE_VERSION="${OS_VERSION}"
VERSION="${OS_VERSION} (${BASE_IMAGE_NAME^})"
OSTREE_VERSION='${OS_VERSION}'
ID_LIKE="${IMAGE_LIKE}"
HOME_URL="${HOME_URL}"
DOCUMENTATION_URL="${DOCUMENTATION_URL}"
SUPPORT_URL="${SUPPORT_URL}"
BUG_REPORT_URL="${BUG_REPORT_URL}"
EOF

	# traceability
	if [[ -n "${SHA_HEAD_SHORT:-}" ]]; then
		echo "BUILD_ID=\"${SHA_HEAD_SHORT}\"" >>"${OS_RELEASE}"
	fi

	echo "Customized ${OS_RELEASE}"
fi
