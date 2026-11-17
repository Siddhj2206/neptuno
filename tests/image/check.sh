#!/usr/bin/bash
# Image content tests (doc/product.md 13.2). Runs inside the built image with
# the repository mounted read-only at /src:
#   podman run --rm -v "$PWD:/src:ro" <image> /src/tests/image/check.sh
# Every check runs; the script fails at the end if any did.
set -uo pipefail

SRC=/src
PACKAGES="${SRC}/build/packages"
READ="${SRC}/build/scripts/read-packages"
failures=0

fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

pass() {
	echo "ok:   $*"
}

# Every package a manifest installs is present; every [remove] package is gone.
for manifest in "${PACKAGES}"/*.toml; do
	while read -r section; do
		case "${section}" in
		fedora | copr:* | third-party:*) ;;
		*) continue ;;
		esac
		mapfile -t pkgs < <("${READ}" "${manifest}" "${section}")
		if missing="$(rpm -q "${pkgs[@]}" | grep 'is not installed')"; then
			fail "$(basename "${manifest}") [${section}]: ${missing}"
		else
			pass "$(basename "${manifest}") [${section}]: ${#pkgs[@]} packages installed"
		fi
	done < <("${READ}" "${manifest}" --sections)

	if "${READ}" "${manifest}" --sections | grep -qx remove; then
		while read -r pkg; do
			rpm -q --quiet "${pkg}" && fail "$(basename "${manifest}") [remove]: ${pkg} is installed"
		done < <("${READ}" "${manifest}" remove)
		pass "$(basename "${manifest}") [remove]: checked"
	fi
done

# Only Fedora's own repositories (as shipped by fedora-repos) are left enabled.
enabled="$(dnf5 repolist --enabled 2>/dev/null | awk 'NR > 1 { print $1 }' | sort | tr '\n' ' ')"
unexpected="$(tr ' ' '\n' <<<"${enabled}" | grep -vxE 'fedora|updates|updates-archive|' || true)"
if [[ -n "${unexpected}" ]]; then
	fail "repositories left enabled: ${unexpected//$'\n'/ }"
else
	pass "enabled repositories: ${enabled}"
fi

# The keyless model ships no signature policy of its own (section 11): the
# container policy and registries.d are exactly what their packages ship.
for f in /etc/containers/policy.json /etc/containers/registries.d/*; do
	[[ -e "${f}" ]] || continue
	if ! rpm -qf --quiet "${f}"; then
		fail "${f} is not owned by any package"
	elif rpm -Vf "${f}" 2>/dev/null | awk -v f="${f}" '$NF == f && $1 ~ /5/' | grep -q .; then
		fail "${f} differs from its package"
	fi
done
pass "container signature policy is Fedora's"

# Our system units parse and reference things that exist.
mapfile -t units < <(find "${SRC}"/system_files/*/usr/lib/systemd/system -maxdepth 1 -type f \
	-name 'neptuno-*' -printf '/usr/lib/systemd/system/%f\n' | sort)
if out="$(systemd-analyze verify --man=no "${units[@]}" 2>&1)" && [[ -z "${out}" ]]; then
	pass "systemd-analyze verify: ${#units[@]} system units"
else
	fail "systemd-analyze verify:"$'\n'"${out}"
fi

# The default niri config, with every DMS include, is valid.
if out="$(niri validate -c /etc/skel/.config/niri/config.kdl 2>&1)"; then
	pass "niri validate /etc/skel/.config/niri/config.kdl"
else
	fail "niri validate:"$'\n'"${out}"
fi

# Sudoers drop-ins parse, and the default login shell is fish.
if out="$(visudo -cq 2>&1)"; then
	pass "visudo -c"
else
	fail "visudo -c: ${out}"
fi
if grep -qx 'SHELL=/usr/bin/fish' /etc/default/useradd; then
	pass "useradd SHELL=/usr/bin/fish"
else
	fail "/etc/default/useradd does not default to fish"
fi

# Login shells find the system's commands before the Nix profile's, so a Nix
# compiler never replaces /usr/bin/cc (doc/product.md 7.1). nix.fish adds the
# profile only if it exists, so a throwaway HOME gets one first.
first_of() {
	tr ':' '\n' <<<"$1" | grep -m1 -xE '/usr/bin|.*/\.nix-profile/bin'
}
path_home="$(mktemp -d)"
mkdir -p "${path_home}/.nix-profile/bin"
for cmd in "bash -l -c 'echo \$PATH'" "fish -l -c 'string join : \$PATH'"; do
	path="$(HOME="${path_home}" eval "${cmd}" 2>/dev/null </dev/null)"
	if [[ "$(first_of "${path}")" == /usr/bin ]] && grep -q '\.nix-profile/bin' <<<"${path}"; then
		pass "${cmd%% *} login PATH: /usr/bin before the Nix profile"
	else
		fail "${cmd%% *} login PATH: ${path}"
	fi
done

echo
if ((failures > 0)); then
	echo "${failures} check(s) failed" >&2
	exit 1
fi
echo "All image checks passed"
