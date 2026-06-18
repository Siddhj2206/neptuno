---
name: finpilot-examples
description: >-
  Runnable examples and activation patterns for the finpilot template.
  Covers third-party repo integration, COPR packages, desktop environment
  changes, and custom ujust commands.
  Use when looking for worked examples of common customization patterns.
metadata:
  context7-sources: []
---

# finpilot Examples

## When to Use

- Looking for a worked example of a customization pattern
- Adding a third-party RPM repository
- Creating a new step script
- Adding a ujust command

## When NOT to Use

- General package decisions — see `finpilot-packages.md`
- CI or workflow changes — see `finpilot-ci.md`

## Activation Pattern

This template uses the **example → rename → activate** pattern for build scripts:

1. Scripts ending in `.example` are ignored by the build
2. To activate: remove the `.example` suffix (rename `20-*.sh.example` → `20-*.sh`)
3. New scripts must be registered in `build/build.sh`

## Existing Examples in This Fork

### Third-Party Repo Pattern

The `build/steps/` directory contains step scripts that follow this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Add repo
cat > /etc/yum.repos.d/some-repo.repo << 'EOF'
[some-repo]
name=Some Repo
baseurl=https://example.com/rpm
enabled=1
gpgcheck=1
gpgkey=https://example.com/gpg.key
EOF

# Install
dnf5 install -y some-package

# Clean up (required!)
rm -f /etc/yum.repos.d/some-repo.repo
```

### COPR Pattern

All COPR packages use the isolated install pattern:

```bash
source /ctx/build/copr-helpers.sh

# Install from COPR (auto-disables after install)
copr_install_isolated "owner/repo" package-name

# Install multiple packages
copr_install_isolated "owner/repo" pkg1 pkg2 pkg3
```

### Desktop Environment Change

The pattern for replacing or adding a desktop environment:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Remove old desktop
dnf5 remove -y gnome-shell gnome-desktop

# Install new desktop via COPR
source /ctx/build/copr-helpers.sh
copr_install_isolated "owner/repo" new-desktop-packages

# Configure display manager
systemctl enable display-manager
```

## Creating a New Example

1. Create `build/steps/NN-description.sh` with `set -euo pipefail`
2. Add the script call to `build/build.sh` in the correct position
3. Run `shellcheck build/steps/NN-description.sh`
4. Test with `just build`

## Common Patterns

| Pattern | Location | Method |
|---|---|---|
| Install system package | `build/steps/10-build.sh` | `dnf5 install -y` |
| Install from COPR | `build/steps/20-*.sh` | `copr_install_isolated` |
| Add third-party repo | `build/steps/20-*.sh` | Create repo file → install → remove |
| Enable systemd service | `build/steps/10-build.sh` | `systemctl enable` |
| Replace desktop | `build/steps/30-*.sh` | Remove old → install new |
| Copy custom configs | `build/steps/10-build.sh` | `cp -r /ctx/custom/config/* ...` |
| Add brew package | `custom/brew/default.Brewfile` | `brew "package"` |
| Add flatpak app | `custom/flatpaks/default.preinstall` | `[Flatpak Preinstall org.app.ID]` |
| Add ujust command | `custom/ujust/*.just` | `[group('...')] recipe-name:` |
