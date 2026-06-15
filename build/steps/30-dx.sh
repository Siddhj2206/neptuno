#!/usr/bin/bash

set -eoux pipefail

echo "::group:: Install Docker CE"

# Add Docker CE repo
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

# Pin Docker CE repo to avoid pull from other repos
dnf5 config-manager setopt docker-ce-stable.priority=90

# Install Docker CE
dnf5 install -y \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin \
	podman-compose

# Disable Docker CE repo after install (packages baked into image)
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/docker-ce.repo

echo "::endgroup::"

echo "::group:: Install Virtualization Stack"

dnf5 install -y \
	edk2-ovmf \
	genisoimage \
	libvirt \
	libvirt-nss \
	qemu \
	qemu-char-spice \
	qemu-device-display-virtio-gpu \
	qemu-device-display-virtio-vga \
	qemu-device-usb-redirect \
	qemu-img \
	qemu-system-x86-core \
	qemu-user-binfmt \
	qemu-user-static \
	virt-manager \
	virt-viewer \
	virt-v2v

echo "::endgroup::"

echo "::group:: Install Performance & Tracing Tools"

dnf5 install -y \
	bcc \
	bpftop \
	bpftrace \
	sysprof \
	trace-cmd \
	iotop \
	nicstat \
	numactl \
	tiptop

echo "::endgroup::"

echo "::group:: Install Development Utilities"

dnf5 install -y \
	android-tools \
	cascadia-code-fonts \
	flatpak-builder \
	git-subtree \
	git-svn \
	osbuild-selinux \
	p7zip \
	p7zip-plugins \
	udica \
	wtype \
	ydotool

echo "::endgroup::"

echo "::group:: Copy DX System Files"

# Copy specific DX system files from projectbluefin/common
mkdir -p /usr/lib/sysctl.d/
cp /ctx/oci/common/dx/usr/lib/sysctl.d/docker-ce.conf /usr/lib/sysctl.d/ 2>/dev/null || true

mkdir -p /usr/lib/dracut/dracut.conf.d/
cp /ctx/oci/common/dx/usr/lib/dracut/dracut.conf.d/80-vfio.conf /usr/lib/dracut/dracut.conf.d/ 2>/dev/null || true

mkdir -p /usr/lib/tmpfiles.d/
cp /ctx/oci/common/dx/usr/lib/tmpfiles.d/libvirt-workaround.conf /usr/lib/tmpfiles.d/ 2>/dev/null || true

mkdir -p /usr/lib/systemd/system/
cp /ctx/oci/common/dx/usr/lib/systemd/system/libvirt-workaround.service /usr/lib/systemd/system/ 2>/dev/null || true
cp /ctx/oci/common/dx/usr/lib/systemd/system/bluefin-dx-groups.service /usr/lib/systemd/system/ 2>/dev/null || true

mkdir -p /usr/bin/
cp /ctx/oci/common/dx/usr/bin/bluefin-dx-groups /usr/bin/ 2>/dev/null || true
chmod +x /usr/bin/bluefin-dx-groups 2>/dev/null || true

# Apply docker IP forwarding sysctl
sysctl -p /usr/lib/sysctl.d/docker-ce.conf 2>/dev/null || true

# Create ip_tables module for docker-in-docker
mkdir -p /etc/modules-load.d/
echo "iptable_nat" > /etc/modules-load.d/ip_tables.conf

echo "::endgroup::"

echo "::group:: Enable DX System Services"

systemctl enable docker.socket
systemctl enable libvirt-workaround.service
systemctl enable bluefin-dx-groups.service

echo "::endgroup::"

echo "DX configuration complete!"
