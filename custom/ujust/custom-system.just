# vim: set ft=make :
# neptuno — DMS helpers

# Restore Niri, Ghostty, and DMS configs from system defaults (skel) to this
# user's home. Existing files are backed up with a timestamp before replacement.
# This is intentionally the only way to apply these defaults to an existing
# user; image updates and logins never overwrite user configuration.
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

# Add the invoking user to the Docker and libvirt groups.
# Group membership is never changed automatically; log out and back in afterward.
[group('System')]
add-dev-groups:
    #!/usr/bin/env bash
    set -euo pipefail

    USER_NAME="$(id -un)"
    REQUIRED_GROUPS=(docker libvirt)
    MISSING_GROUPS=()

    for group in "${REQUIRED_GROUPS[@]}"; do
        if ! getent group "${group}" >/dev/null; then
            echo "Error: required group '${group}' does not exist"
            exit 1
        fi

        if ! id -nG "${USER_NAME}" | grep -qw "${group}"; then
            MISSING_GROUPS+=("${group}")
        fi
    done

    if [[ ${#MISSING_GROUPS[@]} -eq 0 ]]; then
        echo "${USER_NAME} already has Docker and libvirt access."
        exit 0
    fi

    if command -v gum >/dev/null 2>&1; then
        if ! gum confirm "Add ${USER_NAME} to: ${MISSING_GROUPS[*]}?"; then
            echo "Cancelled."
            exit 0
        fi
    fi

    GROUP_LIST="$(IFS=,; echo "${MISSING_GROUPS[*]}")"
    sudo usermod --append --groups "${GROUP_LIST}" "${USER_NAME}"
    echo "Added ${USER_NAME} to: ${MISSING_GROUPS[*]}"
    echo "Log out and back in before using Docker or libvirt without sudo."

# Show release changelogs for the running image (bctl first, else GitHub).
# Neptuno release changelog lookup.
changelogs:
    #!/usr/bin/bash
    set -euo pipefail
    if command -v bctl &>/dev/null; then
        exec bctl changelogs
    fi

    IMAGE_INFO_FILE="${IMAGE_INFO_FILE:-/usr/share/ublue-os/image-info.json}"
    TAG="$(jq -r '.["image-tag"]' < "${IMAGE_INFO_FILE}")"
    REPO="siddhj2206/neptuno"
    # Pager is optional (brew-runtime may be absent); curl/jq are required.
    if command -v glow >/dev/null 2>&1; then PAGER="glow -p"; else PAGER="cat"; fi
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 1; }

    DATE="$(grep -oP "OSTREE_VERSION=.*\d{2}\.\K\d{8}[.0-9]*" /etc/os-release 2>/dev/null || true)"
    CONTENT=""
    if [[ "$TAG" =~ gts$|stable$|^lts ]] && [[ -n "${DATE:-}" ]]; then
        CONTENT="$(curl -Ls "https://api.github.com/repos/${REPO}/releases" | jq -r ".[] | select(.tag_name==\"${TAG}-${DATE}\") | .body")"
    fi

    if [[ -n "${CONTENT:-}" ]]; then
        echo "$CONTENT" | $PAGER
    else
        echo "WARN: Could not find a release specific to your image"
        curl -Ls "https://api.github.com/repos/${REPO}/releases/latest" | jq -r ".body" | $PAGER
    fi
