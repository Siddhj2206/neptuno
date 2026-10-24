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

Brewfiles use Ruby syntax. They define Homebrew packages installed by users after deployment. Homebrew itself is pre-staged at build time via the `@ublue-os/brew` OCI container and extracted on first boot by `brew-setup.service`; Brewfiles define what users install after that extraction.

### File Locations

| File                           | Purpose                                    |
| ------------------------------ | ------------------------------------------ |
| `custom/brew/default.Brewfile` | General purpose CLI tools (the only Brewfile) |
| Custom `*.Brewfile`            | Create as needed for specific use cases    |

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

### How Users Invoke Them

Users install via `ujust` commands (shortcuts defined in `custom/ujust/custom-system.just` — the only recipe file; current recipes: `install-dms-config`, `changelogs`):

```bash
# Restore DMS/skel config onto an existing user
ujust install-dms-config

# Show image changelogs
ujust changelogs
```

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

## Skel dotfiles: `custom/config/`

`custom/config/` is rsynced verbatim to `/etc/skel` by `build/10-build.sh`; the
tree root mirrors `~` (`.config/...`). Only user-level config belongs here.

- `niri/dms/*.kdl` are the fragments `config.kdl` includes. Ship the real
  content copied from a running system, **not** comment-only stubs: DMS does
  not reliably regenerate them (binds especially), so the shipped copies are
  what a new user actually gets. After changing binds/window rules in DMS
  Settings, re-copy `~/.config/niri/dms/*.kdl` here.
- Do not seed `~/.config/DankMaterialShell/settings.json` — that is per-user
  DMS state, not a default.
- Validate niri changes with `niri validate -c custom/config/.config/niri/config.kdl`
  (includes resolve relative to the file) and ghostty changes with
  `ghostty +validate-config --config-file=...`.
- Files land in `/etc/skel` only for new users; existing users get them via
  `ujust install-dms-config`.

## System files: `custom/files/`

`custom/files/` mirrors `/` verbatim and is rsynced to the image root by
`build/10-build.sh` (`rsync -rvKl /ctx/custom/files/ /`). Unit files, wants
symlinks, gschema overrides, PAM/greetd config and udev rules live here, not in
heredocs. Layout rules are in `custom/files/README.md`.

- **udev rules go in `usr/lib/udev/rules.d/`** (immutable image path) and must
  pass `udevadm verify <file>`.
- **`TAG+="uaccess"` rules must sort before `73-seat-late.rules`** — that file
  runs the `uaccess` builtin, so a `73`+ name tags the device after the ACL
  pass and the tag has no effect. Use the `70-` range and
  `ACTION!="remove", …` so the tag is re-applied on `change` events.
- **Never tell users to join the `input` group on this image.** `input` is only
  defined in `/usr/lib/group` and resolved via `nss-altfiles`, so
  `usermod -aG input` exits 0 without writing a membership into `/etc/group`
  (the only file shadow-utils edits). The image grants evdev access through
  `70-neptuno-input-uaccess.rules` instead, which covers DMS's evdev manager
  (Caps Lock OSD) and HEX dictation without a re-login.
- Input device read access is keyboard-read capability (keylogger equivalent),
  scoped by uaccess to the active seat session and revoked at logout. Keep the
  granting rule narrow and commented.

## ujust: `custom/ujust/*.just`

ujust files define user convenience commands. All `.just` files are auto-consolidated during the build.

### Critical Rule: NEVER USE `dnf5` IN JUST FILES

ujust commands are shortcuts for user convenience — they should only invoke Brewfiles, Flatpaks, or other user-level tools. **Never use `dnf5` or any package manager in a just file.**

### Common Structure

```just
# vim: set ft=make :

[group('System')]
install-dms-config:
    #!/usr/bin/env bash
    ...restore skel/DMS config onto the invoking user...

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
| "I'll add `dnf5 install` to a just file for convenience."                   | **Never.** ujust is for user-level shortcuts. Use `build/10-build.sh` for system packages.            |
| "Flatpaks should be in the container so they work offline."                 | Flatpaks are intentionally post-first-boot to keep the container small and allow independent updates. |
| "I'll put the Brewfile inline in the just file instead of a separate file." | Separate Brewfiles are easier to validate and let users install them manually too.                    |
| "The just file doesn't need a shebang if it's just one command."            | Always use a shebang (`#!/usr/bin/env bash`) for explicit execution context.                          |

## Red Flags

- `dnf5` or `rpm-ostree` in any `.just` file
- Flatpak preinstall missing `Branch=stable`
- Brewfile without a corresponding `ujust` shortcut in `custom/ujust/`
- App ID in `.preinstall` not verified on Flathub
- Just file using `dnf` or `yum` instead of proper Brewfile/Flatpak shortcuts

## Verification

- [ ] Does each `.Brewfile` have a corresponding `ujust` shortcut?
- [ ] Do all Flatpak entries specify `Branch=stable`?
- [ ] Are all app IDs in `.preinstall` files verified on Flathub?
- [ ] Does `just --list` pass without errors?
- [ ] Do udev rules pass `udevadm verify` and sort before `73-seat-late.rules`?
- [ ] Does `brew bundle check --file` pass for each Brewfile?
- [ ] Is there NO `dnf5`, `dnf`, or `rpm-ostree` in any `.just` file?
