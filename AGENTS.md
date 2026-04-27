# AGENTS.md

## Scope

These instructions apply to the whole `neptuno` repository.

`neptuno` is a custom immutable image based on `bluefin-dx`. Keep changes aligned with Bluefin/common conventions unless there is a clear `neptuno`-specific reason to differ.

---

## Core principles

- Prefer small, explicit, maintainable changes over broad refactors.
- Treat `main` as the production branch.
- Use `dnf5` for build-time system packages and services.
- Use Brewfiles and Flatpaks for runtime/user-facing software.
- Do not add unnecessary local patterns when Bluefin/common already provides one.

---

## Build-time vs runtime

### Build-time

Use `build/*.sh` for anything that must be baked into the image:

- system packages
- services
- system config
- session defaults
- files copied into image-owned locations

Rules:

- use `dnf5` only
- always use `-y` for non-interactive installs
- if enabling a COPR, disable it after install
- prefer existing helper patterns like `copr_install_isolated` where practical

### Runtime

Use `custom/` for user-facing runtime content:

- `custom/brew/*.Brewfile` for Homebrew bundles
- `custom/flatpaks/*.preinstall` for Flatpak preinstalls
- `custom/ujust/*.just` for user commands
- `custom/config/` for default config shipped to `/etc/skel/.config`

Rules:

- do not install packages with `dnf5` inside `ujust`
- `ujust` should wrap Brew/Flatpak/user workflows, not mutate the base image

---

## Where to put changes

- Add build-time packages: `build/10-build.sh` or another numbered build script
- Add COPR-based packages: a numbered `build/*.sh` script, and disable the COPR afterward
- Add runtime CLI tools: `custom/brew/*.Brewfile`
- Add runtime GUI apps: `custom/flatpaks/*.preinstall`
- Add user helper commands: `custom/ujust/*.just`
- Change the base image or OCI imports: `Containerfile`
- Change local build workflow: `Justfile`

Keep numbered build scripts focused:

- `10-*` main/common setup
- `20-*` additional layers
- `30-*` optional stacks like gaming or desktop-specific layers
- `40-*` hardware-specific layers

---

## Bluefin/common integration

This repository inherits shared behavior from:

- `bluefin-dx`
- `projectbluefin/common`

Before adding new `ujust` helpers or image behavior, check whether Bluefin/common already provides it.

Avoid duplicating generic commands that upstream already owns, especially around:

- updates
- cleanup
- devmode
- group setup
- generic app helpers
- generic Brewfile selection

Custom `ujust` commands should focus on `neptuno`-specific workflows.

---

## DMS / Niri rules

### Ownership model

Treat these as image-owned defaults:

- `custom/config/niri/config.kdl`
- vendored DMS fragment files under `custom/config/niri/dms/`
- `custom/config/ghostty/config`
- `custom/config/environment.d/90-dms.conf`

Treat this as the user override path:

- `custom/config/niri/local.kdl`

The intended runtime model is:

- shipped defaults are image-owned
- user-specific Niri changes belong in `~/.config/niri/local.kdl`
- Ghostty may remain user-managed if the user chooses not to replace it during refresh

Do not put `neptuno`-specific customization into vendored DMS fragment files.

### DMS sync rule

The files below are upstream mirrors from `DankMaterialShell` and must not be treated as hand-maintained local config:

- `custom/config/niri/dms/colors.kdl`
- `custom/config/niri/dms/layout.kdl`
- `custom/config/niri/dms/alttab.kdl`
- `custom/config/niri/dms/binds.kdl`

When updating DMS or reviewing DMS-related changes:

1. Check whether these vendored DMS fragment files still match upstream `DankMaterialShell`.
2. If they are out of date, update them from upstream before making additional DMS-related changes.
3. Keep `neptuno`-specific changes in `config.kdl` or `local.kdl`, not in the mirrored DMS fragment files.

Important:

- `dms setup` is disabled on immutable/image-based systems, so these files cannot be refreshed on a running bootc system with normal DMS setup commands.
- Because of that, the repo must treat these vendored files as upstream mirrors and refresh them from source when needed.

### Config refresh model

Existing users refresh shipped defaults manually with:

- `ujust refresh-dms-config`

Personal Niri changes should remain in:

- `~/.config/niri/local.kdl`

Do not assume existing user config is auto-migrated.

---

## Services and session setup

Enable services only when there is a clear reason.

Prefer session wiring that is easy to reason about:

- attach DMS to the Niri session
- avoid overly broad service enablement unless required

If a service or session behavior is hardware-specific or user-specific, document why it is being enabled.

---

## Hardware-specific layers

Hardware-specific packages should be clearly isolated and justified.

Example:

- ASUS-related packages belong in a dedicated layer like `build/40-asus.sh`

If you enable third-party repositories for hardware support, disable them after package installation.

---

## Validation and hygiene

Before finalizing changes:

- validate shell files
- validate YAML if edited
- validate Justfiles if edited
- avoid committing syntax errors
- do not simplify working code just to silence diagnostics

If you edit package lists or config ownership behavior, update the README accordingly.

---

## Documentation rules

Keep README changes practical and user-focused.

If behavior changes, document:

- what changed
- who owns the config afterward
- what the user should do after updating
- where personal overrides belong

For DMS/Niri changes, keep the README aligned with the actual ownership model:

- image-owned defaults
- user-owned `local.kdl`
- manual refresh via `ujust refresh-dms-config`

---

## Repository-specific cautions

- Keep `.gitignore` protecting local-only or secret material.
- Local reference repositories under `References/` are for comparison only and should stay untracked.
- Do not treat vendored DMS mirrors as hand-authored config.
- Do not reintroduce duplicated generic `ujust` app helpers already covered by Bluefin/common.
- Prefer explicit comments when a configuration choice intentionally differs from upstream.

---

## Quick rules

- Use `dnf5`, not `dnf`, `yum`, or `rpm-ostree` in build scripts.
- Disable COPRs after use.
- Use Brew/Flatpak for runtime software.
- Keep DMS fragment files synced from upstream.
- Put user Niri customizations in `local.kdl`.
- Keep existing-user config refresh manual.
- Update README when config ownership or package behavior changes.
