#!/usr/bin/env bats
# build/scripts/package-lib.sh with dnf5, rpm and systemctl stubbed.

REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

setup() {
	BIN="${BATS_TEST_TMPDIR}/bin"
	LOG="${BATS_TEST_TMPDIR}/calls.log"
	mkdir -p "${BIN}"
	for tool in dnf5 rpm systemctl; do
		printf '#!/usr/bin/bash\nprintf "%%s %%s\\n" %s "$*" >>"%s"\n' "${tool}" "${LOG}" >"${BIN}/${tool}"
		chmod +x "${BIN}/${tool}"
	done
	export PATH="${BIN}:${PATH}"
	export READ_PKGS="${REPO}/build/scripts/read-packages"
	# shellcheck source=/dev/null
	source "${REPO}/build/scripts/package-lib.sh"
	MANIFEST="${BATS_TEST_TMPDIR}/m.toml"
}

@test "install_copr_sections limits each COPR to its packages and deps, then disables it" {
	cat >"${MANIFEST}" <<'TOML'
["copr:owner/one"]
packages = ["a", "b"]
deps = ["c"]

["copr:owner/two"]
packages = ["d"]
TOML
	run install_copr_sections "${MANIFEST}"
	[ "$status" -eq 0 ]
	grep -qx 'dnf5 -y copr enable owner/one' "${LOG}"
	grep -qx 'dnf5 -y install --setopt=copr:copr.fedorainfracloud.org:owner:one.includepkgs=a,b,c --setopt=copr:copr.fedorainfracloud.org:owner:two.includepkgs=d a b d' "${LOG}"
	grep -qx 'dnf5 -y copr disable owner/one' "${LOG}"
	grep -qx 'dnf5 -y copr disable owner/two' "${LOG}"
}

@test "disable_services_section skips a unit the base does not ship" {
	export UNIT_ROOT="${BATS_TEST_TMPDIR}/root"
	mkdir -p "${UNIT_ROOT}/usr/lib/systemd/system"
	touch "${UNIT_ROOT}/usr/lib/systemd/system/present.service"
	cat >"${MANIFEST}" <<'TOML'
[services]
disabled = ["present.service", "gone.service"]
TOML
	run disable_services_section "${MANIFEST}" test
	[ "$status" -eq 0 ]
	[[ "$output" == *"::warning::test: gone.service does not exist"* ]]
	grep -qx 'systemctl disable present.service' "${LOG}"
	! grep -q 'gone.service' "${LOG}"
}

@test "link_wanted_units fails on a unit that is not installed" {
	export UNIT_ROOT="${BATS_TEST_TMPDIR}/root"
	mkdir -p "${UNIT_ROOT}/usr/lib/systemd/user"
	cat >"${BATS_TEST_TMPDIR}/m.toml" <<'TOML'
[[wants]]
scope = "user"
target = "niri.service"
units = ["missing.service"]
TOML
	run link_wanted_units "${BATS_TEST_TMPDIR}/m.toml" test
	[ "${status}" -ne 0 ]
	[[ "${output}" == *"missing.service is not installed"* ]]
}
