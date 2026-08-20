#!/usr/bin/bash
# iso/src/configure-live.sh — minimal live bake for purebuild
#
# Runs inside iso/Containerfile `live` stage as root during podman build.
# All state is baked, EROFS is read-only — no boot-time mutation.
# Keep this file generic and not desktop-specific: the base image's
# custom/ already defines the default session (neptuno: niri via
# user-templates, finpilot: GNOME). The live user just needs autologin;
# GDM will use the base's default session.

set -exo pipefail

# ── 1. liveuser (passwordless, /var/home) ─────────────────────────────────
if ! id liveuser &>/dev/null; then
    useradd --create-home --uid 1000 --user-group --comment "Live User" liveuser
fi
passwd --delete liveuser
mkdir -p /var/home/liveuser
chown 1000:1000 /var/home/liveuser

# ── 2. GDM autologin (live-only) ───────────────────────────────────────────
# Base custom already has FallbackSession + InitialSetupEnable=false, we
# just add the live autologin. Keep it minimal; don't touch Session.
mkdir -p /etc/gdm
# Preserve any existing custom.conf from base, just ensure autologin stanza
if [[ -f /etc/gdm/custom.conf ]] && grep -q "^\[daemon\]" /etc/gdm/custom.conf; then
    # Ensure AutomaticLogin lines exist (idempotent)
    if ! grep -q "^AutomaticLoginEnable" /etc/gdm/custom.conf; then
        echo "AutomaticLoginEnable=true" >>/etc/gdm/custom.conf
    else
        sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' /etc/gdm/custom.conf
    fi
    if ! grep -q "^AutomaticLogin=" /etc/gdm/custom.conf; then
        echo "AutomaticLogin=liveuser" >>/etc/gdm/custom.conf
    else
        sed -i 's/^AutomaticLogin=.*/AutomaticLogin=liveuser/' /etc/gdm/custom.conf
    fi
else
    cat >/etc/gdm/custom.conf <<'GDMCONF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=liveuser
GDMCONF
fi

# ── 3. Network + inhibit suspend ───────────────────────────────────────────
systemctl enable NetworkManager.service 2>/dev/null || true
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

# ── 4. /usr/local dangling symlink (Silverblue) ─────────────────────────────
if [[ -L /usr/local ]] && [[ ! -e /usr/local ]]; then
    target=$(readlink /usr/local)
    mkdir -p "/${target}"
    mkdir -p /var/usrlocal
elif [[ ! -e /usr/local ]]; then
    mkdir -p /usr/local
fi
mkdir -p /var/usrlocal

# ── 5. Break vmlinuz hardlink for purebuild ─────────────────────────────────
# Fedora ships vmlinuz as hardlink (nlink 2); oci.ApplyTar → TypeHardlink
# which purebuild's blob() rejects. Bake as regular file.
for kdir in /usr/lib/modules/*; do
    if [[ -f "${kdir}/vmlinuz" ]]; then
        cp -a --reflink=never "${kdir}/vmlinuz" "${kdir}/vmlinuz.tmp" 2>/dev/null || cp -a "${kdir}/vmlinuz" "${kdir}/vmlinuz.tmp"
        mv -f "${kdir}/vmlinuz.tmp" "${kdir}/vmlinuz"
        echo "Broke hardlink for ${kdir}/vmlinuz (now $(stat -c %h "${kdir}/vmlinuz") link)"
    fi
done

echo "Live bake complete."
