# vim: set ft=make :

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile

# Install development tools via Homebrew
[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing development tools via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile

# Install fonts via Homebrew
[group('Apps')]
install-fonts:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing fonts via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile
