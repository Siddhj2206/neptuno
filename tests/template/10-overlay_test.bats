#!/usr/bin/env bats
# Unit tests for build/10-overlay.sh.
#
# The script overlays the Common/Brew OCI payloads and writes the template's
# custom declarations under /usr/share and /etc/skel, so each test rewrites a
# throwaway copy to point at a sandbox root and stubs the binaries it shells
# out to (rsync, systemctl, curl). Production behaviour is never modified; the
# rewrite is asserted below so the suite fails loudly if the paths in the
# script ever drift.
#
# Run with: bats tests/template/10-overlay_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERLAY_SRC="${REPO_ROOT}/build/10-overlay.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/10-overlay.${BATS_TEST_NUMBER:-0}.$$"
	SANDBOX="${TEST_ROOT}/root"
	CTX="${SANDBOX}/ctx"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	SCRIPT="${TEST_ROOT}/10-overlay.sh"

	RSYNC_LOG="${TEST_ROOT}/logs/rsync.log"
	SYSTEMCTL_LOG="${TEST_ROOT}/logs/systemctl.log"
	CURL_LOG="${TEST_ROOT}/logs/curl.log"

	HOMEBREW_DIR="${SANDBOX}/usr/share/ublue-os/homebrew"
	JUST_DIR="${SANDBOX}/usr/share/ublue-os/just"
	PREINSTALL_DIR="${SANDBOX}/usr/share/flatpak/preinstall.d"

	mkdir -p "${STUB_BIN}" "${TEST_ROOT}/logs"
	mkdir -p "${CTX}/oci/common/shared" "${CTX}/oci/brew"
	mkdir -p "${CTX}/build/scripts" "${CTX}/build/packages"

	# The overlay applies overlay.toml through the shared manifest helpers, and
	# snapshots the enabled set through build/scripts/systemd-units. Copy all three verbatim and
	# point the helpers at the sandbox.
	cp "${REPO_ROOT}/build/scripts/systemd-units" "${CTX}/build/scripts/systemd-units"
	cp "${REPO_ROOT}/build/scripts/read-packages" "${CTX}/build/scripts/read-packages"
	cp "${REPO_ROOT}/build/scripts/package-lib.sh" "${CTX}/build/scripts/package-lib.sh"
	cp "${REPO_ROOT}/build/packages/overlay.toml" "${CTX}/build/packages/overlay.toml"
	chmod +x "${CTX}/build/scripts/systemd-units" "${CTX}/build/scripts/read-packages"

	export READ_PKGS="${CTX}/build/scripts/read-packages"
	export UNITS_ROOT="${SANDBOX}"
	export CHERRY_PICK_ROOT="${SANDBOX}"
	export UNITS_SNAPSHOT="${TEST_ROOT}/units.before"
	mkdir -p "${CTX}/custom/brew" "${CTX}/custom/ujust" "${CTX}/custom/flatpaks"

	# common/bluefin cherry-pick sources. The overlay asserts every path after
	# the copy, so the fixture must provide all of them.
	for cherry in \
		usr/libexec/bonedigger-report \
		usr/lib/systemd/system/dconf-update.service \
		usr/share/flatpak/preinstall.d/bazaar.preinstall \
		etc/bazaar/bazaar.yaml \
		usr/lib/systemd/user/bazaar.service \
		usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar \
		usr/lib/tmpfiles.d/bazaar-flatpak.conf; do
		mkdir -p "$(dirname "${CTX}/oci/common/bluefin/${cherry}")"
		printf 'cherry-pick\n' >"${CTX}/oci/common/bluefin/${cherry}"
	done

	# The rsync stub logs without copying, so create the cherry-pick destinations
	# the post-copy assertions look for. The assertions themselves are covered by
	# the missing-path test below.
	for dest in \
		usr/libexec/bonedigger-report \
		usr/lib/systemd/system/dconf-update.service \
		usr/share/flatpak/preinstall.d/bazaar.preinstall \
		etc/bazaar/bazaar.yaml \
		usr/lib/systemd/user/bazaar.service \
		usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar \
		usr/lib/tmpfiles.d/bazaar-flatpak.conf; do
		mkdir -p "$(dirname "${SANDBOX}/${dest}")"
		printf 'cherry-pick\n' >"${SANDBOX}/${dest}"
	done

	# Representative build context contents.
	printf 'shared-payload\n' >"${CTX}/oci/common/shared/.keep"
	printf 'brew "tmux"\n' >"${CTX}/custom/brew/default.Brewfile"
	printf 'brew "gcc"\n' >"${CTX}/custom/brew/development.Brewfile"
	printf 'custom-apps-marker:\n\techo apps\n' >"${CTX}/custom/ujust/custom-apps.just"
	printf 'custom-system-marker:\n\techo system\n' >"${CTX}/custom/ujust/custom-system.just"
	printf '# not a just file\n' >"${CTX}/custom/ujust/README.md"
	printf 'org.mozilla.firefox\n' >"${CTX}/custom/flatpaks/default.preinstall"

	sed \
		-e "s#/ctx/#${CTX}/#g" \
		-e "s#/usr/share/#${SANDBOX}/usr/share/#g" \
		-e "s#/etc/skel#${SANDBOX}/etc/skel#g" \
		-e "s#/etc/flatpak#${SANDBOX}/etc/flatpak#g" \
		"${OVERLAY_SRC}" >"${SCRIPT}"

	# What the curl stub serves: the committed copy of the descriptor by
	# default, so the pin in the script is checked against real bytes.
	CURL_BODY="${REPO_ROOT}/tests/fixtures/flathub.flatpakrepo"

	export PATH="${STUB_BIN}:${PATH}"
	export RSYNC_LOG SYSTEMCTL_LOG CURL_LOG CURL_BODY

	for tool in rsync systemctl; do
		local log_var
		log_var="$(printf '%s' "${tool}" | tr '[:lower:]' '[:upper:]')_LOG"
		cat >"${STUB_BIN}/${tool}" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" >> "\${${log_var}}"
