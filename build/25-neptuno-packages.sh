#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Neptuno package layer
###############################################################################
# WM-agnostic RPM additions on the Silverblue GNOME base: the base manifest,
# the Tailscale third-party repo, the uupd COPR, and Bluefin's
# negativo17 multimedia pattern. Compositor packages live in 40-niri.sh.
#
# Package installs belong to the package phases, never to 10-overlay.sh, so a
# filesystem-overlay change cannot invalidate this layer.
#
# Manifests of record: build/packages/base.toml, build/packages/multimedia.toml
###############################################################################

# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

BASE_TOML=/ctx/build/packages/base.toml
MULTIMEDIA_TOML=/ctx/build/packages/multimedia.toml

echo "::group:: Remove Fedora desktop defaults"

# The [remove] manifest section is the source of truth. It deliberately keeps
# fedora-logos: without a replacement, DNF removes GDM and GNOME Shell.
remove_fedora_section "${BASE_TOML}" "Fedora desktop defaults"

echo "::endgroup::"

echo "::group:: Install base packages"

install_fedora_section "${BASE_TOML}" "base packages"

echo "::endgroup::"

echo "::group:: Install Tailscale"

install_third_party_repo_section \
	"${BASE_TOML}" \
	"third-party:tailscale-stable" \
	"Tailscale"

echo "::endgroup::"

echo "::group:: Install COPR packages"

# ublue-os/packages (oversteer-udev). ghostty moved to the DMS COPR in
# niri.toml (danklinux still builds it for Fedora 45). uupd itself is installed
# by 20-packages-and-services.sh through the isolated COPR helper.
install_copr_sections "${BASE_TOML}"

echo "::endgroup::"

echo "::group:: Enable the multimedia repository"

if ! grep -q fedora-multimedia <(dnf5 repolist); then
	dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi
dnf5 config-manager setopt fedora-multimedia.priority=90

echo "::endgroup::"

echo "::group:: Replace Mesa/VA overrides"

# Follow Bluefin: sync the codec-adjacent Mesa/VA packages from negativo17
# before locking them, so the hardware acceleration stack matches the full
# ffmpeg codec stack rather than leaving Fedora's free-only variants behind.
readarray -t OVERRIDES < <("${READ_PKGS}" "${MULTIMEDIA_TOML}" multimedia_overrides)
dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

echo "::endgroup::"

echo "::group:: Install multimedia packages"

install_fedora_section "${MULTIMEDIA_TOML}" "multimedia packages" --enablerepo='fedora-multimedia'

echo "::endgroup::"

echo "::group:: Rebuild gdk-pixbuf loader cache"

# Arch-suffixed helper name (image is x86_64-only, but don't hardcode it).
LOADER_QUERY="$(command -v gdk-pixbuf-query-loaders-64 || command -v gdk-pixbuf-query-loaders-32)"
[[ -n "${LOADER_QUERY}" ]] || {
	echo "ERROR: no gdk-pixbuf-query-loaders helper found" >&2
	exit 1
}
"${LOADER_QUERY}" --update-cache

echo "::endgroup::"

echo "::group:: Configure zram"

# Silverblue's zram generator — zram0 sized min(ram, 8192).
# System location so it survives /etc reset; users can override in /etc.
cat >/usr/lib/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram, 8192)
EOF

echo "::endgroup::"

echo "::group:: Enable base services"

# The [services] section is the only enablement path for this layer. Everything
# else in the image is enabled by 10-overlay.sh (overlay units) or 40-niri.sh
# (compositor units), and 90-cleanup.sh audits the union.
enable_services_section "${BASE_TOML}" "base services"
disable_services_section "${BASE_TOML}" "base services"

echo "::endgroup::"

echo "Neptuno package layer complete!"
