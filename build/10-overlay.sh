#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Runtime overlays
###############################################################################
# This phase owns every runtime integration the image applies on top of its
# base: the selected Common and Brew filesystem overlays, the template's custom
# declaration seams, and the systemd enablement that makes those declarations
# live.
#
# It installs nothing. RPM and COPR installation belongs to
# 20-packages-and-services.sh.
#
# Order is the contract. Every step writes over the one above it, so a later
# step deliberately wins:
#
#   1. common/shared        reusable runtime infrastructure
#   2. common/bluefin       targeted cherry-picks (never overlaid wholesale)
#   3. ublue-os/brew        the Homebrew mechanism and its shell integration
#   4. custom/files         the override seam: mirrors / and may replace anything
#   5. custom/config        per-user defaults, seeded into /etc/skel/.config
#
# The declaration seams write into directories the overlays above created:
# custom/brew/*.Brewfile, custom/ujust/ (any depth), and
# custom/flatpaks/*.preinstall.
# A custom file sharing a name with an inherited one overrides it. That follows
# the same precedence rule; it is not a collision to guard against.
#
# common/bluefin/ is imported into the build context but never overlaid
# wholesale: shared/ is reusable runtime infrastructure, while bluefin/ is
# product opinion and nvidia/ is a paired hardware feature that must ship with
# a real driver installation.
#
# Enablement is declared in packages/overlay.toml, not in this script; see
# build/README.md and build/scripts/systemd-units.
###############################################################################

shopt -s nullglob

# Record the base image's enabled units before any overlay lands. 90-cleanup.sh
# diffs against this snapshot, so a unit can only become enabled through a
# manifest's [services] section — never through an overlay symlink or an RPM
# scriptlet we did not choose.
"${UNITS_BIN:-/ctx/build/scripts/systemd-units}" snapshot "${UNITS_SNAPSHOT:-/var/tmp/neptuno-units.before}" \
	--root "${UNITS_ROOT:-/}"

# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

echo "::group:: Overlay shared Common runtime files"

# Shared runtime substrate: the ujust entry point and wrapper, first-boot setup
# hooks, container trust policy, and the Flatpak/Brew declarations these
# services consume.
#
# /etc/containers/policy.json arrives here, and the template deliberately takes
# it unmodified. Its sigstore scopes cover ghcr.io/ublue-os and
# quay.io/toolbx-images; this image's own namespace matches the `""` catch-all
# (insecureAcceptAnything), which is why 00-image-info.sh writes an unverified
# update transport. Merging a scope for this namespace — with jq, never by
# forking the file through custom/files, which would freeze every inherited
# scope — is only worth doing once the image is signed with a key the policy
# can name; a keyless GitHub Actions identity is unmatchable here.
rsync -rvK /ctx/oci/common/shared/ /

echo "::endgroup::"

echo "::group:: Overlay Bluefin cherry-picks"

# common/bluefin is product opinion, not shared infrastructure, so it is
# cherry-picked by path instead of overlaid wholesale. Every path is asserted
# after the copy: a rename in common must fail this build with the missing path
# named, rather than silently dropping the integration.
#
# The bluefin/just directory is deliberately NOT taken wholesale: Neptuno owns
# its ujust recipes, and importing Bluefin's changelog.just would duplicate the
# `changelogs` recipe for no gain.
COMMON_CHERRY_PICKS=(
	/ctx/oci/common/bluefin/./usr/libexec/bonedigger-report
	/ctx/oci/common/bluefin/./usr/lib/systemd/system/dconf-update.service
	/ctx/oci/common/bluefin/./usr/share/flatpak/preinstall.d/bazaar.preinstall
	/ctx/oci/common/bluefin/./etc/bazaar/
	/ctx/oci/common/bluefin/./usr/lib/systemd/user/bazaar.service
	/ctx/oci/common/bluefin/./usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar
	/ctx/oci/common/bluefin/./usr/lib/tmpfiles.d/bazaar-flatpak.conf
)
rsync -rvK --relative "${COMMON_CHERRY_PICKS[@]}" /

for src in "${COMMON_CHERRY_PICKS[@]}"; do
	common_path="/${src#/ctx/oci/common/bluefin/./}"
	test -e "${common_path}" || {
		echo "ERROR: common cherry-pick missing: ${common_path}" >&2
		exit 1
	}
done

echo "::endgroup::"

echo "::group:: Overlay Brew integration files"

# Brew supplies the Homebrew mechanism (archive, systemd units, shell
# integration). The template supplies the package declarations below.
rsync -rvK /ctx/oci/brew/ /

echo "::endgroup::"

echo "::group:: Overlay template system files"