exit 0
EOF
		chmod +x "${STUB_BIN}/${tool}"
	done

	# curl also honours --output so the script has a file to verify.
	cat >"${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${CURL_LOG}"
while [ $# -gt 0 ]; do
	if [ "$1" = "--output" ]; then
		cp "${CURL_BODY}" "$2"
		shift
	fi
	shift
done
exit 0
EOF
	chmod +x "${STUB_BIN}/curl"
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "10-overlay: sandbox rewrite left no writes to the host filesystem" {
	# Guards the rewrite above: if the script's paths change, the sed no longer
	# matches and every other test in this file would silently touch the host.
	run grep -nE '(^|[^-[:alnum:]])/ctx/|[^-[:alnum:]]/usr/share/|[^-[:alnum:]]/etc/skel' "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "10-overlay: completes successfully against a populated sandbox context" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Overlay phase complete!"* ]]
}

@test "10-overlay: emits GitHub Actions group markers" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"::group:: Overlay shared Common runtime files"* ]]
	[[ "$output" == *"::group:: Overlay Brew integration files"* ]]
	[[ "$output" == *"::group:: Copy template custom declarations"* ]]
	[[ "$output" == *"::group:: Add the Flathub remote descriptor"* ]]
	[[ "$output" == *"::group:: Enable overlay services"* ]]
	[[ "$output" == *"::endgroup::"* ]]
}

@test "10-overlay: overlays the inherited layers first, then the template seams" {
	mkdir -p "${CTX}/custom/config"
	printf '[settings]\n' >"${CTX}/custom/config/example.conf"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${RSYNC_LOG}"
	# Order is the contract: every step writes over the one above it, so the
	# template's own seams deliberately win over the inherited payloads.
	[ "${calls[0]}" = "-rvK ${CTX}/oci/common/shared/ /" ]
	# index 1 is the targeted bluefin/ cherry-pick
	[ "${calls[2]}" = "-rvK ${CTX}/oci/brew/ /" ]
	[[ "${calls[3]}" == *"${CTX}/custom/files/ /"* ]]
	[[ "${calls[4]}" == *"${CTX}/custom/config/ ${SANDBOX}/etc/skel/.config/"* ]]

	# bluefin/ is product opinion and nvidia/ is a paired hardware feature, so
	# neither is ever overlaid wholesale. The cherry-pick uses --relative and
	# names each path instead.
	! grep -q 'bluefin/ /' "${RSYNC_LOG}"
	! grep -q 'nvidia' "${RSYNC_LOG}"
	grep -q -- '--relative' "${RSYNC_LOG}"
}

@test "10-overlay: custom/files mirrors the image root and drops its own README" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${RSYNC_LOG}"
	# The override seam copies to the image root, so a payload can replace
	# anything the inherited layers wrote. Its own README must not ship.
	[[ "${calls[3]}" == *"${CTX}/custom/files/ /"* ]]
	[[ "${calls[3]}" == *"--exclude=/README.md"* ]]
}

