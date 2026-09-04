#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eou pipefail

# Ported from projectbluefin/bluefin build_files/shared/validate-repos.sh.
# SECURITY: enabled third-party repos can inject malicious versions of Fedora
# packages. With isolated COPR installation (copr_install_isolated) NO COPR
# should be globally enabled at image completion.

REPOS_DIR="/etc/yum.repos.d"
VALIDATION_FAILED=0
ENABLED_REPOS=()

check_repo_file() {
    local repo_file="$1"
    local basename_file
    basename_file=$(basename "$repo_file")

    [[ -f "$repo_file" ]] || return 0
    [[ -r "$repo_file" ]] || return 0

    if grep -q "^enabled=1" "$repo_file" 2>/dev/null; then
        echo "ENABLED: $basename_file"
        ENABLED_REPOS+=("$basename_file")
        VALIDATION_FAILED=1

        echo "   Enabled sections:"
        local section_name=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[.*\]$ ]]; then
                section_name="$line"
            elif [[ "$line" =~ ^enabled=1 ]]; then
                echo "     - $section_name"
            fi
        done < "$repo_file"
    else
        echo "Disabled: $basename_file"
    fi
}

echo ""
echo "Checking COPR repositories (standard naming)..."
for repo in "$REPOS_DIR"/_copr:copr.fedorainfracloud.org:*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo ""
echo "Checking COPR repositories (non-standard naming)..."
for repo in "$REPOS_DIR"/_copr_*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo ""
echo "Checking other third-party repositories..."
OTHER_REPOS=(
    "negativo17-fedora-multimedia.repo"
    "tailscale.repo"
    "docker-ce.repo"
)

for repo_name in "${OTHER_REPOS[@]}"; do
    repo_path="$REPOS_DIR/$repo_name"
    [[ -f "$repo_path" ]] && check_repo_file "$repo_path"
done

echo ""
echo "Checking RPM Fusion repositories..."
for repo in "$REPOS_DIR"/rpmfusion-*.repo; do
    [[ -f "$repo" ]] && check_repo_file "$repo"
done

echo ""
echo "Checking Fedora updates-testing (should always be disabled)..."
[[ -f "$REPOS_DIR/fedora-updates-testing.repo" ]] && check_repo_file "$REPOS_DIR/fedora-updates-testing.repo"

echo ""
echo "======================================"
if [[ $VALIDATION_FAILED -eq 1 ]]; then
    echo "VALIDATION FAILED"
    echo "======================================"
    echo ""
    echo "The following repositories are still ENABLED:"
    for repo in "${ENABLED_REPOS[@]}"; do
        echo "  - $repo"
    done
    exit 1
fi

echo "::endgroup::"
