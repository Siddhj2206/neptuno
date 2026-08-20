#!/usr/bin/bash
# iso/src/configure-live.sh — minimal agnostic live bake for purebuild
#
# Runs inside iso/Containerfile `live` stage as root during podman build.
# Keep this file highly agnostic: no hard-coded DM (GDM/SDDM/greetd),
# no hard-coded WM (niri/gnome/kde). The base image's custom/ already
# defines the default session (neptuno: niri via user-templates, finpilot:
# GNOME), and purebuild's EnsureLiveUser/EnsureAutologin (tacklebox
# purefs) handles the live user + display-manager autologin generically
# for whatever DM the base ships. This bake only fixes image quirks that
# purebuild can't: Fedora's vmlinuz hardlink and Silverblue's dangling
# /usr/local symlink. All other live state is baked by purebuild.

set -exo pipefail

# ── 1. /usr/local dangling symlink (Silverblue) ─────────────────────────────
# Silverblue ships /usr/local → var/usrlocal which doesn't exist in the
# container build; recreate so tooling writing to /usr/local doesn't fail.
if [[ -L /usr/local ]] && [[ ! -e /usr/local ]]; then
    target=$(readlink /usr/local)
    mkdir -p "/${target}"
    mkdir -p /var/usrlocal
elif [[ ! -e /usr/local ]]; then
    mkdir -p /usr/local
fi
mkdir -p /var/usrlocal

# ── 2. Break vmlinuz hardlink for purebuild ─────────────────────────────────
# Fedora ships vmlinuz as hardlink (nlink 2); oci.ApplyTar → TypeHardlink
# which purebuild's blob(".../vmlinuz") rejects (expects TypeFile).
for kdir in /usr/lib/modules/*; do
    if [[ -f "${kdir}/vmlinuz" ]]; then
        cp -a --reflink=never "${kdir}/vmlinuz" "${kdir}/vmlinuz.tmp" 2>/dev/null || cp -a "${kdir}/vmlinuz" "${kdir}/vmlinuz.tmp"
        mv -f "${kdir}/vmlinuz.tmp" "${kdir}/vmlinuz"
        echo "Broke hardlink for ${kdir}/vmlinuz (now $(stat -c %h "${kdir}/vmlinuz") link)"
    fi
done

echo "Live bake complete."
