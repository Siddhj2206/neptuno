## vim: set ft=make :
# neptuno — release changelog lookup
#
# System defaults are restored by the shared `install-config` recipe in
# custom-system.just; this file deliberately does not duplicate it.

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
