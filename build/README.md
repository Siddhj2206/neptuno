# Build scripts

Scripts that run during image assembly. The Containerfile names each one in its
own `RUN` block, so the order is whatever the Containerfile says — there is no
prefix auto-discovery. The numbers communicate intent.

## Phases

| Script | Does |
|---|---|
| `00-image-info.sh` | Writes the image identity into `os-release` and `/usr/share/neptuno/image-info.json`. Keeps `ID=fedora`; sets the names, variant and `IMAGE_*` fields and the update reference. |
| `10-packages.sh` | Every RPM change, from `packages/*.toml`: snapshots the enabled units, removes, installs Fedora, COPR and third-party packages, and asserts each one. |
| `20-overlay.sh` | Copies `system_files/` (`shared/`, then `desktop/`), installs the nx release, the Flathub descriptor and the Flatpak preinstall list. Installs no RPMs and enables nothing. |
| `30-desktop.sh` | Desktop steps that aren't shipped files: greeter checks, schema compilation, the hidden Settings entry, the fingerprint PAM feature. |
| `40-services.sh` | The single enablement pass: every manifest's `[services]` and `[[wants]]`, mirrored into a preset file. |
| `50-initramfs.sh` | Rebuilds the initramfs after the removals and with `90-neptuno.conf`. |
| `90-cleanup.sh` | Disables and removes build-time repos, audits enablement against the snapshot, prunes build artifacts, prepares for `bootc container lint`. |

Helpers, not phases: `scripts/package-lib.sh` (sourced), `scripts/read-packages`
(TOML reader), `scripts/systemd-units` (snapshot and audit),
`scripts/render-niri-skel`, and `validate-flatpaks.sh` (run by the Justfile and CI).

## Manifests and enablement

`packages/*.toml` is the declaration of record. Each file may carry any of:

- `[remove].packages` — packages removed from the base
- `[fedora].packages` — one install transaction, then an assert per package
- `["copr:<owner>/<project>"].packages` — enabled, installed, disabled in cleanup
- `["third-party:<id>"]` — repo URL/id/file, packages, expected packager
- `[services].system` / `[services].user` — units `40-services.sh` enables
- `[services].disabled` — units a package preset enables that the image does
  not want; disabled explicitly so the audit stays meaningful
- `[[wants]]` — units linked into a specific target's `.wants` directory
  instead of being enabled for every session (`scope`, `target`, `units`)

A unit must be enabled through a manifest. `10-packages.sh` snapshots the base
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
- Add repositories through a manifest section, never by hand: the helpers
  enable each one for one transaction and cleanup removes it.
- Keep one purpose per script, and name it for that purpose.
