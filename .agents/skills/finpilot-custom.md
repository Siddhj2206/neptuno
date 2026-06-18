---
name: finpilot-custom
description: >-
  Runtime customizations: Homebrew Brewfiles (Ruby syntax),
  Flatpak preinstall files (INI format), ujust commands,
  and custom config/files directories.
  Use when changing custom/ or adding runtime user features.
metadata:
  context7-sources: []
---

# finpilot Custom

## When to Use

- Adding or editing Homebrew Brewfiles
- Adding or editing Flatpak preinstall files
- Adding or editing ujust commands
- Adding user config files in `custom/config/` or `custom/files/`

## When NOT to Use

- Build-time packages or scripts — see `finpilot-packages.md` or `finpilot-build.md`
- CI or workflow changes — see `finpilot-ci.md`

## Core Process

1. **Identify the runtime layer** (Brewfile, Flatpak, ujust, or config file)
2. **Follow the format rules** for that layer (Ruby, INI, just, or plain files)
3. **Validate** before committing (Brewfile syntax, Flatpak IDs, just syntax)
4. **Document new ujust recipes** with `[group('Category')]` headers

## Brewfiles (Homebrew)

**Location**: `custom/brew/*.Brewfile`
**Syntax**: Ruby
**Purpose**: CLI tools, fonts, and development environments installed by users at runtime

```ruby
# custom/brew/default.Brewfile
brew "bat"
brew "eza"
brew "ripgrep"

tap "homebrew/cask"
cask "font-fira-code-nerd-font"
```

**Rules:**
- Use `brew "package"` for formulae
- Use `cask "package"` for casks (GUI apps)
- Use `tap "owner/repo"` for third-party taps
- Validate with `brew bundle check --file custom/brew/default.Brewfile`

## Flatpak Preinstall

**Location**: `custom/flatpaks/*.preinstall`
**Syntax**: INI
**Purpose**: GUI applications installed on first boot

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable
```

**Rules:**
- Section header: `[Flatpak Preinstall APP_ID]`
- Always specify `Branch=stable` (or another branch)
- Optional: `IsRuntime=true`, `CollectionID=org.flathub.Stable`
- **Always validate** the app ID exists on Flathub before adding
- Run `flatpak search APP_ID` to confirm availability

## ujust Commands

**Location**: `custom/ujust/*.just`
**Syntax**: Justfile format
**Purpose**: User convenience commands (shortcuts for Brewfile installs, system tasks)

```just
# vim: set ft=make :

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
```

**RULES:**
- **NEVER** use `dnf5` in ujust — only Brewfile/Flatpak shortcuts
- Use `[group('Category')]` for organization (e.g., `Apps`, `System`)
- All `.just` files in `custom/ujust/` are auto-consolidated at build time
- Use `#!/usr/bin/bash` or `#!/usr/bin/env bash` shebangs
- Validate with `just --unstable --fmt --check -f custom/ujust/<file>.just`

## Custom Config and Files

**Location**: `custom/config/` and `custom/files/`
**Purpose**: User-specific configuration and system file overrides

These directories are copied to the image at build time and are available for:
- Shell configuration (`custom/config/environment.d/`)
- Terminal emulator configs (`custom/config/ghostty/`)
- Window manager configs (`custom/config/niri/`)
- System file overrides (`custom/files/etc/`, `custom/files/usr/`)

These are baked into the image at `/usr/share/ublue-os/` or similar locations
depending on the build script's copy logic.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll use dnf5 in a ujust command — it's just for setup." | Never. ujust is user-facing. dnf5 requires root. Use Brewfile/Flatpak. |
| "I don't need to validate the Flatpak ID — it's a well-known app." | Typos happen. Always validate on Flathub. |
| "I'll add a .just file but skip the group header." | Group headers organize the `ujust --list` output. Always include them. |

## Red Flags

- `dnf5` appearing in any `.just` file
- Flatpak app ID without Flathub validation
- Brewfile with broken Ruby syntax
- `.just` file without a `[group('...')]` header
- Config files in `custom/files/` without corresponding build script copy logic

## Verification

- [ ] Brewfile syntax valid? (`brew bundle check --file custom/brew/default.Brewfile`)
- [ ] Flatpak IDs exist on Flathub? (`flatpak search APP_ID`)
- [ ] Justfile syntax valid? (`just --unstable --fmt --check -f custom/ujust/<file>.just`)
- [ ] No `dnf5` in any `.just` file?
- [ ] Group headers present on all ujust recipes?
