#!/usr/bin/env bash
# Apply Neptuno's default user configs (/etc/skel) to this user's home.
#
# /etc/skel only applies at account creation — a rebaser never sees it. This
# hook is the login-time equivalent: ONE-TIME per
# user per version (top-gated like common's 10-theming.sh), conflicts backed
# up with a timestamp (same semantics as the `install-dms-config` ujust
# recipe). To deliberately re-apply for all users later, bump the version.
#
# Manual re-run for a single user:
#   jq 'del(.version.user."neptuno-skel")' ~/.local/share/ublue/setup_versioning.json \
#     | sponge ~/.local/share/ublue/setup_versioning.json   # then next login
# (or keep using `ujust install-dms-config`)

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

set -euo pipefail

# Top gate — the framework idiom: once recorded for this user+version, every
# later login exits right here. Config is never touched again.
version-script neptuno-skel user 1 || exit 0

SKEL_CONFIG="${SKEL_CONFIG:-/etc/skel/.config}"
USER_CONFIG="${USER_CONFIG:-${HOME}/.config}"

[[ -d "${SKEL_CONFIG}" ]] || exit 0

TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
COPIED=0
BACKED_UP=0

while IFS= read -r -d '' file; do
    rel_path="${file#"${SKEL_CONFIG}"/}"
    target="${USER_CONFIG}/${rel_path}"
    mkdir -p "$(dirname "${target}")"

    if [[ -e "${target}" ]] || [[ -L "${target}" ]]; then
        backup="${target}.backup.${TIMESTAMP}"
        n=1
        while [[ -e "${backup}" ]] || [[ -L "${backup}" ]]; do
            backup="${target}.backup.${TIMESTAMP}.$((n++))"
        done
        mv "${target}" "${backup}"
        BACKED_UP=$((BACKED_UP + 1))
    fi

    cp "${file}" "${target}"
    COPIED=$((COPIED + 1))
done < <(find "${SKEL_CONFIG}" -type f -print0)

echo "neptuno-skel: applied ${COPIED} files (${BACKED_UP} backed up)"
