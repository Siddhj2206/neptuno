#!/usr/bin/env bash
# The last mutation before metadata and `bootc container lint`: finalise
# package sources, audit enablement, prune build artifacts.
#
# CLEAN_ROOT is a test seam: it prefixes every filesystem path.
set -euo pipefail

CLEAN_ROOT="${CLEAN_ROOT:-/}"
REPOS_DIRS=(
	"${CLEAN_ROOT}/etc/yum.repos.d"
	# Fedora 45 also keeps packaged repo files here; sweep both.
	"${CLEAN_ROOT}/usr/share/dnf5/repos.d"
)

echo "::group:: Finalise package repositories"
# Remove the build-time dnf settings so the base's dnf.conf is unchanged.
dnf5 config-manager unsetopt keepcache install_weak_deps

disable_repo_file() {
	[[ -f "$1" ]] || return 0
	sed -i 's@enabled=1@enabled=0@g' "$1"
}

for repos_dir in "${REPOS_DIRS[@]}"; do
	for repo_file in "${repos_dir}"/_copr:*.repo "${repos_dir}"/_copr_*.repo; do
		disable_repo_file "${repo_file}"
	done
	for repo_name in tailscale fedora-cisco-openh264 fedora-coreos-pool; do
		disable_repo_file "${repos_dir}/${repo_name}.repo"
	done
done

for repos_dir in "${REPOS_DIRS[@]}"; do
	for repo_file in "${repos_dir}"/_copr:*.repo "${repos_dir}"/_copr_*.repo; do
		[[ -f "${repo_file}" ]] || continue
		if grep -qE '^enabled=1' "${repo_file}"; then
			echo "::error::third-party repository still enabled: $(basename "${repo_file}")" >&2
			exit 1
		fi
	done
done
echo "::endgroup::"

echo "::group:: Audit systemd enablement"
# A unit may only become enabled through a manifest. Anything else newly
# enabled since 10-packages.sh took its snapshot fails the build, whether an
# RPM scriptlet or a shipped symlink put it there.
"${UNITS_BIN:-/ctx/build/scripts/systemd-units}" check \
	"${UNITS_SNAPSHOT:-/var/tmp/neptuno-units.before}" \
	"${UNITS_MANIFESTS:-/ctx/build/packages}"/*.toml \
	--root "${UNITS_ROOT:-/}"
echo "::endgroup::"

echo "::group:: Prune build artifacts"
find "${CLEAN_ROOT}/var" -mindepth 1 -maxdepth 1 -type d \! -name cache -exec rm -fr {} \;
find "${CLEAN_ROOT}/var/cache" -mindepth 1 -maxdepth 1 -type d \! -name libdnf5 -exec rm -fr {} \;

# Buildah may hold bind mounts under these; clear contents, keep mountpoints.
for runtime_dir in tmp boot; do
	mkdir -p "${CLEAN_ROOT:?}/${runtime_dir}"
	find "${CLEAN_ROOT:?}/${runtime_dir}" -mindepth 1 -maxdepth 1 -print0 |
		while IFS= read -r -d '' entry; do
			mountpoint -q "${entry}" 2>/dev/null && continue
			rm -rf "${entry}"
		done
done

# /run is walked depth-first with -xdev so image-owned files such as /run/dnf
# go while the build container's own mounts stay.
mkdir -p "${CLEAN_ROOT:?}/run"
find "${CLEAN_ROOT:?}/run" -xdev -mindepth 1 -depth -print0 2>/dev/null |
	while IFS= read -r -d '' entry; do
		mountpoint -q "${entry}" 2>/dev/null && continue
		if [[ -d "${entry}" ]]; then
			rmdir "${entry}" 2>/dev/null || true
			continue
		fi
		rm -f "${entry}"
	done
echo "::endgroup::"
