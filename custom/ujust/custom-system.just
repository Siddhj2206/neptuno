# vim: set ft=make :

# Alias for bluefin-cli (terminal bling toggle)
[group('System')]
neptuno-cli:
    @ujust bluefin-cli

# Deploy DMS configuration files from system defaults
[group('System')]
install-dms-config:
    #!/usr/bin/bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh

    SKEL_CONFIG="/etc/skel/.config"
    USER_CONFIG="${HOME}/.config"
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

    if [[ ! -d "$SKEL_CONFIG" ]]; then
        echo "Error: $SKEL_CONFIG not found"
        exit 1
    fi

    echo "${bold}DMS Configuration Installer${normal}"
    echo "This will install DMS configs for niri and ghostty."
    echo ""

    CONFLICTS=()
    while IFS= read -r -d '' file; do
        rel_path="${file#$SKEL_CONFIG/}"
        target="$USER_CONFIG/$rel_path"
        if [[ -f "$target" ]]; then
            CONFLICTS+=("$rel_path")
        fi
    done < <(find "$SKEL_CONFIG" -type f -print0)

    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        echo "The following files will be backed up:"
        for f in "${CONFLICTS[@]}"; do
            echo "  - $f"
        done
        echo ""
    fi

    if ! gum confirm "Proceed with installation?"; then
        echo "Cancelled."
        exit 0
    fi

    BACKED_UP=()
    INSTALLED=()

    while IFS= read -r -d '' file; do
        rel_path="${file#$SKEL_CONFIG/}"
        target="$USER_CONFIG/$rel_path"
        target_dir=$(dirname "$target")

        mkdir -p "$target_dir"

        if [[ -f "$target" ]]; then
            backup="${target}.backup.${TIMESTAMP}"
            mv "$target" "$backup"
            BACKED_UP+=("$rel_path")
        fi

        cp "$file" "$target"
        INSTALLED+=("$rel_path")
    done < <(find "$SKEL_CONFIG" -type f -print0)

    echo ""
    echo "${bold}=== Installation Complete ===${normal}"
    echo ""
    echo "Installed ${#INSTALLED[@]} files"

    if [[ ${#BACKED_UP[@]} -gt 0 ]]; then
        echo ""
        echo "Backups created:"
        for b in "${BACKED_UP[@]}"; do
            echo "  $b"
        done
    fi

    echo ""
    echo "Run 'systemctl --user enable --now dms' to start DMS"

# Install ASUS Linux control stack (asusctl + ROG Control Center)
# Installs via Homebrew from ublue-os/tap — requires kernel >= 6.19
[group('System')]
install-asus:
    #!/usr/bin/env bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh

    # Ensure Homebrew is available
    if ! command -v brew &>/dev/null; then
        if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        else
            echo "Homebrew is not installed. Run 'ujust setup-brew' first."
            exit 1
        fi
    fi

    echo "${bold}ASUS Linux Control Stack Installer${normal}"
    echo ""
    echo "This installs asusctl and ROG Control Center from ublue-os/tap."
    echo "Requires kernel 6.19 or later for full hardware support."
    echo ""

    if ! gum confirm "Proceed with ASUS tools installation?"; then
        echo "Cancelled."
        exit 0
    fi

    echo ""
    echo "Step 1: Installing system daemon (asusctl-linux)..."
    echo ""
    brew tap ublue-os/tap
    brew install --cask ublue-os/tap/asusctl-linux

    echo ""
    echo "Step 2: Enabling system services..."
    echo ""
    sudo systemctl enable --now asusd.service asus-shutdown.service
    sudo udevadm control --reload && sudo udevadm trigger

    echo ""
    echo "Step 3: Installing GUI and user daemon (ROG Control Center)..."
    echo ""
    brew install --cask ublue-os/tap/rog-control-center-linux

    echo ""
    echo "Step 4: Enabling user services..."
    echo ""
    systemctl --user daemon-reload
    systemctl --user enable --now asusd-user.service

    echo ""
    echo "${green}ASUS tools installed successfully!${normal}"
    echo "ROG Control Center will appear in your system tray."
    echo "You can manage fan curves, RGB, power profiles, battery limits, and GPU modes."
