#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Multimedia — Bluefin's negativo17 codec and hardware-acceleration pattern.
###############################################################################

PKGS_TOML=/ctx/build/packages/multimedia.toml

# Source helper functions (install_fedora_section)
# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

echo "::group:: Enable Multimedia Repo"
if ! grep -q fedora-multimedia <(dnf5 repolist); then
	dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi
dnf5 config-manager setopt fedora-multimedia.priority=90

echo "::endgroup::"

echo "::group:: Replace Mesa/VA Overrides"

# Follow Bluefin: sync the codec-adjacent Mesa/VA packages from negativo17
# before locking them, so the hardware acceleration stack matches the full
# ffmpeg codec stack rather than leaving Fedora's free-only variants behind.
readarray -t OVERRIDES < <("${READ_PKGS}" "${PKGS_TOML}" multimedia_overrides)
dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

echo "::endgroup::"

echo "::group:: Install Multimedia Packages"

install_fedora_section "${PKGS_TOML}" "multimedia packages" --enablerepo='fedora-multimedia'

echo "::endgroup::"

echo "::group:: Rebuild gdk-pixbuf Loader Cache"

# Arch-suffixed helper name (image is x86_64-only, but don't hardcode it).
LOADER_QUERY="$(command -v gdk-pixbuf-query-loaders-64 || command -v gdk-pixbuf-query-loaders-32)"
[[ -n "${LOADER_QUERY}" ]] || {
	echo "ERROR: no gdk-pixbuf-query-loaders helper found" >&2
	exit 1
}
"${LOADER_QUERY}" --update-cache

echo "::endgroup::"

echo "Multimedia layer complete!"
