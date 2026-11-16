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

# Remove packages from a manifest section. Only currently installed packages
# enter the transaction, so a future base that already drops an
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

# Install every ["copr:<owner>/<project>"] section of a manifest in ONE
# transaction, then disable the COPRs again.
#
# Each COPR is limited (includepkgs) to the packages its section names plus the
# section's optional `deps` list. COPRs such as duxlabs/dux-repo also rebuild
# Fedora packages (greetd, cava, quickshell); without the limit a newer COPR
# build would silently replace Fedora's. One transaction across every section
# still lets cross-COPR dependencies resolve together, so quickshell-git
# satisfies dms instead of the stable quickshell.
#
# Exits non-zero if any listed package did not install.
install_copr_sections() {
	local manifest="$1"
	local copr_section copr_id repo_id include
	local -a copr_sections packages deps all_packages setopts
	local missing=()
	local pkg

	mapfile -t copr_sections < <("${READ_PKGS}" "${manifest}" --sections copr:)
	if [[ ${#copr_sections[@]} -eq 0 ]]; then
		echo "No COPR sections in ${manifest}."
		return 0
	fi

	for copr_section in "${copr_sections[@]}"; do
		copr_id="${copr_section#copr:}"
		repo_id="copr:copr.fedorainfracloud.org:${copr_id//\//:}"
		readarray -t packages < <("${READ_PKGS}" "${manifest}" "${copr_section}")
		readarray -t deps < <("${READ_PKGS}" "${manifest}" "${copr_section}" deps 2>/dev/null || true)
		include="$(IFS=,; echo "${packages[*]}${deps[*]:+,${deps[*]}}")"
		echo "Enabling COPR ${copr_id} (limited to: ${include})"
		dnf5 -y copr enable "${copr_id}"
		setopts+=("--setopt=${repo_id}.includepkgs=${include}")
		all_packages+=("${packages[@]}")
	done

	echo "Installing ${all_packages[*]} from COPRs"
	dnf5 -y install "${setopts[@]}" "${all_packages[@]}"

	for copr_section in "${copr_sections[@]}"; do
		dnf5 -y copr disable "${copr_section#copr:}"
	done

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

# Enable the [services] section of a manifest: system units with
# `systemctl enable`, user units with `systemctl --global enable`.
#
# A manifest without [services] is a no-op, so a layer can opt out. The unit
# must already exist (package installed or overlay applied); `systemctl enable`
# fails closed and names the unit otherwise. `units check` audits the union of
# every manifest in 90-cleanup.sh, so anything enabled outside this path fails
# the build.
enable_services_section() {
	local manifest="$1"
	local label="${2:-${manifest}}"
	local -a system_units=() user_units=()
	local unit

	if ! "${READ_PKGS}" "${manifest}" --sections services >/dev/null 2>&1; then
		echo "${label}: no [services] section."
		return 0
	fi

	readarray -t system_units < <("${READ_PKGS}" "${manifest}" services system 2>/dev/null || true)
	readarray -t user_units < <("${READ_PKGS}" "${manifest}" services user 2>/dev/null || true)

	for unit in "${system_units[@]}"; do
		[[ -n "${unit}" ]] || continue
		systemctl enable "${unit}"
	done
	for unit in "${user_units[@]}"; do
		[[ -n "${unit}" ]] || continue
		systemctl --global enable "${unit}"
	done

	echo "${label}: enabled ${#system_units[@]} system and ${#user_units[@]} user units."
}

# Disable the [services].disabled units of a manifest. A base preset may enable
# a unit we do not want; naming it here keeps the choice explicit and the audit
# meaningful. A unit the base no longer ships is skipped with a warning rather
# than failing the build: a daily rebuild must not break because Fedora dropped
# a daemon we were turning off anyway. Runs after enable_services_section.
disable_services_section() {
	local manifest="$1"
	local label="${2:-${manifest}}"
	local -a units=()
	local unit count=0

	if ! "${READ_PKGS}" "${manifest}" --sections services >/dev/null 2>&1; then
		echo "${label}: no [services] section."
		return 0
	fi

	readarray -t units < <("${READ_PKGS}" "${manifest}" services disabled 2>/dev/null || true)
	for unit in "${units[@]}"; do
		[[ -n "${unit}" ]] || continue
		if [[ ! -e "${UNIT_ROOT:-}/usr/lib/systemd/system/${unit}" && ! -e "${UNIT_ROOT:-}/etc/systemd/system/${unit}" ]]; then
			echo "::warning::${label}: ${unit} does not exist; nothing to disable"
			continue
		fi
		systemctl disable "${unit}"
		count=$((count + 1))
	done

	echo "${label}: disabled ${count} units."
}

# Link units into a target's .wants directory instead of enabling them for
# every session. The manifest names the scope, target, and units:
#
#   [[wants]]
#   scope = "user"
#   target = "niri.service"
#   units = ["dms.service"]
#
# This is how a compositor-scoped shell starts with the compositor without
# starting in another desktop's session. The target is data, so the helper has
# no compositor-specific knowledge.
link_wanted_units() {
	local manifest="$1"
	local label="${2:-${manifest}}"
	local rows scope target unit dir count=0

	if ! rows="$("${READ_PKGS}" "${manifest}" --wants)"; then
		echo "ERROR: ${label}: cannot read [[wants]] from ${manifest}" >&2
		return 1
	fi
	if [[ -z "${rows}" ]]; then
		echo "${label}: no wanted units."
		return 0
	fi

	while IFS=$'\t' read -r scope target unit; do
		[[ -n "${unit}" ]] || continue
		case "${scope}" in
			system) dir="/usr/lib/systemd/system/${target}.wants" ;;
			user) dir="/usr/lib/systemd/user/${target}.wants" ;;
			*)
				echo "ERROR: ${label}: unknown scope '${scope}'" >&2
				return 1
				;;
		esac
		if [[ ! -e "${UNIT_ROOT:-}/usr/lib/systemd/${scope}/${unit}" ]]; then
			echo "ERROR: ${label}: ${scope} unit ${unit} is not installed; cannot link it into ${target}" >&2
			return 1
		fi
		mkdir -p "${dir}"
		ln -sfn "/usr/lib/systemd/${scope}/${unit}" "${dir}/${unit}"
		count=$((count + 1))
	done <<<"${rows}"

	echo "${label}: linked ${count} wanted units."
}
