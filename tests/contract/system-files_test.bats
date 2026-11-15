#!/usr/bin/env bats
# Shipped files agree with the manifests and with each other.

REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "every shipped unit with an [Install] section is declared in a manifest" {
	declared="$("${REPO}/build/scripts/systemd-units" declared "${REPO}"/build/packages/*.toml)"
	missing=()
	while IFS= read -r unit; do
		grep -q '^\[Install\]' "${unit}" || continue
		name="$(basename "${unit}")"
		grep -qx "${name}" <<<"${declared}" || missing+=("${name}")
	done < <(find "${REPO}/system_files" -path '*/systemd/*' -type f \( -name '*.service' -o -name '*.timer' -o -name '*.path' -o -name '*.socket' -o -name '*.mount' -o -name '*.swap' \))
	[ "${#missing[@]}" -eq 0 ] || { echo "undeclared: ${missing[*]}"; false; }
}

@test "units linked by [[wants]] that the image ships exist in system_files" {
	run python3 - "${REPO}" <<'PY'
import pathlib, sys, tomllib
repo = pathlib.Path(sys.argv[1])
shipped = {p.name for p in (repo / "system_files").rglob("*") if p.is_file()}
packaged = {"dms.service", "dsearch.service"}
for manifest in (repo / "build/packages").glob("*.toml"):
    for item in tomllib.load(manifest.open("rb")).get("wants", []):
        for unit in item["units"]:
            if unit not in shipped | packaged:
                sys.exit(f"{manifest.name}: {unit} is neither shipped nor a known package unit")
PY
	[ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "shipped scripts and units are executable or parse as unit files" {
	for f in "${REPO}"/system_files/shared/usr/bin/* "${REPO}"/system_files/shared/usr/libexec/neptuno/*; do
		[ -x "${f}" ] || { echo "not executable: ${f}"; false; }
	done
}

@test "the neptuno justfile parses" {
	run just --justfile "${REPO}/system_files/shared/usr/share/neptuno/justfile" --summary
	[ "$status" -eq 0 ]
}

@test "the greetd config names a user" {
	grep -Eq '^user *= *"[a-z_][a-z0-9_-]*"' "${REPO}/system_files/desktop/etc/greetd/config.toml"
}

@test "nothing is shipped under /usr/etc" {
	[ ! -e "${REPO}/system_files/shared/usr/etc" ]
	[ ! -e "${REPO}/system_files/desktop/usr/etc" ]
}

@test "every dms include in the skel niri config has a shipped file" {
	# DMS does not reliably create these itself; a missing file silently drops
	# its settings because the includes are optional.
	skel="${REPO}/system_files/desktop/etc/skel/.config/niri"
	missing=()
	while IFS= read -r inc; do
		[ -f "${skel}/${inc}" ] || missing+=("${inc}")
	done < <(sed -n 's/^include optional=true "\(dms\/[^"]*\)"/\1/p' "${skel}/config.kdl")
	[ "${#missing[@]}" -eq 0 ] || { echo "missing: ${missing[*]}"; false; }
}

@test "the seeded DMS settings are valid JSON with no personal paths" {
	settings="${REPO}/system_files/desktop/etc/skel/.config/dms/settings.json"
	python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${settings}"
	! grep -Eq '/(var/)?home/|@[a-z0-9.-]+\.[a-z]{2,}' "${settings}"
}

@test "render-niri-skel puts a commented copy of base.kdl in the skel config" {
	cp "${REPO}/system_files/desktop/etc/skel/.config/niri/config.kdl" "${BATS_TEST_TMPDIR}/config.kdl"
	run "${REPO}/build/scripts/render-niri-skel" \
		"${REPO}/system_files/desktop/usr/share/neptuno/niri/base.kdl" "${BATS_TEST_TMPDIR}/config.kdl"
	[ "$status" -eq 0 ]
	! grep -q '@NEPTUNO_NIRI_DEFAULTS@' "${BATS_TEST_TMPDIR}/config.kdl"
	grep -qx '// prefer-no-csd' "${BATS_TEST_TMPDIR}/config.kdl"
	# Nothing from base.kdl is live in the user file except the include.
	! grep -qx 'prefer-no-csd' "${BATS_TEST_TMPDIR}/config.kdl"
}

@test "render-niri-skel fails when the marker is missing" {
	printf 'include "x"\n' >"${BATS_TEST_TMPDIR}/config.kdl"
	run "${REPO}/build/scripts/render-niri-skel" \
		"${REPO}/system_files/desktop/usr/share/neptuno/niri/base.kdl" "${BATS_TEST_TMPDIR}/config.kdl"
	[ "$status" -ne 0 ]
}

@test "systemd-units rejects an unknown [services] key" {
	printf '[services]\nsystm = ["a.service"]\n' >"${BATS_TEST_TMPDIR}/bad.toml"
	run "${REPO}/build/scripts/systemd-units" declared "${BATS_TEST_TMPDIR}/bad.toml"
	[ "${status}" -ne 0 ]
	[[ "${output}" == *"unknown [services] keys"* ]]
}

@test "ensure-homes only creates missing homes under /home or /var/home" {
	root="${BATS_TEST_TMPDIR}"
	mkdir -p "${root}/skel/.config" "${root}/var/home"
	echo seeded >"${root}/skel/.config/f"
	ln -s /nonexistent "${root}/var/home/dangling"
	cat >"${root}/passwd" <<PW
ok:x:$(id -u):$(id -g)::${root}/var/home/ok:/usr/bin/fish
dangling:x:$(id -u):$(id -g)::${root}/var/home/dangling:/usr/bin/fish
outside:x:$(id -u):$(id -g)::${root}/opt/outside:/usr/bin/fish
svc:x:1001:1001::${root}/var/home/svc:/sbin/nologin
PW
	# Point the script at the fixture: its passwd, skel and home pattern.
	sed -e "s|</etc/passwd|<${root}/passwd|" -e "s|/etc/skel|${root}/skel|g" \
		-e "s|\\^/(var/)?home/|^${root}/(var/)?home/|" \
		"${REPO}/system_files/shared/usr/libexec/neptuno/ensure-homes" >"${root}/run.sh"
	run bash "${root}/run.sh"
	[ "${status}" -eq 0 ]
	[ -f "${root}/var/home/ok/.config/f" ]
	[ -L "${root}/var/home/dangling" ]
	[ ! -e "${root}/opt/outside" ]
	[ ! -e "${root}/var/home/svc" ]
}
