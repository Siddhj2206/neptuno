# vim: set ft=make :
####################
### custom-apps.just
####################

# neptuno-specific curated GUI installs that complement the shared Bluefin/common
# app helpers. Generic Brewfile selection and common app installers are already
# provided upstream, so this file only keeps shortcuts that are opinionated for
# this image.

# Install a small default GUI toolkit for managing an immutable desktop
[group('Apps')]
install-neptuno-core-flatpaks:
    #!/usr/bin/env bash
    set -euo pipefail
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub \
        com.github.tchx84.Flatseal \
        io.github.flattool.Warehouse \
        io.missioncenter.MissionCenter

# Alias for the neptuno default GUI app set
[group('Apps')]
neptuno-apps:
    @ujust install-neptuno-core-flatpaks

# Install all neptuno Homebrew bundles in one shot
[group('Apps')]
install-neptuno-brew:
    #!/usr/bin/env bash
    set -euo pipefail
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile
