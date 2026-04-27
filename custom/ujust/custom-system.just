# vim: set ft=make :
#######################
### custom-system.just
#######################

# Manage neptuno's DMS and Niri configuration defaults.

[group('System')]
install-dms-config:
    #!/usr/bin/env bash
    set -euo pipefail

    source /usr/lib/ujust/ujust.sh

    SYSTEM_CONFIG_DIR="/etc/skel/.config"
    USER_CONFIG_DIR="${HOME}/.config"
    TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"

    REQUIRED_FILES=(
        "niri/config.kdl"
        "ghostty/config"
        "environment.d/90-dms.conf"
    )

    if [[ ! -d "${SYSTEM_CONFIG_DIR}" ]]; then
        echo "System config directory not found: ${SYSTEM_CONFIG_DIR}"
        exit 1
    fi

    echo "${bold}neptuno DMS Config Installer${normal}"
    echo
    echo "This will copy the neptuno default DMS-related config into:"
    echo "  ${USER_CONFIG_DIR}"
    echo
    echo "Existing files with matching paths will be backed up first."
    echo "Your personal Niri overrides should go in:"
    echo "  ${USER_CONFIG_DIR}/niri/local.kdl"
    echo

    MISSING=()
    for rel_path in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "${SYSTEM_CONFIG_DIR}/${rel_path}" ]]; then
            MISSING+=("${rel_path}")
        fi
    done

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo "The system defaults are incomplete. Missing files:"
        for path in "${MISSING[@]}"; do
            echo "  - ${path}"
        done
        exit 1
    fi

    CONFLICTS=()
    while IFS= read -r -d '' file; do
        rel_path="${file#${SYSTEM_CONFIG_DIR}/}"
        target="${USER_CONFIG_DIR}/${rel_path}"
        if [[ -f "${target}" ]]; then
            CONFLICTS+=("${rel_path}")
        fi
    done < <(find "${SYSTEM_CONFIG_DIR}" -type f -print0)

    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        echo "The following files will be backed up:"
        for file in "${CONFLICTS[@]}"; do
            echo "  - ${file}"
        done
        echo
    fi

    if ! gum confirm "Install neptuno DMS config into your home directory?"; then
        echo "Cancelled."
        exit 0
    fi

    BACKED_UP=()
    INSTALLED=()

    while IFS= read -r -d '' file; do
        rel_path="${file#${SYSTEM_CONFIG_DIR}/}"
        target="${USER_CONFIG_DIR}/${rel_path}"
        target_dir="$(dirname "${target}")"

        mkdir -p "${target_dir}"

        if [[ -f "${target}" ]]; then
            backup="${target}.backup.${TIMESTAMP}"
            mv "${target}" "${backup}"
            BACKED_UP+=("${rel_path} -> $(basename "${backup}")")
        fi

        cp "${file}" "${target}"
        INSTALLED+=("${rel_path}")
    done < <(find "${SYSTEM_CONFIG_DIR}" -type f -print0)

    LOCAL_NIRI="${USER_CONFIG_DIR}/niri/local.kdl"
    if [[ ! -f "${LOCAL_NIRI}" ]]; then
        cat > "${LOCAL_NIRI}" <<'EOF'
// Put your personal Niri overrides here.
// This file is included from config.kdl and is intended to survive
// refreshes of the default neptuno DMS configuration.

// Example:
//
// input {
//     keyboard {
//         xkb {
//             layout "us"
//         }
//     }
// }
EOF
        INSTALLED+=("niri/local.kdl")
    fi

    echo
    echo "${bold}Installation complete${normal}"
    echo
    echo "Installed ${#INSTALLED[@]} files."
    if [[ ${#BACKED_UP[@]} -gt 0 ]]; then
        echo
        echo "Backups created:"
        for item in "${BACKED_UP[@]}"; do
            echo "  - ${item}"
        done
    fi
    echo
    echo "Log out and select the Niri session if needed."
    echo "Put personal Niri overrides in:"
    echo "  ${LOCAL_NIRI}"

[group('System')]
refresh-dms-config:
    #!/usr/bin/env bash
    set -euo pipefail

    source /usr/lib/ujust/ujust.sh

    USER_CONFIG_DIR="${HOME}/.config"
    LOCAL_NIRI="${USER_CONFIG_DIR}/niri/local.kdl"

    echo "${bold}Refresh neptuno DMS Config${normal}"
    echo
    echo "This will reinstall the default neptuno DMS config and back up"
    echo "any existing user config files before replacing them."
    echo
    echo "Your personal overrides should live in:"
    echo "  ${LOCAL_NIRI}"
    echo

    if [[ -f "${LOCAL_NIRI}" ]]; then
        echo "Detected existing local override file:"
        echo "  ${LOCAL_NIRI}"
    else
        echo "No local override file found yet. One will be created for you."
    fi
    echo

    if ! gum confirm "Continue refreshing your DMS config?"; then
        echo "Cancelled."
        exit 0
    fi

    ujust install-dms-config

[group('System')]
show-dms-config-paths:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "System defaults:"
    echo "  /etc/skel/.config/niri/config.kdl"
    echo "  /etc/skel/.config/ghostty/config"
    echo "  /etc/skel/.config/environment.d/90-dms.conf"
    echo
    echo "User-installed config:"
    echo "  ${HOME}/.config/niri/config.kdl"
    echo "  ${HOME}/.config/ghostty/config"
    echo "  ${HOME}/.config/environment.d/90-dms.conf"
    echo
    echo "User override file:"
    echo "  ${HOME}/.config/niri/local.kdl"

[group('System')]
dms-doctor:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v dms >/dev/null 2>&1; then
        echo "dms is not installed or not in PATH."
        exit 1
    fi

    echo "Running DMS doctor in verbose mode..."
    echo
    exec dms doctor -v

[group('System')]
dms-check:
    #!/usr/bin/env bash
    set -euo pipefail

    USER_CONFIG_DIR="${HOME}/.config"
    REQUIRED_USER_FILES=(
        "${USER_CONFIG_DIR}/niri/config.kdl"
        "${USER_CONFIG_DIR}/niri/local.kdl"
        "${USER_CONFIG_DIR}/ghostty/config"
        "${USER_CONFIG_DIR}/environment.d/90-dms.conf"
    )

    echo "Checking neptuno DMS prerequisites..."
    echo

    for path in "${REQUIRED_USER_FILES[@]}"; do
        if [[ -f "${path}" ]]; then
            echo "[ok] ${path}"
        else
            echo "[missing] ${path}"
        fi
    done

    echo
    echo "If files are missing, run:"
    echo "  ujust install-dms-config"
    echo
    echo "For runtime health checks, run:"
    echo "  ujust dms-doctor"
