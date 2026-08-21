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
# Keep it agnostic: no hard-coded WM, just generic polkit + autostart.
INSTALLER_APP_ID="org.bootcinstaller.Installer"
if [[ "${INSTALLER_CHANNEL:-stable}" == "dev" ]]; then
    INSTALLER_APP_ID="org.bootcinstaller.Installer.Devel"
fi
if [[ -d "/var/lib/flatpak/app/${INSTALLER_APP_ID}" ]]; then
    echo ">>> Configuring bootc-installer (hybrid)..."
    # Polkit: allow liveuser to run installer without password
    mkdir -p /etc/polkit-1/rules.d
    cat >/etc/polkit-1/rules.d/99-live-installer.rules <<'POLKIT'
polkit.addRule(function(action, subject) {
    if (action.id == "org.bootcinstaller.Installer" && subject.isInGroup("liveuser")) {
        return polkit.Result.YES;
    }
});
POLKIT
    # Autostart installer in live session (generic, no WM hard-code)
    mkdir -p /etc/xdg/autostart
    cat >/etc/xdg/autostart/tuna-installer.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Install Neptuno
Exec=flatpak run ${INSTALLER_APP_ID}
OnlyShowIn=GNOME;KDE;X-NIRI;
AutostartCondition=GSettings org.gnome.desktop.session session-name != 'neptuno'
DESKTOP
    # Sudoers for liveuser (installer needs it)
    echo "liveuser ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/liveuser
    chmod 0440 /etc/sudoers.d/liveuser
    # Storage for installer (offline container storage)
    mkdir -p /etc/containers
    cat >/etc/containers/storage.conf <<'STORAGE'
[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"
[storage.options]
additionalimagestores = ["/usr/lib/containers/storage"]
[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
STORAGE
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
