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

