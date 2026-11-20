#!/usr/bin/env bash
# Filesystem overlay: system_files/, nx, the Flathub descriptor and the
# Flatpak preinstall list. Installs nothing and enables nothing (40-services.sh does).
set -euo pipefail

echo "::group:: Overlay system files"
# shared/ is everything a second image could reuse; desktop/ is niri, DMS and
# greeter wiring. desktop/ lands last, so it wins on a shared path.
rsync -rlK /ctx/system_files/shared/ /
rsync -rlK /ctx/system_files/desktop/ /
echo "::endgroup::"

echo "::group:: sudoers drop-ins"
# rsync does not carry modes; sudo wants these root-owned and not writable.
chmod 0440 /etc/sudoers.d/neptuno-*
for f in /etc/sudoers.d/neptuno-*; do visudo -cf "${f}"; done
echo "::endgroup::"

echo "::group:: Nix settings"
# Fedora's /etc/nix/nix.conf belongs to nix-core; include ours from it rather
# than replacing it. The daemon and every client read the same file.
nix_include='!include /usr/share/neptuno/nix/nix.conf'
grep -qxF "${nix_include}" /etc/nix/nix.conf || printf '\n%s\n' "${nix_include}" >>/etc/nix/nix.conf
nix config show download-buffer-size | grep -qx 67108864
echo "::endgroup::"

echo "::group:: nx"
# nx 1.0, from github.com/Siddhj2206/nx (doc/product.md 7.1): Fedora RPMs live
# on /usr (the host tier) and sealed nixpkgs tools beside it. It links the
# image's libsolv and librpm, so a release has one tarball per Fedora release
# and architecture: the tree to unpack at / (nx, nxd, units and presets,
# sysusers, tmpfiles, polkit, PATH snippets, completions, man pages). Its
# units are enabled by base.toml like every other. Renovate bumps the version
# but can't recompute a hash, so the tarball is checked against the
# SHA256SUMS published with the same release.
# renovate: datasource=github-releases depName=Siddhj2206/nx
NX_VERSION=v1.0.1
# shellcheck source=/dev/null
nx_fedora="$(. /etc/os-release && echo "${VERSION_ID}")"
nx_tgz="nx-${NX_VERSION}-fc${nx_fedora}-$(uname -m).tar.gz"
nx_tmp="$(mktemp -d)"
nx_base="https://github.com/Siddhj2206/nx/releases/download/${NX_VERSION}"
curl --fail --location --retry 3 --silent --show-error \
	--output "${nx_tmp}/${nx_tgz}" "${nx_base}/${nx_tgz}" \
	--output "${nx_tmp}/SHA256SUMS" "${nx_base}/SHA256SUMS"
(cd "${nx_tmp}" && grep -F "  ${nx_tgz}" SHA256SUMS | sha256sum --check --strict)
# --no-overwrite-dir: /usr, /etc and the rest keep their own modes and times.
tar -xzf "${nx_tmp}/${nx_tgz}" -C / --no-same-owner --no-overwrite-dir
rm -rf "${nx_tmp}"
[ "$(/usr/bin/nx --version)" = "nx ${NX_VERSION#v}" ]
echo "::endgroup::"

echo "::group:: Default login shell"
# fish for every account useradd creates, including Anaconda's user screen.
sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd
grep -qx 'SHELL=/usr/bin/fish' /etc/default/useradd
echo "::endgroup::"

echo "::group:: Flatpak preinstall list"
install -Dm0644 /ctx/flatpaks/default.preinstall /usr/share/flatpak/preinstall.d/neptuno.preinstall
echo "::endgroup::"

echo "::group:: Flathub remote descriptor"
# flatpak imports /etc/flatpak/remotes.d into the system installation the first
# time it is opened. Never `flatpak remote-add` at build time: that writes to
# /var, which 90-cleanup.sh empties. The descriptor is the trust root for every
# Flatpak (it carries GPGKey=), so it is pinned by hash; tests/fixtures holds
# the same file.
FLATHUB_REPO_SHA256=3371dd250e61d9e1633630073fefda153cd4426f72f4afa0c3373ae2e8fea03a
flathub_tmp="$(mktemp)"
curl --fail --retry 3 --silent --show-error --output "${flathub_tmp}" \
	https://dl.flathub.org/repo/flathub.flatpakrepo
echo "${FLATHUB_REPO_SHA256}  ${flathub_tmp}" | sha256sum --check --strict
install -Dm0644 "${flathub_tmp}" /etc/flatpak/remotes.d/flathub.flatpakrepo
rm -f "${flathub_tmp}"
echo "::endgroup::"
