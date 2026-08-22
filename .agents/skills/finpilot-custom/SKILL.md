---
name: finpilot-custom
description: >-
  Runtime layer of finpilot: Brewfiles, Flatpaks, and ujust commands — syntax,
  placement, and validation. Use when modifying custom/ or explaining the
  runtime layer to contributors.
---

# finpilot Runtime Layer

## When to Use

- Adding or editing Homebrew Brewfiles (`custom/brew/*.Brewfile`)
- Adding or editing Flatpak preinstall files (`custom/flatpaks/*.preinstall`)
- Adding or editing ujust command files (`custom/ujust/*.just`)
- Explaining the runtime vs build-time distinction to contributors
- Debugging why a Brewfile or Flatpak didn't install as expected

## When NOT to Use

- Build script changes — use `finpilot-build`
- CI workflow changes — use `finpilot-ci`
- Adding system packages at build-time — use `finpilot-packages`

## Core Process

1. **Identify the runtime need**: CLI tool, GUI app, or user convenience command
2. **Choose the right runtime file**: Brewfile (CLI), Flatpak (GUI), or ujust (shortcut)
3. **Apply correct syntax** for each file type
4. **Validate locally** before opening a PR

## Brewfiles: `custom/brew/*.Brewfile`

Brewfiles use Ruby syntax. In this repo they are **OS-managed preinstall declarations**, not user-opt-in installs: `build/steps/10-build.sh` copies every `custom/brew/*.Brewfile` into the image's `/usr/share/ublue-os/homebrew/preinstall.d/`, and the per-user `brew-preinstall.service` applies them at first login — installing additions, uninstalling removals, and never touching user-added packages. Homebrew itself is pre-staged at build time via the `@ublue-os/brew` OCI container.

### File Locations

| File                           | Purpose                                        |
| ------------------------------ | ---------------------------------------------- |
| `custom/brew/default.Brewfile` | OS-managed CLI tools installed for every user  |
| Custom `*.Brewfile`            | Additional OS-managed sets (all auto-installed) |

**Every `*.Brewfile` placed here is force-installed on every user account.** Do not put user-opt-in Brewfiles in this directory.

### Syntax

```ruby
# CLI tools
brew "bat"        # Better cat with syntax highlighting
brew "eza"        # Modern replacement for ls
brew "ripgrep"    # Faster grep
brew "fd"         # Simple alternative to find

# Taps (repositories)
tap "homebrew/cask"

# Casks
brew "node"
brew "python"
```

### How They Are Applied

No user action is required. The flow is declarative:

1. Edit `custom/brew/default.Brewfile`, add/remove `brew` lines
2. Build and deploy the image
3. On next login, `brew-preinstall.service` reconciles the user's Homebrew with the declared state (content-addressed: only runs on hash change)

Removing a package from a preinstall Brewfile *uninstalls* it from user systems. User-added packages are never affected.

### Validation

- **PR trigger**: `validate-brewfiles.yml` runs on PRs that touch `custom/brew/**`
- **Local check**: `brew bundle check --file /path/to/Brewfile`
- **List what would install**: `brew bundle list --file /path/to/Brewfile`

## Flatpaks: `custom/flatpaks/*.preinstall`

Flatpak preinstall files use INI format. They define GUI apps installed after first boot.

### File Locations

| File                                 | Purpose                                |
| ------------------------------------ | -------------------------------------- |
| `custom/flatpaks/default.preinstall` | Default GUI applications               |
| Custom `*.preinstall`                | Create as needed for specific app sets |

### Syntax

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable

[Flatpak Preinstall com.visualstudio.code]
Branch=stable

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
```

### Key Rules

- **Post-first-boot only**: Flatpaks are NOT baked into the ISO or container. They install on first boot with internet access — do not rely on them in offline scenarios or ISO-based installs without network.
- **Always specify `Branch=stable`** (or another valid branch)
- **Find app IDs at https://flathub.org/**
- **Validation**: `validate-flatpaks.yml` checks that app IDs exist on Flathub

## ujust: `custom/ujust/*.just`

ujust files define user convenience commands. All `.just` files are auto-consolidated during the build.

### Critical Rule: NEVER USE `dnf5` IN JUST FILES

ujust commands are shortcuts for user convenience — they should only invoke Brewfiles, Flatpaks, or other user-level tools. **Never use `dnf5` or any package manager in a just file.**

### Common Structure

```just
# vim: set ft=make :

[group('Apps')]
install-system-flatpaks:
    #!/usr/bin/env bash
    brew bundle --file /usr/share/ublue-os/homebrew/system-flatpaks.Brewfile

[group('Apps')]
bluefin-apps:
    #!/usr/bin/env bash
    brew bundle --file /usr/share/ublue-os/homebrew/system-dx-flatpaks.Brewfile

[group('System')]
my-custom-command:
    #!/usr/bin/env bash
    echo "Running custom command..."
    # Your logic here (NO dnf5!)
```

### Syntax Rules

- Use `#!/usr/bin/env bash` shebang for bash blocks
- Use `[group('Category')]` for organization in `ujust --list`
- All `.just` files are merged into `/usr/share/ublue-os/just/60-custom.just`
- Use descriptive, kebab-case command names

### Validation

- **PR trigger**: `validate-justfiles.yml` runs on PRs that touch `Justfile` or `custom/ujust/*.just`
- **Local check**: `just --list`
- **Syntax validation**: `just --unstable --fmt --check -f custom/ujust/your-file.just`

## Validation Workflows by File Type

| File Type      | Validation Workflow      | What It Checks              |
| -------------- | ------------------------ | --------------------------- |
| `*.Brewfile`   | `validate-brewfiles.yml` | Syntax, package existence   |
| `*.preinstall` | `validate-flatpaks.yml`  | App ID existence on Flathub |
| `*.just`       | `validate-justfiles.yml` | `just --list` syntax check  |

## Common Rationalizations

| Rationalization                                                             | Reality                                                                                               |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| "I'll add `dnf5 install` to a just file for convenience."                   | **Never.** ujust is for user-level shortcuts. Use `build/steps/10-build.sh` for system packages.            |
| "Flatpaks should be in the container so they work offline."                 | Flatpaks are intentionally post-first-boot to keep the container small and allow independent updates. |
| "I'll put the Brewfile inline in the just file instead of a separate file." | Separate Brewfiles are easier to validate and let users install them manually too.                    |
| "The just file doesn't need a shebang if it's just one command."            | Always use a shebang (`#!/usr/bin/env bash`) for explicit execution context.                          |

## Red Flags

- `dnf5` or `rpm-ostree` in any `.just` file
- Flatpak preinstall missing `Branch=stable`
- User-opt-in Brewfile placed in `custom/brew/` — everything there is force-installed on every user at first login
- App ID in `.preinstall` not verified on Flathub
- Just file using `dnf` or `yum` instead of proper Brewfile/Flatpak shortcuts

## Verification

- [ ] Is every `.Brewfile` under `custom/brew/` intended as OS-managed preinstall (auto-installed, declarative)?
- [ ] Do all Flatpak entries specify `Branch=stable`?
- [ ] Are all app IDs in `.preinstall` files verified on Flathub?
- [ ] Does `just --list` pass without errors?
- [ ] Does `brew bundle check --file` pass for each Brewfile?
- [ ] Is there NO `dnf5`, `dnf`, or `rpm-ostree` in any `.just` file?
