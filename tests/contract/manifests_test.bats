#!/usr/bin/env bats
# Contract tests for the Neptuno manifest layer.
#
# The manifests are the image's declaration of record: packages, removals,
# third-party repositories, and systemd enablement all live in
# build/packages/*.toml. These tests keep that contract honest without needing
# a built image.

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGES_DIR="${REPO_ROOT}/build/packages"
UNITS="${REPO_ROOT}/build/scripts/systemd-units"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/manifests.${BATS_TEST_NUMBER:-0}.$$"
	ROOT="${TEST_ROOT}/root"
	mkdir -p "${ROOT}/usr/lib/systemd/system/multi-user.target.wants"
	mkdir -p "${ROOT}/etc/systemd/user"
	: >"${TEST_ROOT}/snapshot"
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "manifests: every build/packages/*.toml parses" {
	for manifest in "${PACKAGES_DIR}"/*.toml; do
		run python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1], 'rb'))" "${manifest}"
		[ "$status" -eq 0 ]
	done
}

@test "manifests: package sections are lists of non-empty strings" {
	for manifest in "${PACKAGES_DIR}"/*.toml; do
		run python3 - "${manifest}" <<'PY'
import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
for name, section in data.items():
    if name in ("services", "wants"):
        continue
    if not isinstance(section, dict):
        sys.exit(f"{name}: not a table")
    packages = section.get("packages")
    if packages is None:
        continue
    if not isinstance(packages, list) or not all(isinstance(p, str) and p for p in packages):
        sys.exit(f"{name}.packages: not a list of non-empty strings")
PY
		[ "$status" -eq 0 ]
	done
}

@test "manifests: declared units are valid and unique" {
	run python3 - "${PACKAGES_DIR}" <<'PY'
import pathlib, re, sys, tomllib

unit = re.compile(r"^[A-Za-z0-9@_.:-]+\.(service|timer|socket|path|mount|target|slice)$")
seen = {}

def declare(name, origin):
    if not unit.match(name):
        sys.exit(f"{origin}: not a unit name: {name}")
    if name in seen:
        sys.exit(f"{name} declared in both {seen[name]} and {origin}")
    seen[name] = origin

for manifest in sorted(pathlib.Path(sys.argv[1]).glob("*.toml")):
    data = tomllib.load(open(manifest, "rb"))

    services = data.get("services", {})
    for scope in ("system", "user"):
        entries = services.get(scope, [])
        if not isinstance(entries, list):
            sys.exit(f"{manifest.name}: [services].{scope} is not a list")
        for entry in entries:
            declare(entry, manifest.name)

    disabled = services.get("disabled", [])
    if not isinstance(disabled, list):
        sys.exit(f"{manifest.name}: [services].disabled is not a list")
    for entry in disabled:
        if not unit.match(entry):
            sys.exit(f"{manifest.name}: not a unit name: {entry}")
        if entry in seen:
            sys.exit(f"{entry} is both declared and disabled in {manifest.name}")

    wants = data.get("wants", [])
    if not isinstance(wants, list):
        sys.exit(f"{manifest.name}: [[wants]] is not an array of tables")
    for item in wants:
        if not isinstance(item, dict):
            sys.exit(f"{manifest.name}: every [[wants]] entry must be a table")
        if item.get("scope") not in ("system", "user"):
            sys.exit(f"{manifest.name}: [[wants]] scope must be system or user")
        target = item.get("target")
        if not isinstance(target, str) or not unit.match(target):
            sys.exit(f"{manifest.name}: [[wants]] target is not a unit name: {target}")
        entries = item.get("units", [])
        if not isinstance(entries, list):
            sys.exit(f"{manifest.name}: [[wants]] units is not a list")
        for entry in entries:
            declare(entry, manifest.name)
PY
	[ "$status" -eq 0 ]
}

@test "units: snapshot records enabled units" {
	touch "${ROOT}/usr/lib/systemd/system/multi-user.target.wants/a.service"

	run "${UNITS}" snapshot "${TEST_ROOT}/snapshot" --root "${ROOT}"
	[ "$status" -eq 0 ]
	grep -qx 'a.service' "${TEST_ROOT}/snapshot"
}

@test "units: check passes when every new unit is declared" {
	touch "${ROOT}/usr/lib/systemd/system/multi-user.target.wants/b.service"
	printf '[services]\nsystem = ["b.service"]\n' >"${TEST_ROOT}/manifest.toml"

	run "${UNITS}" check "${TEST_ROOT}/snapshot" "${TEST_ROOT}/manifest.toml" --root "${ROOT}"
	[ "$status" -eq 0 ]
}

@test "units: check fails when a new unit is undeclared" {
	touch "${ROOT}/usr/lib/systemd/system/multi-user.target.wants/stray.service"
	printf '[services]\nsystem = []\n' >"${TEST_ROOT}/manifest.toml"

	run "${UNITS}" check "${TEST_ROOT}/snapshot" "${TEST_ROOT}/manifest.toml" --root "${ROOT}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"stray.service"* ]]
}

@test "units: units already enabled before the snapshot are not flagged" {
	touch "${ROOT}/usr/lib/systemd/system/multi-user.target.wants/preexisting.service"
	"${UNITS}" snapshot "${TEST_ROOT}/snapshot" --root "${ROOT}"
	printf '[services]\nsystem = []\n' >"${TEST_ROOT}/manifest.toml"

	run "${UNITS}" check "${TEST_ROOT}/snapshot" "${TEST_ROOT}/manifest.toml" --root "${ROOT}"
	[ "$status" -eq 0 ]
}
