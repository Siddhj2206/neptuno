# Build Scripts

This directory contains build scripts used during image creation. The
Containerfile explicitly runs each script in order; extra scripts must be
explicitly added to the Containerfile.

## How It Works

Scripts are named with a number prefix (`00-`, `10-`, `20-`, `25-`, `40-`,
`45-`) and run in ascending order during the container build process. Each script is one
**layer**: metadata, overlays, wm-agnostic packages, multimedia, the compositor, dx.

## Included Scripts

- **`00-image-info.sh`** - Image identity (os-release / image-info.json), ARG-driven
- **`10-build.sh`** - Overlays + custom files: brew OCI layer, common `shared/` layer (ujust, flatpak-preinstall, brew-preinstall), `custom/files/` → `/`, `custom/config/` → `/etc/skel`, just consolidation, flatpak preinstall files; wm-agnostic
- **`20-base.sh`** - WM-agnostic desktop foundation packages (fonts, graphics, audio, portals, keyring, display manager, zram, power) from `packages/base.toml`; COPR sections installed per-repo; wm-agnostic
- **`25-multimedia.sh`** - Full multimedia (ffmpeg + non-FOSS codecs, mesa/VA overrides) from the negativo17 `fedora-multimedia` repo via `packages/multimedia.toml`; wm-agnostic
- **`40-niri.sh`** - Compositor layer: niri + DMS stack from `packages/niri.toml` + dynamic wiring (greeter, first-boot units, schemas); **wm-specific — renumber/replace for a different compositor**
- **`45-dx.sh`** - DX layer: developer experience stack — docker-ce daemon (official third-party repo, removed after install), adb, minimal libvirt/qemu host daemon — from `packages/dx.toml`; daemons socket-activated; wm-agnostic
- `clean-stage.sh` - Cleanup stage (build artifacts, final image hygiene)
- `packages/` - TOML manifests (the "manifest of record": `base.toml`, `firmware.toml`, `multimedia.toml`, `niri.toml`, `dx.toml`)
- `scripts/` - Shared helpers (`read-packages`, `package-lib.sh`)

## Creating Your Own Scripts

Create numbered scripts between the layers above (e.g. `30-…` for a
wm-agnostic app layer, `45-…` for compositor extras):

```bash
# 30-development.sh - Development tools (wm-agnostic)
# 45-niri-extra.sh   - Compositor-specific extras
```

### Script Template

```bash
#!/usr/bin/bash
set -euo pipefail

echo "Running custom setup..."
# Your commands here
```

### Conventions

- **Manifest-driven installs**: packages live in `packages/*.toml`, read by
  `scripts/read-packages`. Never hardcode `dnf5 install` lists in a layer
  script.
- **Shared helpers** (`scripts/package-lib.sh`) — use these, don't reinvent:
  - `install_fedora_section <manifest> <label> [dnf5 flags...]` — installs
    the `[fedora]` section and asserts every package landed
  - `install_copr_sections <manifest>` — enables ALL `["copr:<owner>/<project>"]`
    sections, then installs their packages in ONE transaction (explicit args
    beat coprdep-pulled builds: quickshell-git over plain quickshell); explicit
    chroot via `copr_chroot`; COPRs disabled by clean-stage.sh in the final
    image
  - `assert_packages_present <label> <pkgs...>`, `assert_vendor <label>
    <vendor> <pkgs...>`
- **Assert gates**: every layer verifies its packages post-install — the
  build FAILS listing missing names. Do not remove.
- **COPR policy (AGENTS.md rule 3)**: COPRs are enabled only during the
  build layers that install from them; `clean-stage.sh` disables them in the
  final image.
- **Group markers**: wrap each step in `echo "::group:: Name"` /
  `echo "::endgroup::"` (CI annotations).
- **Formatting**: shellcheck + shfmt — `just lint`, `just format`.

### Best Practices

- **One purpose per script**: Easier to debug and maintain
- **Package installs go in the TOML manifests**, not inline `dnf5 install`
  lines — see `packages/base.toml` for the format and `scripts/read-packages`
- **Keep composition swap-friendly**: wm-agnostic things in `10/20/25/45`,
  wm-specific things in `40-*` (+ `custom/config`, `custom/files`)
- **Clean up after yourself**: remove temporary files; COPR repos are
  disabled by `clean-stage.sh` before lint
- **Test incrementally**: one script at a time, then `just build`
- **Comment your code**: Future you will thank present you

### Disabling a Script

Remove its corresponding `RUN` block from `Containerfile` (or delete the script).

## Execution Order

The template runs scripts explicitly, rather than automatically discovering
files by prefix. Place extra script blocks between the existing layers and
before `clean-stage.sh`. Use numbered names to communicate the intended order.

## Notes

- Scripts run as root during build
- Build context is available at `/ctx` (`/ctx/build`, `/ctx/custom`)
- Use dnf5 for package management (not dnf or yum)
- Always use `-y` flag for non-interactive installs
- System-wide static files live in `custom/files/`; user config defaults in
  `custom/config/` — prefer those over heredocs in scripts
