# Build scripts

Scripts that run during image assembly. The Containerfile names each one in its
own `RUN` block, so the order is whatever the Containerfile says — there is no
prefix auto-discovery. The numbers communicate intent.

## Phases

| Script | Does |
|---|---|
| `00-image-info.sh` | Writes the image identity into `os-release` and `image-info.json`: the base image name, the Fedora major derived from the base's `os-release`, the version string, and the tag. |
| `10-overlay.sh` | Overlays `projectbluefin/common`'s shared layer and the Brew integration, copies this template's declarations (Brewfiles, ujust recipes, Flatpak preinstalls, `/etc/skel` seeds), and enables the units that consume them. Installs no packages. |
| `20-packages-and-services.sh` | Installs the template's default RPMs and uupd, and enables the update timers. |
| `25-neptuno-packages.sh` | Neptuno's WM-agnostic package layer, driven by `packages/base.toml` and `packages/multimedia.toml`: removals, base packages, Tailscale, COPRs, the negativo17 codec stack, zram, and the base service list. |
| `40-niri.sh` | Neptuno's compositor layer, driven by `packages/niri.toml`: niri, DMS, the COPR stack, theme schema compilation, and the compositor service list. |
| `90-cleanup.sh` | Finalises package and Flatpak sources, prunes build artifacts, audits systemd enablement, and prepares for `bootc container lint`. |

Helpers, not phases: `copr-helpers.sh` and `scripts/package-lib.sh` (sourced),
`scripts/read-packages` (TOML reader), `systemd-units` (enablement snapshot/audit), and
`validate-{brewfiles,flatpaks}.sh` (called by the Justfile and CI).

## Manifests and enablement

`packages/*.toml` is the declaration of record. A layer reads its own manifest:

- `[remove].packages` — packages the layer removes
- `[fedora].packages` — one install transaction, then an assert per package
- `["copr:<owner>/<project>"].packages` — enabled, installed, disabled in cleanup
- `["third-party:<id>"]` — repo URL/id/file, packages, expected packager
- `[services].system` / `[services].user` — units enabled by that layer
- `[services].disabled` — units a package preset enables that the image does
  not want; disabled explicitly so the audit stays meaningful
- `[[wants]]` — units linked into a specific target's `.wants` directory
  instead of being enabled for every session (`scope`, `target`, `units`)

A unit must be enabled through a manifest. `10-overlay.sh` snapshots the base
image's enabled set; `90-cleanup.sh` diffs it against the union of every
manifest and fails the build on anything enabled outside it. That catches RPM
scriptlets and overlay symlinks, not just our own calls.

## Writing one

```bash
#!/usr/bin/env bash
set -euo pipefail

dnf5 install -y package-name
```

- Scripts run as root, with the build context at `/ctx`.
- Use `dnf5`, never `dnf` or `yum`, and always `-y`.
- Disable any repository you enable. `copr_install_isolated` does it for COPRs.
- Keep one purpose per script, and name it for that purpose.
