# Neptuno offline installer (embedded payload)
# Builds an Anaconda installer image FROM Neptuno, embeds anaconda stack.
# Used for:
#   - BIB  bootc-installer  ( --type bootc-installer --bootc-installer-payload-ref )
#   - image-builder bootc-generic-iso (preferred, with iso.yaml + kickstart)
#
# NOTE: no Justfile recipes wrap this yet — build manually, e.g.:
#   podman build -f iso/installer.Containerfile -t localhost/neptuno-installer:stable .
#
ARG BASE_IMAGE=localhost/neptuno:stable
FROM ${BASE_IMAGE}

# Anaconda stack (tries both env-deps names across releases; dnf5 only).
RUN set -eux; \
    command -v dnf5 >/dev/null 2>&1 || { echo "dnf5 required" >&2; exit 1; }; \
    dnf5 install -y \
        anaconda \
        anaconda-dracut \
        dracut-config-generic \
        dracut-network \
        net-tools \
        grub2-efi-x64-cdboot \
        grub2-efi-x64 \
        shim-x64 \
        plymouth; \
    dnf5 install -y anaconda-install-env-deps || dnf5 install -y anaconda-install-img-deps; \
    dnf5 install -y lorax-templates-generic; \
    # NOTE: xorrisofs is not a separate F44 package — provided by xorriso.
    dnf5 install -y xorriso; \
    dnf5 install -y squashfs-tools isomd5sum mtools dosfstools; \
    dnf5 install -y podman python3; \
    dnf5 install -y biosdevname prefixdevname; \
    # Fedora 42+ needs /boot/efi pre-populated for image-builder contract
    if [ -d /usr/lib/efi ]; then mkdir -p /boot/efi && cp -ra /usr/lib/efi/*/*/EFI /boot/efi/; fi; \
    mkdir -p /var/mnt; \
    dnf5 clean all

# Tools required by bootc-generic-iso contract in the (build) container.
# If you use a separate --bootc-build-ref, these can live there instead.
RUN dnf5 install -y grub2-tools grub2-pc-modules; \
    dnf5 clean all

# Minimal lorax runtime-postinstall emulation — required for Anaconda to boot.
RUN set -eux; \
    echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >> /etc/passwd; \
    echo "install::14438:0:99999:7:::" >> /etc/shadow; \
    passwd -d root; \
    if [ -f /usr/share/anaconda/list-harddrives-stub ]; then mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives; fi; \
    if [ -d /etc/yum.repos.d ] && [ ! -d /etc/anaconda.repos.d ]; then mv /etc/yum.repos.d /etc/anaconda.repos.d; fi; \
    if [ -f /lib/systemd/system/anaconda.target ]; then ln -sf /lib/systemd/system/anaconda.target /etc/systemd/system/default.target; fi; \
    rm -vf /usr/lib/systemd/system-generators/systemd-gpt-auto-generator; \
    if [ -f /usr/lib/systemd/system/anaconda-shell@.service ]; then \
        rm -f /usr/lib/systemd/system/autovt@.service; \
        ln -s /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service; \
    fi; \
    mkdir -p /usr/lib/systemd/logind.conf.d; \
    printf '[Login]\nReserveVT=2\n' > /usr/lib/systemd/logind.conf.d/anaconda-shell.conf; \
    mkdir -p /etc/systemd/user/pipewire.service.d /etc/systemd/user/pipewire.socket.d; \
    printf '[Unit]\nConditionUser=\n' > /etc/systemd/user/pipewire.service.d/allowroot.conf; \
    printf '[Unit]\nConditionUser=\n' > /etc/systemd/user/pipewire.socket.d/allowroot.conf; \
    # Ensure /root symlink target exists for dracut
    mkdir -p "$(realpath /root 2>/dev/null || echo /var/roothome)"; \
    if command -v kernel-install >/dev/null 2>&1 && command -v dracut >/dev/null 2>&1; then \
        kver=$(kernel-install list --json pretty 2>/dev/null | jq -r '.[] | select(.has_kernel == true) | .version' 2>/dev/null | head -n1); \
        if [ -n "${kver:-}" ] && [ -f "/usr/lib/modules/${kver}/vmlinuz" ]; then \
            DRACUT_NO_XATTR=1 dracut --force -v --zstd --reproducible --no-hostonly --add "anaconda" "/usr/lib/modules/${kver}/initramfs.img" "${kver}"; \
        fi; \
    fi

# ISO metadata for bootc-generic-iso (context is repo root).
COPY iso/iso.yaml /usr/lib/image-builder/bootc/iso.yaml
COPY iso/iso.yaml /usr/lib/bootc-image-builder/iso.yaml

# Kickstart default (registry pull; embedded builds override at build time).
COPY iso/interactive-defaults.ks /usr/share/anaconda/interactive-defaults.ks

RUN bootc container lint --fatal-warnings