@test "10-overlay: a missing Bluefin cherry-pick fails the build" {
	rm -f "${SANDBOX}/usr/share/flatpak/preinstall.d/bazaar.preinstall"

	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"cherry-pick missing"* ]]
}

@test "10-overlay: copies every Brewfile into homebrew/preinstall.d" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# brew-preinstall only reads preinstall.d; a Brewfile in the parent dir is a
	# declaration, not an install. Neptuno wants first-login auto-install.
	[ -f "${HOMEBREW_DIR}/preinstall.d/default.Brewfile" ]
	[ -f "${HOMEBREW_DIR}/preinstall.d/development.Brewfile" ]
	grep -q 'brew "tmux"' "${HOMEBREW_DIR}/preinstall.d/default.Brewfile"
	[ ! -f "${HOMEBREW_DIR}/default.Brewfile" ]
}

@test "10-overlay: consolidates only .just files into 60-custom.just" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ -f "${JUST_DIR}/60-custom.just" ]
	grep -q 'custom-apps-marker:' "${JUST_DIR}/60-custom.just"
	grep -q 'custom-system-marker:' "${JUST_DIR}/60-custom.just"
	! grep -q 'not a just file' "${JUST_DIR}/60-custom.just"
}

@test "10-overlay: consolidates just recipes from subdirectories" {
	# A fork may group recipes by topic. The merge walks the tree, so a nested
	# recipe must not be dropped silently.
	mkdir -p "${CTX}/custom/ujust/nested"
	printf 'nested-marker:\n\techo nested\n' >"${CTX}/custom/ujust/nested/deep.just"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	grep -q 'nested-marker:' "${JUST_DIR}/60-custom.just"
}

@test "10-overlay: consolidates just recipes in sorted, deterministic order" {
	printf 'zzz-marker:\n\techo z\n' >"${CTX}/custom/ujust/zzz-last.just"
	printf 'aaa-marker:\n\techo a\n' >"${CTX}/custom/ujust/aaa-first.just"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	first_content="$(cat "${JUST_DIR}/60-custom.just")"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ "$(cat "${JUST_DIR}/60-custom.just")" = "${first_content}" ]

	# aaa-first.just sorts before zzz-last.just, so its marker must appear first.
	first_line="$(grep 'marker:' "${JUST_DIR}/60-custom.just" | head -n1)"
	[[ "${first_line}" == *"aaa-marker"* ]]
}

@test "10-overlay: repeated runs do not accumulate the consolidated just file" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	count_one="$(grep -c 'custom-apps-marker:' "${JUST_DIR}/60-custom.just")"
	[ "${count_one}" -eq 1 ]

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	count_two="$(grep -c 'custom-apps-marker:' "${JUST_DIR}/60-custom.just")"
	[ "${count_two}" -eq 1 ]
}

@test "10-overlay: separates consolidated just recipes with a blank line" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# Without the separator the last line of one file and the first recipe of
	# the next would merge into a single unparseable line.
	run grep -c '^$' "${JUST_DIR}/60-custom.just"
	[ "$status" -eq 0 ]
	[ "$output" -ge 2 ]
}

@test "10-overlay: copies flatpak preinstall files into preinstall.d" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ -f "${PREINSTALL_DIR}/default.preinstall" ]
	grep -q 'org.mozilla.firefox' "${PREINSTALL_DIR}/default.preinstall"
}

@test "10-overlay: seeds /etc/skel/.config from custom/config when present" {
	mkdir -p "${CTX}/custom/config"
	printf '[settings]\n' >"${CTX}/custom/config/example.conf"
	printf '# seam docs\n' >"${CTX}/custom/config/README.md"

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# rsync is stubbed, so the copy is asserted from the log. Per-user defaults
	# land under .config rather than directly in the home skeleton, and the
	# seam's own README documents the seam instead of shipping into every new
	# user's home.
	mapfile -t calls <"${RSYNC_LOG}"
	[[ "${calls[4]}" == *"${CTX}/custom/config/ ${SANDBOX}/etc/skel/.config/"* ]]
	[[ "${calls[4]}" == *"--exclude=/README.md"* ]]
}

@test "10-overlay: a missing custom/config directory is not an error" {
	[ ! -d "${CTX}/custom/config" ]

	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ ! -d "${SANDBOX}/etc/skel" ]
}

