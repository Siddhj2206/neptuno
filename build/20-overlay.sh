#!/usr/bin/env bash
# Filesystem overlay: system_files/, the Flathub descriptor and the Flatpak
# preinstall list. Installs nothing and enables nothing (40-services.sh does).
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