# custom/files mirrors the image root, so a fork can ship systemd units,
# presets, and other system payloads by path. The leading slash anchors the
# exclusion to the copy root, so the seam's own README never lands in the image
# while a nested file named README.md still ships.
rsync -rvKl --exclude=/README.md /ctx/custom/files/ /

echo "::endgroup::"

echo "::group:: Copy template custom declarations"

# custom/config seeds each new user's ~/.config. Updating users who already
# exist is a deliberate, idempotent ujust command, never an automatic login
# hook. The leading slash anchors the exclusion to the copy root, so only the
# seam's own README is skipped and a nested file named README.md still ships.
if [[ -d /ctx/custom/config ]]; then
	mkdir -p /etc/skel/.config
	rsync -a --exclude=/README.md /ctx/custom/config/ /etc/skel/.config/
fi

# Brewfiles consumed by first-user Homebrew setup. Neptuno auto-installs its
# curated set on first login, so they belong in preinstall.d (the content-hashed
# brew-preinstall service reads only that directory). Upstream finpilot copies
# them to the parent dir, where they are declaration-only.
mkdir -p /usr/share/ublue-os/homebrew/preinstall.d/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/preinstall.d/

# The copy is the only link between custom/brew and the runtime preinstaller.
compgen -G "/usr/share/ublue-os/homebrew/preinstall.d/*.Brewfile" >/dev/null || {
	echo "ERROR: no Brewfiles landed in preinstall.d" >&2
	exit 1
}

# Merge custom ujust recipes into the file the shared ujust entry point imports.
# Walk the tree so a fork can organise recipes into subdirectories, and sort the
# inputs so the merged result is deterministic and idempotent.
mkdir -p /usr/share/ublue-os/just/
: >/usr/share/ublue-os/just/60-custom.just
if [[ -d /ctx/custom/ujust ]]; then
	mapfile -t recipes < <(find /ctx/custom/ujust -type f -iname '*.just' | LC_ALL=C sort)
	for recipe in "${recipes[@]}"; do
		cat "${recipe}" >>/usr/share/ublue-os/just/60-custom.just
		printf '\n' >>/usr/share/ublue-os/just/60-custom.just
	done
fi

# Flatpak preinstall declarations, consumed at first boot.
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

echo "::endgroup::"

echo "::group:: Add the Flathub remote descriptor"

# flatpak imports remotes from /etc/flatpak/remotes.d into the default system
# installation the first time it is used, then records them in the repository's
# applied-remotes list: the remote is imported once, and is the user's to remove
# afterwards. Shipping the descriptor is therefore all that is needed. There is
# deliberately no unit and no build-time `flatpak remote-add`, which would only
# write to /var and be pruned by 90-cleanup.sh.
#
# The descriptor is pinned like every other input to this image: it carries
# Url= and GPGKey=, so it is the trust root every Flatpak on the image is
# verified against, not merely a pointer to one. OSTree's signature check is
# only as good as the key this file names. Flathub's key has not changed since
# the repository opened, so a hash bump here means Flathub itself moved and the
# new descriptor deserves a look before it ships. tests/fixtures holds the
# pinned copy.
FLATHUB_REPO_SHA256=3371dd250e61d9e1633630073fefda153cd4426f72f4afa0c3373ae2e8fea03a
install -d -m0755 /etc/flatpak/remotes.d
flathub_tmp="$(mktemp)"
curl --fail --retry 3 --silent --show-error \
	--output "${flathub_tmp}" \
	https://dl.flathub.org/repo/flathub.flatpakrepo
echo "${FLATHUB_REPO_SHA256}  ${flathub_tmp}" | sha256sum --check --strict
install -m0644 "${flathub_tmp}" /etc/flatpak/remotes.d/flathub.flatpakrepo
rm -f "${flathub_tmp}"

echo "::endgroup::"

echo "::group:: Enable overlay services"

# Units the overlays above provide. The [services] section of overlay.toml is
# the single enablement path: it makes the Brew and Flatpak declarations take
# effect, wires the first-boot setup framework, and turns on rootless podman.
# Nothing here is enabled implicitly, and 90-cleanup.sh audits the result.
enable_services_section /ctx/build/packages/overlay.toml "overlay services"

# common ships 01-brew-preinstall.preset, but systemd applies presets only for
# the system manager on a machine's first boot. In a Containerfile build that
# preset is inert for user units, so the explicit global enable above is the
# only thing that turns brew-preinstall on. Fail closed if it did not take.
systemctl --global is-enabled brew-preinstall.service >/dev/null

echo "::endgroup::"

shopt -u nullglob

echo "Overlay phase complete!"
