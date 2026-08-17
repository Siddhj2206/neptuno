#!/usr/bin/bash
# Live-environment setup for the Neptuno ISO installer image.
#
# Runs inside the final stage of iso/Containerfile with:
#   --cap-add sys_admin --security-opt label=disable
#
# The payload image already ships a dmsquash-live initramfs (60-initramfs.sh),
# so this script only handles the runtime live environment: liveuser, GDM
# autologin into niri, bootc-installer configuration + autostart, polkit, and
# the containers-storage layout for the embedded offline store.
#
# All static live-env files live as real files under live-files/ (mirroring
# their target paths) and are copied into place below — nothing is written
# inline, so every file can be linted and inspected in the repo. Config is
# sourced from /tmp/src/neptuno.conf; DEBUG and INSTALLER_CHANNEL arrive via
# ENV from Containerfile build-args.

set -exo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_FILES="${SCRIPT_DIR}/live-files"

# ── Config (single source of truth) ───────────────────────────────────────────
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/neptuno.conf"

# ── Live user ─────────────────────────────────────────────────────────────────
# Fedora Silverblue has /home → /var/home, so useradd --create-home lands in
# /var/home/liveuser, which dmsquash-live keeps writable via the overlay.
useradd --create-home --uid 1000 --user-group \
    --comment "Live User" liveuser || true
passwd --delete liveuser

# Debug builds only: known passwords + SSH so the live session is reachable
# for testing. Never enabled in production ISOs.
if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "liveuser:live" | chpasswd
    passwd --unlock root
    echo "root:root" | chpasswd
fi

# ── Static live-env files ─────────────────────────────────────────────────────
# Copy every file under live-files/ to its mirrored target path. The two
# installer desktop entries are templated (@INSTALLER_APP_ID@ — the app ID
# differs between stable and dev channels).
INSTALLER_APP_ID="org.bootcinstaller.Installer"
[[ "${INSTALLER_CHANNEL:-stable}" == "dev" ]] && INSTALLER_APP_ID="org.bootcinstaller.Installer.Devel"

install -Dm644 "${LIVE_FILES}/etc/gdm/custom.conf" /etc/gdm/custom.conf
install -Dm644 "${LIVE_FILES}/var/lib/AccountsService/users/liveuser" /var/lib/AccountsService/users/liveuser
install -Dm644 "${LIVE_FILES}/etc/sudoers.d/liveuser" /etc/sudoers.d/liveuser
install -Dm644 "${LIVE_FILES}/etc/containers/storage.conf" /etc/containers/storage.conf
install -Dm644 "${LIVE_FILES}/etc/containers/mounts.conf" /etc/containers/mounts.conf
install -Dm644 "${LIVE_FILES}/etc/polkit-1/rules.d/99-live-installer.rules" /etc/polkit-1/rules.d/99-live-installer.rules
install -Dm644 "${LIVE_FILES}/usr/share/polkit-1/actions/org.bootcinstaller.Installer.policy" /usr/share/polkit-1/actions/org.bootcinstaller.Installer.policy
install -Dm644 "${LIVE_FILES}/usr/lib/systemd/system/var-tmp.mount" /usr/lib/systemd/system/var-tmp.mount
install -Dm644 "${LIVE_FILES}/usr/lib/systemd/system/live-run-expand.service" /usr/lib/systemd/system/live-run-expand.service
install -Dm644 "${LIVE_FILES}/usr/lib/systemd/system/live-ready.service" /usr/lib/systemd/system/live-ready.service
install -Dm644 "${LIVE_FILES}/usr/lib/systemd/system/bluefin-remove-installer.service.d/live-skip.conf" /usr/lib/systemd/system/bluefin-remove-installer.service.d/live-skip.conf
install -Dm644 "${LIVE_FILES}/usr/lib/tmpfiles.d/live-hostname.conf" /usr/lib/tmpfiles.d/live-hostname.conf

# Installer desktop entry (override) + XDG autostart, templated per channel
sed "s/@INSTALLER_APP_ID@/${INSTALLER_APP_ID}/g" \
    "${LIVE_FILES}/usr/share/applications/bootc-installer.desktop" > "/usr/share/applications/${INSTALLER_APP_ID}.desktop"
sed "s/@INSTALLER_APP_ID@/${INSTALLER_APP_ID}/g" \
    "${LIVE_FILES}/etc/xdg/autostart/tuna-installer.desktop" > /etc/xdg/autostart/tuna-installer.desktop

