# Homebrew Integration

Brewfiles in this directory are **auto-preinstalled**: every `*.Brewfile`
here is copied to `/usr/share/ublue-os/homebrew/preinstall.d/` at build and
applied at first login by `brew-preinstall.service` (content-addressed by
hash — editing a file is enough to re-apply on the next login).

## What goes here vs the base image

- **This directory: USER tools.** Things a person runs interactively
  (CLI tools, fonts, shells). Homebrew delivers them; the base image stays
  lean.
- **Base image (`build/packages/base.toml`): SYSTEM tools.** Things needed
  at build time, by systemd services, at first boot *before* brew is
  extracted, or for desktop integration (e.g. `ghostty`, `git`, `jq`,
  `rsync`, `gum`).

## Files

- **`default.Brewfile`** — the default preinstall set (htop, nvtop, fzf,
  glow, zenity + shells, dev tools, modern CLI replacements). All entries
  verified on Homebrew with Linux bottles.

## Adding a user tool

1. Add `brew "name"` to `default.Brewfile` (keep the comment style).
2. That's it — it lands at the next image update + first login.

`brew-preinstall.service` runs in the graphical session after brew is
extracted (`brew-setup.service`); both are user units from the
`@ublue-os/brew` / `@projectbluefin/common` overlays.

## Resources

- [Homebrew](https://brew.sh/)
- [`brew bundle` docs](https://docs.brew.sh/Manpage#bundle-subcommand)
- `brew search <name>` on the live system to confirm availability
