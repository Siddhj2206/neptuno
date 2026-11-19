---
name: overview
description: >-
  Map of the repository: how the image is assembled, where each kind of change
  goes, and which skill owns it. Use when orienting, or when deciding where a
  package, app, file or setting belongs.
---

# Overview

Neptuno is a personal bootc image: Fedora `base-atomic` 45 with niri,
DankMaterialShell and greetd, built in this repository and published to
`ghcr.io/siddhj2206/neptuno`. `doc/product.md` is the record of every package
and design decision, with the reasoning; read the section a change touches
before reversing a decision there.

## How the image is assembled

The `Containerfile` is the source of truth and is written to be read:

1. A `ctx` scratch stage holds `build/`, `system_files/` and `flatpaks/`.
2. `FROM quay.io/fedora-ostree-desktops/base-atomic:45@sha256:…` is the only
   place the base is chosen.
3. One `RUN` per phase, in the order the Containerfile names them.
   [build/README.md](../../../build/README.md) lists the phases.
4. Late `ARG`s feed the `LABEL` block, then `bootc container lint`.

`just rechunk` (chunkah) then re-layers the image; everything after it
(content tests, boot test, signing) runs on the rechunked digest.

## Where a change goes

| The thing is… | Put it in | Lands |
|---|---|---|
| An RPM, a removal, a COPR or third-party repo | `build/packages/*.toml` | build time, by `10-packages.sh` |
| A systemd unit to enable or disable | `[services]` / `[[wants]]` in the same manifest | build time, by `40-services.sh` |
| A file under `/usr` or `/etc`, or a seeded user config | `system_files/shared/` (any image) or `system_files/desktop/` (niri, DMS, greeter) | build time, by `20-overlay.sh` |
| A GUI application | `flatpaks/default.preinstall` | first boot |
| A user's CLI tool or `-devel` package | nothing in the image: the user runs `nx add` | on demand |
| A `neptuno <recipe>` command | `system_files/shared/usr/share/neptuno/justfile` | build time |

The line is who decides: the image ships what every boot needs; the user adds
the rest with Flatpak or `nx`.

## Layout

| Path | Holds |
|---|---|
| `Containerfile` | Assembly: context, base, phases, labels. |
| `Justfile` | Every check and build step, locally and in CI (`just --list`). |
| `build/` | Phases, manifests (`packages/`) and their helpers (`scripts/`). |
| `system_files/` | The filesystem overlay. |
| `flatpaks/` | The Flatpak preinstall list. |
| `iso/` | Installer ISO and qcow2 configuration (local only). |
| `tests/` | `contract/` (what the image promises), `template/` (build wiring), `image/check.sh` (run against a built image). |
| `.github/` | `build.yml`, `clean.yml`, Renovate config. |

## Which skill

| I need to… | Load |
|---|---|
| Change a manifest, an overlay file, PAM, the greeter, Nix or nx | `neptuno` |
| Change the Containerfile, Justfile, a phase or a pin | `build` |
| Change a workflow, Renovate, signing, tags or retention | `ci` |
| Fix something broken, or check before a pull request | `troubleshooting` |
