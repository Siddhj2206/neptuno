# vim: set ft=make :
# Skill: finpilot-custom.md — ujust rule reference

# Alias for bluefin-cli (terminal bling toggle)
[group('System')]
neptuno-cli:
    @ujust bluefin-cli

# Restore DMS config files from system defaults (backup-first)
[group('System')]
install-dms-config:
    #!/usr/bin/bash
    set -euo pipefail

    SKEL_CONFIG="${SKEL_CONFIG:-/etc/skel/.config}"
    USER_CONFIG="${USER_CONFIG:-${HOME}/.config}"
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

    bold="$(tput bold 2>/dev/null || printf '\033[1m')"
    normal="$(tput sgr0 2>/dev/null || printf '\033[0m')"

    if [[ ! -d "$SKEL_CONFIG" ]]; then
        echo "Error: $SKEL_CONFIG not found"
        exit 1
    fi

    echo "${bold}DMS Config Restore${normal}"
    echo "Restores DMS configs from system defaults to your home."
    echo "Existing files are backed up before being replaced."
    echo ""

    CONFLICTS=()
    while IFS= read -r -d '' file; do
        rel_path="${file#$SKEL_CONFIG/}"
        target="$USER_CONFIG/$rel_path"
        if [[ -e "$target" || -L "$target" ]]; then
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

    if command -v gum >/dev/null 2>&1; then
        if ! gum confirm "Proceed with restore?"; then
            echo "Cancelled."
            exit 0
        fi
    else
        echo "gum not found — proceeding without confirmation."
    fi

    BACKED_UP=()
    INSTALLED=()

    while IFS= read -r -d '' file; do
        rel_path="${file#$SKEL_CONFIG/}"
        target="$USER_CONFIG/$rel_path"
        target_dir=$(dirname "$target")

        if ! mkdir -p "$target_dir" 2>/dev/null; then
            echo "  WARN: cannot create $target_dir — skipping $rel_path"
            continue
        fi

        if [[ -e "$target" || -L "$target" ]]; then
            backup="${target}.backup.${TIMESTAMP}"
            n=1
            while [[ -e "$backup" || -L "$backup" ]]; do
                backup="${target}.backup.${TIMESTAMP}.$((n++))"
            done
            mv "$target" "$backup"
            BACKED_UP+=("$rel_path")
        fi

        cp "$file" "$target"
        INSTALLED+=("$rel_path")
    done < <(find "$SKEL_CONFIG" -type f -print0)

    echo ""
    echo "${bold}=== Restore Complete ===${normal}"
    echo ""
    echo "Restored ${#INSTALLED[@]} files"

    if [[ ${#BACKED_UP[@]} -gt 0 ]]; then
        echo ""
        echo "Backups created:"
        for b in "${BACKED_UP[@]}"; do
            echo "  $b"
        done
    fi

    echo ""
    echo "Run 'systemctl --user enable --now dms' to start DMS"

# Show the neptuno changelog (overrides common's bluefin-pointing recipe)
# Loaded via 60-custom.just AFTER changelog.just, so this definition wins
[group('System')]
changelogs:
    #!/usr/bin/bash
    set -euo pipefail
    if command -v bctl &>/dev/null; then
        exec bctl changelogs
    fi

    IMAGE_INFO_FILE="${IMAGE_INFO_FILE:-/usr/share/ublue-os/image-info.json}"
    TAG="$(jq -r '.["image-tag"]' < "${IMAGE_INFO_FILE}")"
    REPO="siddhj2206/neptuno"

    DATE="$(grep -oP "OSTREE_VERSION=.*\d{2}\.\K\d{8}[.0-9]*" /etc/os-release 2>/dev/null || true)"
    CONTENT=""
    if [[ "$TAG" =~ gts$|stable$|^lts ]] && [[ -n "${DATE:-}" ]]; then
        CONTENT="$(curl -Ls "https://api.github.com/repos/${REPO}/releases" | jq -r ".[] | select(.tag_name==\"${TAG}-${DATE}\") | .body")"
    fi

    if [[ -n "${CONTENT:-}" ]]; then
        echo "$CONTENT" | glow -p
    else
        echo "WARN: Could not find a release specific to your image"
        curl -Ls "https://api.github.com/repos/${REPO}/releases/latest" | jq -r ".body" | glow -p
    fi
