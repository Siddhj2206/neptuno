# Homebrew Integration

This directory contains Brewfile declarations that will be copied into your custom image at `/usr/share/ublue-os/homebrew/`.

## What are Brewfiles?

Brewfiles are Homebrew's way of declaring packages in a declarative format. They allow you to specify which packages, taps, and casks you want installed.

## How It Works

1. **During Build**: `build/steps/10-build.sh` copies `preinstall.d/*.Brewfile` to `/usr/share/ublue-os/homebrew/preinstall.d/` in the image
2. **First Login**: `brew-preinstall.service` (per-user) processes every file in `preinstall.d/` — installing new packages, uninstalling ones removed from the list, and never touching user-added packages
3. **User Experience**: Declarative package management via Homebrew, OS-managed on every user account

## Adding a Preinstall Package

1. Add the formula/cask line to `preinstall.d/default.Brewfile`
2. Build your image — the next login applies it (content-addressed: only on hash change)

**Important**: removing a package from a preinstall Brewfile *uninstalls* it from user systems. User-added packages are never affected.

## Contents

- `preinstall.d/default.Brewfile` — OS-managed packages installed for every user at first login