# Debug-only files
if [[ "${DEBUG:-0}" == "1" ]]; then
    install -Dm644 "${LIVE_FILES}/etc/systemd/system-preset/90-live-debug.preset" /etc/systemd/system-preset/90-live-debug.preset
    install -Dm644 "${LIVE_FILES}/etc/ssh/sshd_config.d/90-live-debug.conf" /etc/ssh/sshd_config.d/90-live-debug.conf
    install -Dm644 "${LIVE_FILES}/etc/firewalld/zones/public.xml" /etc/firewalld/zones/public.xml
    install -Dm644 "${LIVE_FILES}/usr/lib/systemd/system/debug-ssh-banner.service" /usr/lib/systemd/system/debug-ssh-banner.service
    # The Fedora preset marks sshd disabled; a systemd preset file takes
    # priority over /usr/lib and forces it on.
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/sshd.service \
        /etc/systemd/system/multi-user.target.wants/sshd.service
    systemctl enable debug-ssh-banner.service
fi

# ── Systemd enablement / masking ─────────────────────────────────────────────
systemctl enable var-tmp.mount || true
systemctl enable live-run-expand.service || true
systemctl enable live-ready.service || true

# Mask systemd sleep/suspend targets so the kernel never suspends regardless
# of what any userspace tool requests — belt-and-suspenders for the install.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

# fisherman (bootc-installer backend) creates /var/fisherman-tmp and
# bind-mounts it to /var/tmp. Pre-create the directory so it exists at boot.
mkdir -p /var/fisherman-tmp

# ── Polkit fisherman symlink ─────────────────────────────────────────────────
# installer calls /usr/local/bin/fisherman via pkexec. Resolve the /usr/local
# symlink if dangling (Fedora Silverblue: /usr/local -> /var/usrlocal).
INSTALLER_APP_DIR=$(find /var/lib/flatpak/app/${INSTALLER_APP_ID} -name fisherman -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
if [ -n "$INSTALLER_APP_DIR" ]; then
    USR_LOCAL_BIN=/usr/local/bin
    if [[ -L /usr/local ]] && [[ ! -d /usr/local ]]; then
        USR_LOCAL_BIN="$(readlink /usr/local)/bin"
        mkdir -p "$USR_LOCAL_BIN"
    else
        mkdir -p /usr/local/bin
    fi
    ln -sf "${INSTALLER_APP_DIR}/fisherman" "${USR_LOCAL_BIN}/fisherman"
fi

# ── Installer configuration (images.json + recipe.json) ──────────────────────
# Generated from iso/neptuno.conf — the single source of truth. recipe.json
# branding/tour/steps come from the static template in etc/bootc-installer/.
mkdir -p /etc/bootc-installer
python3 - << PYEOF
import json

os_name = "$OS_NAME"
os_desc = "$OS_DESC"
imgref = "$IMGREF"
bootloader = "$BOOTLOADER"
composefs = "$COMPOSEFS" == "true"
needs_user_creation = "$NEEDS_USER_CREATION" == "true"
flatpak_var_path = "$FLATPAK_VAR_PATH"

# ── images.json: the installer's image catalog ───────────────────────────
images = {
    "default_image": imgref,
    "fallback_flatpaks": [],
    "images": [
        {
            "name": os_name,
            "imgref": imgref,
            "desc": os_desc,
            "icon": "resource:///org/bootcinstaller/Installer/images/bluefin.png",
            "bootloader": bootloader,
            "filesystem": "btrfs",
            "composefs": composefs,
            "needs_user_creation": needs_user_creation,
            "flatpak_var_path": flatpak_var_path,
            "filesystems": ["btrfs", "xfs"],
        }
    ],
}
with open("/etc/bootc-installer/images.json", "w") as f:
    json.dump(images, f, indent=2)
    f.write("\n")

# ── recipe.json: branding/tour from template, imgrefs from config ─────────
with open("$SCRIPT_DIR/etc/bootc-installer/recipe.json") as f:
    recipe = json.load(f)

recipe["distro_name"] = os_name
recipe["welcome_title"] = "Welcome to " + os_name
# image = source for fisherman/bootc install. For non-composefs (bootcDirect)
# the empty image triggers a native bootc install with
# --source-imgref containers-storage:... into the payload embedded at
# /usr/lib/containers/storage.
recipe["image"] = ""
recipe["local_imgref"] = "containers-storage:" + imgref
recipe["targetImgref"] = imgref
recipe["imgref"] = imgref
recipe["filesystem"] = "btrfs"
recipe["bootloader"] = bootloader
recipe["composeFsBackend"] = composefs

with open("/etc/bootc-installer/recipe.json", "w") as f:
    json.dump(recipe, f, indent=2)
    f.write("\n")
PYEOF

# Flag file read by the installer to activate live ISO mode even when running
# inside a Flatpak sandbox.
touch /etc/bootc-installer/live-iso-mode

echo "Live environment configuration complete."
