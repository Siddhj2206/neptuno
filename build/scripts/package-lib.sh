#!/usr/bin/bash
###############################################################################
# Shared package-manifest helpers (sourced by layer scripts).
###############################################################################
# Depends on the read-packages script (default below; override before
# sourcing if the path ever moves).
READ_PKGS="${READ_PKGS:-/ctx/build/scripts/read-packages}"

# Install a manifest's [fedora] section in one dnf5 transaction and assert
# every listed package landed (the build fails listing missing names).
# Trailing arguments are passed through to dnf5 (e.g. --enablerepo).
install_fedora_section() {
	local manifest="$1"
	local label="$2"
	shift 2
	local -a packages

	readarray -t packages < <("${READ_PKGS}" "${manifest}" fedora)
	dnf5 install -y "$@" "${packages[@]}"
	assert_packages_present "${label}" "${packages[@]}"
}

# Install every ["copr:<owner>/<project>"] section of a manifest. ALL COPRs
# are enabled FIRST, then every section's packages install in ONE
# transaction: the explicit args win candidate selection, so cross-COPR
# dependencies resolve to the wanted build — e.g. dms's deps live in either
# the dms or danklinux stash, and together quickshell-git replaces the plain
# quickshell a coprdep would otherwise drag in. COPRs stay enabled through
# the build; clean-stage.sh disables them in the final image (rule 3).
# Exits non-zero if any listed package did not install.
install_copr_sections() {
	local manifest="$1"
	local copr_section copr_id
	local -a copr_sections packages all_packages
	local missing=()
	local pkg

	# Phase 1 — enable every COPR section (repo files may also declare
	# coprdeps on each other; all of it resolves together in phase 2).
	mapfile -t copr_sections < <("${READ_PKGS}" "${manifest}" --sections copr:)
	for copr_section in "${copr_sections[@]}"; do
		copr_id="${copr_section#copr:}"
		echo "Enabling COPR ${copr_id}"
		dnf5 -y copr enable "${copr_id}"
	done

	# Phase 2 — one install transaction across every section.
	for copr_section in "${copr_sections[@]}"; do
		readarray -t packages < <("${READ_PKGS}" "${manifest}" "${copr_section}")
		all_packages+=("${packages[@]}")
	done
	if [[ ${#all_packages[@]} -eq 0 ]]; then
		echo "No COPR packages in ${manifest}."
		return 0
	fi
	echo "Installing ${all_packages[*]} from COPRs"
	dnf5 -y install "${all_packages[@]}"

	# Phase 3 — assert gate.
	for pkg in "${all_packages[@]}"; do
		rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "ERROR: COPR packages failed to install: ${missing[*]}" >&2
		return 1
	fi
	echo "All COPR packages present."
}

# Assert every package argument is installed; first arg is a human label.
assert_packages_present() {
	local label="$1"
	shift
	local missing=()
	local pkg

	for pkg in "$@"; do
		rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "ERROR: ${label} failed to install: ${missing[*]}" >&2
		return 1
	fi
	echo "${label}: $# packages present."
}

# Assert every package argument is provided by the given RPM VENDOR string —
# catches a repo-priority slip silently swapping in a different build.
assert_vendor() {
	local label="$1"
	local vendor="$2"
	shift 2
	local missing=()
	local pkg

	for pkg in "$@"; do
		rpm -q --qf "%{NAME} %{VENDOR}\n" "${pkg}" | grep -qFw "${vendor}" || missing+=("${pkg}")
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "ERROR: ${label} not sourced from ${vendor}: ${missing[*]}" >&2
		return 1
	fi
	echo "${label}: all $# packages from ${vendor}."
}
