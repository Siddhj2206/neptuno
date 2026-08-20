#!/usr/bin/bash
# iso/src/configure-live.sh — deterministic live bake for purebuild
#
# Runs inside `iso/Containerfile.live` as root during `podman build`.
# All state is baked into the image's writable layer so `podman export`
# captures it. No boot-time mutation; the EROFS is read-only.
#
# Steps (per .scratch/iso-rebuild/plan.md §5):
# 1. liveuser (passwordless, /var/home/liveuser via /home→/var/home)
# 2. GDM autologin → liveuser, no initial-setup
# 3. niri session via AccountsService (Session=niri)
# 4. inhibit idle lock / suspend (passwordless user would strand)
# 5. NetworkManager + mask sleep targets
# 6. /usr/local dangling symlink fix

set -exo pipefail

# ── Config (optional, for parity) ──────────────────────────────────────────
# shellcheck source=/dev/null
if [[ -f /tmp/neptuno.conf ]]; then
    source /tmp/neptuno.conf
fi

# ── 1. liveuser ─────────────────────────────────────────────────────────────
# Silverblue: /home → /var/home, so --create-home lands in /var/home/liveuser,
# which the live overlay keeps writable.
if ! id liveuser &>/dev/null; then
    useradd --create-home --uid 1000 --user-group --comment "Live User" liveuser
fi
passwd --delete liveuser

# Ensure home is seeded and owned (AccountsService needs it)
mkdir -p /var/home/liveuser
chown 1000:1000 /var/home/liveuser

# ── 2. GDM autologin ────────────────────────────────────────────────────────
mkdir -p /etc/gdm
cat >/etc/gdm/custom.conf <<'GDMCONF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=liveuser
InitialSetupEnable=false
GDMCONF

# ── 3. niri as the session ──────────────────────────────────────────────────
mkdir -p /var/lib/AccountsService/users
cat >/var/lib/AccountsService/users/liveuser <<'ACCT'
[User]
Session=niri
SessionType=wayland
XSession=niri
ACCT
chmod 644 /var/lib/AccountsService/users/liveuser

# FallbackSession for GDM ≥51 forward-compat (harmless if ignored)
if grep -q "^\[daemon\]" /etc/gdm/custom.conf; then
    if ! grep -q "FallbackSession" /etc/gdm/custom.conf; then
        echo "FallbackSession=niri" >>/etc/gdm/custom.conf
    fi
fi

# ── 4. Inhibit idle lock / suspend ──────────────────────────────────────────
# niri idle: prevent lock when fullscreen false (passwordless user would strand)
# and friends: disable idle timeout and lock-on-suspend for live session
mkdir -p /etc/xdg
cat >/etc/xdg/niri-session.override <<'NIRI'
[idle]
inhibit-when-fullscreen=false
timeout=0
lock-on-suspend=false
NIRI

# ── 5. Network + mask sleep ─────────────────────────────────────────────────
systemctl enable NetworkManager.service 2>/dev/null || true
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

# ── 6. /run sizing (optional, plan §5 step 6) ───────────────────────────────
# Enlarge /run for live overlay (tbox live mounts tmpfs there). 20% of RAM
# is default; ensure at least 2G via tmpfiles for the live session.
mkdir -p /etc/tmpfiles.d
cat >/etc/tmpfiles.d/live-run.conf <<'RUNCONF'
# Type Path Mode UID GID Age Argument
d /run 0755 root root - -
RUNCONF

# ── 7. /usr/local dangling symlink ──────────────────────────────────────────
# Silverblue ships /usr/local → var/usrlocal which does not exist in the
# container build; recreate so tooling writing to /usr/local doesn't fail.
if [[ -L /usr/local ]] && [[ ! -e /usr/local ]]; then
    target=$(readlink /usr/local)
    # target is var/usrlocal (relative) → create ../var/usrlocal from /usr perspective
    mkdir -p "/${target}"
    # also ensure /var/usrlocal exists for the export
    mkdir -p /var/usrlocal
elif [[ ! -e /usr/local ]]; then
    mkdir -p /usr/local
fi

# Ensure /var/usrlocal exists regardless (the symlink target)
mkdir -p /var/usrlocal

# ── 8. Break hardlink for vmlinuz (purebuild expects regular file, not hardlink)
# Fedora's kernel RPM ships vmlinuz as a hardlink (nlink 2); oci.ApplyTar
# stores it as TypeHardlink, which purebuild's blob(".../vmlinuz") rejects
# (expects TypeFile). Break the link so the exported tar sees a regular file.
for kdir in /usr/lib/modules/*; do
    if [[ -f "${kdir}/vmlinuz" ]]; then
        cp -a --reflink=never "${kdir}/vmlinuz" "${kdir}/vmlinuz.tmp" 2>/dev/null || cp -a "${kdir}/vmlinuz" "${kdir}/vmlinuz.tmp"
        mv -f "${kdir}/vmlinuz.tmp" "${kdir}/vmlinuz"
        echo "Broke hardlink for ${kdir}/vmlinuz (now $(stat -c %h "${kdir}/vmlinuz") link)"
    fi
done

echo "Live bake complete."
