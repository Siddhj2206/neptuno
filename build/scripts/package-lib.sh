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

# Install DNF package groups declared in a manifest section. DNF resolves a
# group's package membership from the pinned Fedora repositories.
install_fedora_groups() {
	local manifest="$1"
	local section="$2"
	local label="$3"
	local -a groups

	readarray -t groups < <("${READ_PKGS}" "${manifest}" "${section}" groups)
	if [[ ${#groups[@]} -eq 0 ]]; then
		echo "${label}: no package groups declared."
		return 0
	fi

	dnf5 group install -y "${groups[@]}"
	echo "${label}: ${#groups[@]} groups installed."
}

# Remove packages from a manifest section. Only currently installed packages
# enter the transaction, so a future Silverblue base that already drops an
# entry does not make the image build fail. Assert every requested package is
# absent afterwards.
remove_fedora_section() {
	local manifest="$1"
	local label="$2"
	local -a requested installed
	local package

	readarray -t requested < <("${READ_PKGS}" "${manifest}" remove)
	for package in "${requested[@]}"; do
		rpm -q "${package}" >/dev/null 2>&1 && installed+=("${package}")
	done
	if [[ ${#installed[@]} -eq 0 ]]; then
		echo "${label}: no matching packages installed."
		return 0
	fi

	dnf5 remove -y "${installed[@]}"
	assert_packages_absent "${label}" "${requested[@]}"
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

# Install packages from a named [third-party:<repo-id>] manifest section, then
# remove the repository definition so the final image cannot update from it
# outside a newly built image. Metadata and package source assertions are read
# from the manifest rather than hard-coded in the calling layer.
install_third_party_repo_section() {
	local manifest="$1"
	local section="$2"
	local label="$3"
	local repo_url repo_id repo_file packager
	local -a packages

	repo_url="$("${READ_PKGS}" "${manifest}" "${section}" repo_url)"
	repo_id="$("${READ_PKGS}" "${manifest}" "${section}" repo_id)"
	repo_file="$("${READ_PKGS}" "${manifest}" "${section}" repo_file)"
	packager="$("${READ_PKGS}" "${manifest}" "${section}" packager)"
	readarray -t packages < <("${READ_PKGS}" "${manifest}" "${section}")

	dnf5 config-manager addrepo --from-repofile="${repo_url}"
	dnf5 install -y --from-repo="${repo_id}" "${packages[@]}"
	assert_packages_present "${label}" "${packages[@]}"
	assert_packager "${label}" "${packager}" "${packages[@]}"
	dnf5 config-manager setopt "${repo_id}.enabled=0"
	rm -f "/etc/yum.repos.d/${repo_file}"
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

# Assert every package argument is absent; first arg is a human label.
assert_packages_absent() {
	local label="$1"
	shift
	local remaining=()
	local package

	for package in "$@"; do
		rpm -q "${package}" >/dev/null 2>&1 && remaining+=("${package}")
	done

	if [[ ${#remaining[@]} -gt 0 ]]; then
		echo "ERROR: ${label} failed to remove: ${remaining[*]}" >&2
		return 1
	fi
	echo "${label}: $# packages absent."
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

# Assert every package argument came from an expected RPM Packager substring.
# Some trusted third-party RPMs (including Tailscale) intentionally leave the
# RPM Vendor field empty, so vendor assertions cannot establish their source.
assert_packager() {
	local label="$1"
	local packager="$2"
	shift 2
	local mismatched=()
	local pkg

	for pkg in "$@"; do
		rpm -q --qf "%{NAME} %{PACKAGER}\n" "${pkg}" | grep -Fq "${packager}" || mismatched+=("${pkg}")
	done

	if [[ ${#mismatched[@]} -gt 0 ]]; then
		echo "ERROR: ${label} not packaged by ${packager}: ${mismatched[*]}" >&2
		return 1
	fi
	echo "${label}: all $# packages packaged by ${packager}."
}
