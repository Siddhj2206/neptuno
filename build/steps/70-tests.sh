#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# In-image smoke tests, adapted from projectbluefin/bluefin 20-tests.sh.
# Runs at the very end of the image build so a silently-dropped package,
# codec swap, or missed unit enable fails the build instead of shipping.

# ujust + just consolidation target (all custom recipes append into it)
stat /usr/bin/ujust
stat /usr/share/ublue-os/just/00-entry.just
stat /usr/share/ublue-os/just/60-custom.just

# The brew-preinstall delivery path: everything below is inherited from the
# pinned `common`/`brew` images whose digests Renovate bumps automatically,
# so a rename or drop upstream would otherwise stop shipping with no signal.
test -f /usr/share/ublue-os/homebrew/preinstall.d/default.Brewfile
test -f /usr/share/ublue-os/homebrew/preinstall.d/chairlift.Brewfile
test -f /usr/share/ublue-os/homebrew/preinstall.d/bluefinctl.Brewfile
test -f /usr/share/ublue-os/homebrew/preinstall.d/system-cli.Brewfile
test -x /usr/bin/brew-preinstall
test -f /usr/lib/systemd/user/brew-preinstall.service
grep -q '^enable brew-preinstall\.service$' /usr/lib/systemd/user-preset/01-brew-preinstall.preset

# If this file is not on the image bazaar will be removed from users' systems :(
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall

# Make sure this garbage never makes it to an image
test ! -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service

IMPORTANT_PACKAGES=(
    distrobox
    dracut-live
    fish
    flatpak
    fzf
    gum
    fastfetch
    gnome-keyring
    mutter
    gdm
    niri
    quickshell-git
    docker-ce
    libvirt
    qemu-system-x86
    squashfs-tools
    systemd
    tailscale
    uupd
    zsh
)

for package in "${IMPORTANT_PACKAGES[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1; }
done

# these should be sourced from negativo's fedora-multimedia repo
# as Fedora can't ship patent encumbered video codecs
# (only directly-installed packages are asserted — transitive deps excluded
# so a codec-swap upstream can't false-fail the build)
NEGATIVO=(
    ffmpeg
    ffmpeg-libs
    libavcodec
)

for package in "${NEGATIVO[@]}"; do
    rpm -q --qf "%{NAME} %{VENDOR}" "${package}" | grep -q "negativo17\.org" || { echo "${package} not from negativo... Exiting"; exit 1; }
done

# these packages are supposed to be removed and are considered footguns
UNWANTED_PACKAGES=(
    fedora-bookmarks
    fedora-third-party
    firefox
    gnome-software
    gnome-software-rpm-ostree
    podman-docker
    ptyxis
)

for package in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        echo "Unwanted package found: ${package}... Exiting"; exit 1
    fi
done

IMPORTANT_UNITS=(
    podman.socket
    brew-setup.service
    brew-update.timer
    brew-upgrade.timer
    flatpak-appstream-refresh.service
    rechunker-group-fix.service
    flatpak-nuke-fedora.service
    flatpak-preinstall.service
    ublue-system-setup.service
    input-remapper.service
    tailscaled.service
    uupd.timer
    dconf-update.service
)

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
