# vim: set ft=make :
#######################
### custom-system.just
#######################
## Example system configuration commands
## These are simplified examples adapted from Bluefin

# Run a system benchmark (requires stress-ng from Homebrew)
[group('System')]
benchmark:
    #!/usr/bin/env bash
    source /usr/lib/ujust/ujust.sh
    if ! type -P "stress-ng" &>/dev/null ; then
        echo "stress-ng is not installed."
        if command -v brew &>/dev/null; then
            if gum confirm "Install stress-ng via Homebrew?" ; then
                brew install stress-ng
                brew link stress-ng
            else
                exit 0
            fi
        else
            echo "Please install stress-ng to run benchmarks."
            exit 1
        fi
    fi
    echo 'Running a 1 minute benchmark...'
    pushd $(mktemp -d) > /dev/null
    stress-ng --matrix 0 -t 1m --times
    popd > /dev/null

# Configure docker and libvirt groups for development
[group('System')]
configure-dev-groups:
    #!/usr/bin/pkexec bash
    CURRENT_USER="{{ `id -un` }}"
    echo "Adding $CURRENT_USER to docker and libvirt groups..."

    # Ensure groups exist in /etc/group
    for group in docker libvirt; do
        if ! grep -q "^$group:" /etc/group; then
            echo "Adding $group to /etc/group"
            grep "^$group:" /usr/lib/group | tee -a /etc/group > /dev/null
        fi
        usermod -aG $group $CURRENT_USER
    done

    echo "Groups configured. Log out and back in for changes to take effect."

# Example toggle command with user choice
[group('System')]
toggle-example-feature:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "This is an example toggle command."
    echo "Current status: [check your status here]"
    OPTION=$(Choose "Enable" "Disable" "Cancel")
    case "$OPTION" in
        "Enable")
            echo "Enabling feature..."
            # Add your enable logic here
            ;;
        "Disable")
            echo "Disabling feature..."
            # Add your disable logic here
            ;;
        "Cancel")
            echo "No changes made."
            ;;
    esac

# Clean up container images and volumes
[group('Maintenance')]
clean-containers:
    #!/usr/bin/bash
    echo "Cleaning up Podman containers, images, and volumes..."
    podman system prune -af
    podman volume prune -f
    echo "Cleanup complete!"

# Update system and reboot if needed
[group('Maintenance')]
update-and-reboot:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "Updating system..."
    sudo bootc upgrade
    if gum confirm "Reboot now to apply updates?"; then
        systemctl reboot
    else
        echo "Reboot later to apply updates."
    fi

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

    # Find all files in skel config
       CONFLICTS=()
       while IFS= read -r -d '' file; do
           rel_path="${file#$SKEL_CONFIG/}"
           target="$USER_CONFIG/$rel_path"
           if [[ -f "$target" ]]; then
               CONFLICTS+=("$rel_path")
           fi
       done < <(find "$SKEL_CONFIG" -type f -print0)

       if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
           echo "⚠ The following files will be backed up:"
           for f in "${CONFLICTS[@]}"; do
               echo "  - $f"
           done
           echo ""
       fi

       if ! gum confirm "Proceed with installation?"; then
           echo "Cancelled."
           exit 0
       fi

       # Copy files, backing up conflicts
           BACKED_UP=()
           INSTALLED=()

           while IFS= read -r -d '' file; do
               rel_path="${file#$SKEL_CONFIG/}"
               target="$USER_CONFIG/$rel_path"
               target_dir=$(dirname "$target")

               # Create directory if needed
               mkdir -p "$target_dir"

               # Backup existing file
               if [[ -f "$target" ]]; then
                   backup="${target}.backup.${TIMESTAMP}"
                   mv "$target" "$backup"
                   BACKED_UP+=("$rel_path → $(basename "$backup")")
               fi

               # Copy new file
               cp "$file" "$target"
               INSTALLED+=("$rel_path")
           done < <(find "$SKEL_CONFIG" -type f -print0)

           echo ""
              echo "${bold}=== Installation Complete ===${normal}"
              echo ""
              echo "✓ Installed ${#INSTALLED[@]} files"

              if [[ ${#BACKED_UP[@]} -gt 0 ]]; then
                  echo ""
                  echo "📦 Backups created:"
                  for b in "${BACKED_UP[@]}"; do
                      echo "  $b"
                  done
              fi

              echo ""
              echo "Run 'systemctl --user enable --now dms' to start DMS