@test "10-overlay: enables exactly the units overlay.toml declares" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	mapfile -t calls <"${SYSTEMCTL_LOG}"
	[ "${#calls[@]}" -eq 12 ]
	[ "${calls[0]}" = "enable flatpak-appstream-refresh.service" ]
	[ "${calls[1]}" = "enable flatpak-preinstall.service" ]
	[ "${calls[2]}" = "enable projectbluefin-countme.timer" ]
	[ "${calls[3]}" = "enable podman.socket" ]
	[ "${calls[4]}" = "enable ublue-system-setup.service" ]
	[ "${calls[5]}" = "enable dconf-update.service" ]
	[ "${calls[6]}" = "enable brew-setup.service" ]
	[ "${calls[7]}" = "enable brew-update.timer" ]
	[ "${calls[8]}" = "enable brew-upgrade.timer" ]
	[ "${calls[9]}" = "--global enable brew-preinstall.service" ]
	[ "${calls[10]}" = "--global enable ublue-user-setup.service" ]
	# User-scope presets are inert in a Containerfile build, so the global
	# enable is asserted rather than assumed.
	[ "${calls[11]}" = "--global is-enabled brew-preinstall.service" ]
}

@test "10-overlay: snapshots the enabled set before any overlay lands" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	[ -f "${UNITS_SNAPSHOT}" ]
}

@test "10-overlay: ships the Flathub remote descriptor once its hash matches the pin" {
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]

	# flatpak imports remotes from this directory the first time it is used, so
	# the descriptor replaces both a unit and a build-time remote-add. It is
	# fetched to a scratch path, checked against the committed sha256, and only
	# then installed: the file names the Url= and GPGKey= every Flatpak on the
	# image is verified against, so it is pinned like every other build input.
	mapfile -t calls <"${CURL_LOG}"
	[ "${#calls[@]}" -eq 1 ]
	[[ "${calls[0]}" == *"https://dl.flathub.org/repo/flathub.flatpakrepo"* ]]
	[[ "${calls[0]}" != *"--output ${SANDBOX}/etc/flatpak/remotes.d/"* ]]

	local installed="${SANDBOX}/etc/flatpak/remotes.d/flathub.flatpakrepo"
	[ -f "${installed}" ]
	cmp -s "${installed}" "${CURL_BODY}"
	[ "$(stat -c '%a' "${installed}")" = "644" ]
}

@test "10-overlay: pinned descriptor hash matches the committed fixture" {
	# Guards the constant itself: if the fixture is refreshed without bumping
	# the pin (or vice versa) the build would fail closed, which this catches
	# before CI does.
	local pinned
	pinned="$(sed -nE 's/^FLATHUB_REPO_SHA256=([0-9a-f]{64})$/\1/p' "${OVERLAY_SRC}")"
	[ -n "${pinned}" ]
	[ "${pinned}" = "$(sha256sum "${CURL_BODY}" | cut -d' ' -f1)" ]
}

@test "10-overlay: a descriptor that does not match the pin fails the build and installs nothing" {
	local tampered="${TEST_ROOT}/tampered.flatpakrepo"
	sed -e 's#^Url=.*#Url=https://evil.example/repo/#' \
		-e 's#^GPGKey=.*#GPGKey=QUFBQQ==#' \
		"${CURL_BODY}" >"${tampered}"
	export CURL_BODY="${tampered}"

	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"FAILED"* ]]
	[ ! -e "${SANDBOX}/etc/flatpak/remotes.d/flathub.flatpakrepo" ]

	# Failure happens before the services are enabled, so a half-built image
	# cannot slip past with the remote missing.
	[ ! -s "${SYSTEMCTL_LOG}" ]
}

@test "10-overlay: an empty brew dir fails the build despite nullglob (regression guard)" {
	# nullglob makes the glob expand to nothing, which leaves cp with a single
	# argument — cp then fails with 'missing destination file operand'. See
	# issue #287: nullglob does not make these copies optional.
	rm -f "${CTX}"/custom/brew/*.Brewfile
	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "10-overlay: an empty flatpaks dir fails the build despite nullglob (regression guard)" {
	rm -f "${CTX}"/custom/flatpaks/*.preinstall
	run bash "${SCRIPT}"
	[ "$status" -ne 0 ]
}

@test "10-overlay: an empty ujust dir still produces a consolidated just file" {
	rm -f "${CTX}"/custom/ujust/*
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[ -f "${JUST_DIR}/60-custom.just" ]
}

@test "10-overlay: restores default glob behaviour before finishing" {
	cat >>"${SCRIPT}" <<'EOF'
shopt -q nullglob || echo "NULLGLOB_OFF"
EOF
	run bash "${SCRIPT}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"NULLGLOB_OFF"* ]]
}
