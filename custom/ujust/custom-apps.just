# vim: set ft=make :
####################
### custom-apps.just
####################
## Homebrew shortcuts.
##
## Every Brewfile in custom/brew/ is copied to
## /usr/share/ublue-os/homebrew/preinstall.d/ and installed on first login. The
## recipe below is a manual re-run; it is not part of first-boot setup.
##
## See custom/brew/README.md.

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/preinstall.d/default.Brewfile
