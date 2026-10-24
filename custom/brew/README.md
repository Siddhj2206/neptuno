# Homebrew

Brewfiles declared here are copied into
`/usr/share/ublue-os/homebrew/preinstall.d/` and installed on first login by
`brew-preinstall.service`, which is content-addressed: editing a Brewfile
re-applies it, and removing an entry uninstalls that package without touching
packages the user added.

## Files

- `default.Brewfile` — the CLI tools every Neptuno user gets

The image also ships `/usr/share/ublue-os/homebrew/fonts.Brewfile`, a curated
font set from Common's shared layer, so this directory does not need its own.

Anything that must exist before first login — login shells, systemd services,
desktop integration — belongs in `build/packages/*.toml`, not here.

## Adding one

Write a `.Brewfile` here, then add a `ujust` recipe for it in
`custom/ujust/custom-apps.just` so users install it by name instead of
remembering the path. That directory's README has the recipe shape.

## Format

A Brewfile is a Ruby DSL with three kinds of entry:

```ruby
tap "homebrew/cask"           # add a third-party repository
brew "bat"                    # a formula: a CLI tool
brew "eza"
cask "font-jetbrains-mono"    # a cask: a macOS-style package
```

- `tap` comes before anything that needs it.
- `brew` installs formulae.
- `cask` installs macOS-style packages. On Linux only some are available —
  mostly fonts and those that ship a Linux binary.

A repository Brewfile is never evaluated — that would be code execution from a
pull request. `just validate-brewfiles` checks one literally instead, and the
pre-commit hook calls the same script.

## Using them

```bash
brew bundle --file /usr/share/ublue-os/homebrew/preinstall.d/default.Brewfile
```

or, on an image built from this template:

```bash
ujust install-default-apps
```

Homebrew itself is pre-staged at build time. `brew-setup.service` (a system
unit) unpacks the tarball on first boot; `brew-preinstall.service` (a user
unit) installs the managed set at graphical login. There is no systemd ordering
between the two managers: the user unit is gated on the brew binary existing, so
a login that beats the unpack retries on the next login.

`brew-preinstall.service` is enabled with `systemctl --global enable`. That call
is load-bearing: common's `01-brew-preinstall.preset` is inert in a
Containerfile build, because systemd applies presets only for the system manager
on a machine's first boot.
