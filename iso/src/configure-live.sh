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

# ── 3. Bootc-installer (if flatpak present) — hybrid live+install ──────────
# Only runs if install-flatpaks.sh installed org.bootcinstaller.Installer.
# Static files live as real files under live-files/ for linting (not heredocs).
INSTALLER_APP_ID="org.bootcinstaller.Installer"
if [[ "${INSTALLER_CHANNEL:-stable}" == "dev" ]]; then
    INSTALLER_APP_ID="org.bootcinstaller.Installer.Devel"
fi
if [[ -d "/var/lib/flatpak/app/${INSTALLER_APP_ID}" ]]; then
    echo ">>> Configuring bootc-installer (hybrid)..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIVE_FILES="${SCRIPT_DIR}/live-files"
    # Copy static live-files (polkit, autostart, sudoers, storage) for linting
    install -Dm644 "${LIVE_FILES}/etc/polkit-1/rules.d/99-live-installer.rules" /etc/polkit-1/rules.d/99-live-installer.rules
    install -Dm644 "${LIVE_FILES}/etc/xdg/autostart/tuna-installer.desktop" /etc/xdg/autostart/tuna-installer.desktop
    install -Dm644 "${LIVE_FILES}/etc/sudoers.d/liveuser" /etc/sudoers.d/liveuser
    chmod 0440 /etc/sudoers.d/liveuser
    install -Dm644 "${LIVE_FILES}/etc/containers/storage.conf" /etc/containers/storage.conf
    # Fisherman symlink
    INSTALLER_BIN=$(find /var/lib/flatpak/app/${INSTALLER_APP_ID} -name fisherman -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
    if [[ -n "${INSTALLER_BIN}" ]]; then
        mkdir -p /usr/local/bin
        ln -sf "${INSTALLER_BIN}/fisherman" /usr/local/bin/fisherman
    fi
    # Installer config from single recipe.json in iso/ (generic, no neptuno.conf)
    if [[ -f /tmp/recipe.json ]]; then
        IMGREF="${IMGREF:-localhost/neptuno:stable}"
        # Allow override via env (for finpilot port, set IMGREF)
        if [[ -f /tmp/src/live.conf ]] 2>/dev/null; then
            # shellcheck source=/dev/null
            source /tmp/src/live.conf 2>/dev/null || true
        fi
        mkdir -p /etc/bootc-installer
        # Minimal images.json/recipe.json for online install (no offline store)
        python3 - <<PYEOF
import json
imgref = "$IMGREF"
with open("/tmp/recipe.json") as f:
    recipe = json.load(f)
recipe["image"] = imgref
recipe["local_imgref"] = "containers-storage:" + imgref
recipe["targetImgref"] = imgref
recipe["imgref"] = imgref
with open("/etc/bootc-installer/recipe.json", "w") as f:
    json.dump(recipe, f, indent=2)
    f.write("\n")
images = {"default_image": imgref, "images": [{"name": "Neptuno", "imgref": imgref, "desc": "Neptuno — niri-based", "bootloader": "grub2", "filesystem": "btrfs", "composefs": False, "needs_user_creation": True, "flatpak_var_path": "var/lib/flatpak", "filesystems": ["btrfs", "xfs"]}], "fallback_flatpaks": []}
with open("/etc/bootc-installer/images.json", "w") as f:
    json.dump(images, f, indent=2)
    f.write("\n")
PYEOF
        touch /etc/bootc-installer/live-iso-mode
        echo ">>> Bootc-installer configured for ${IMGREF}"
    fi
fi

echo "Live bake complete."
