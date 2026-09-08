#!/usr/bin/bash

set -euo pipefail

###############################################################################
# DX Layer — host-level dev tooling (docker-ce daemon, adb, libvirt/qemu).
# User-level CLIs stay in the Brewfile; virt-manager is a flatpak.
# Manifest of record: build/packages/dx.toml (fedora + docker sections).
#
# Daemons are socket-activated — nothing runs at boot until first use.
#
# Group membership (docker/libvirt) is automatic: the ublue setup hooks
# (user-setup.hooks.d/30-groups.sh -> privileged-setup.hooks.d/10-groups.sh)
# enroll every human user at login (bluefin devmode pattern).
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

PKGS_TOML=/ctx/build/packages/dx.toml

echo "::group:: Install DX Fedora Packages"

install_fedora_section "${PKGS_TOML}" "dx fedora packages"

echo "::endgroup::"

echo "::group:: Install Docker (docker-ce stable repo)"

# docker is not in Fedora — enable the official repo, install, then remove
# it (updates ride image rebuilds; negativo17 multimedia is the one repo
# that intentionally stays).
cat >/etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

readarray -t DOCKER_PKGS < <("${READ_PKGS}" "${PKGS_TOML}" docker)
dnf5 install -y --enablerepo=docker-ce-stable "${DOCKER_PKGS[@]}"
rm -f /etc/yum.repos.d/docker-ce.repo
# Origin assert, not just presence: the four Docker-built packages carry
# RPM VENDOR "Docker"; containerd.io has an empty vendor but a
# docker-repo-unique NAME (proof recorded in dx.toml). The --enablerepo pin
# above keeps the install scoped.
VENDOR_PKGS=()
for p in "${DOCKER_PKGS[@]}"; do
	[[ "${p}" == "containerd.io" ]] || VENDOR_PKGS+=("${p}")
done
assert_vendor "docker packages" "Docker" "${VENDOR_PKGS[@]}"
assert_packages_present "docker packages" "${DOCKER_PKGS[@]}"

echo "::endgroup::"

echo "::group:: Enable Socket-Activated Daemons"

# Socket-activated (no daemons at boot). libvirtd.socket is gone since the
# F34 modular split; this set is host-proven (virsh qemu:///system works):
# virtqemud + virtnetworkd (default NAT) + virtnodedevd + virtstoraged +
# virtsecretd + virtproxyd (legacy-socket compat, via libvirt-daemon-qemu's
# Requires chain incl. libvirt-daemon-proxy — no extra packages).
systemctl enable docker.socket
systemctl enable virtqemud.socket virtnetworkd.socket virtnodedevd.socket virtstoraged.socket virtsecretd.socket virtproxyd.socket

echo "::endgroup::"

echo "DX layer complete!"
