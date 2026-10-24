# neptuno

This repository's delta on top of finpilot. Read `overview` first for how the
image is assembled; this skill covers only what Neptuno changes and the rules
that keep it from drifting back into stale patterns.

## Base and desktop

Fedora Silverblue 45 (GNOME/GDM) plus Niri with DankMaterialShell as a second
session. GDM stays the display manager. The base pin is the `FROM` line in
`Containerfile`; Renovate holds the major, so bump it deliberately.

## Manifests are the declaration of record

`build/packages/*.toml` carries packages, removals, repositories, and systemd
enablement. No layer may install or enable anything that is not declared there.

| File | Applied by | Contents |
|---|---|---|
| `overlay.toml` | `10-overlay.sh` | services whose units arrive with the overlays |
| `base.toml` | `25-neptuno-packages.sh` | removals, base RPMs, Tailscale, ghostty/uupd COPRs, base services |
| `multimedia.toml` | `25-neptuno-packages.sh` | negativo17 codec stack and Mesa/VA overrides |
| `niri.toml` | `40-niri.sh` | niri, DMS COPRs, compositor services |

Schema: `[remove].packages`, `[fedora].packages`,
`["copr:<owner>/<project>"].packages`, `["third-party:<id>"]` with
`repo_url`/`repo_id`/`repo_file`/`packager`, and `[services].system` / `[services].user` / `[services].disabled`, plus
`[[wants]]` for units linked into
a named target (`scope`, `target`, `units`) instead of enabled globally. A
layer supplies the units before its own enablement runs.

`build/scripts/read-packages` is the reader; `build/scripts/package-lib.sh`
holds `install_*`, `remove_*`, `assert_*`, and `enable_services_section`.

## Enablement policy

Enable explicitly, never by applying presets, and never mask.

- `10-overlay.sh` snapshots the enabled set to `/var/tmp/neptuno-units.before`
  before any overlay lands.
- `90-cleanup.sh` runs `build/scripts/systemd-units check` against every manifest and fails if a
  unit is enabled that the snapshot and manifests do not name. That catches RPM
  scriptlets and inherited `.wants` symlinks.
- Do not reintroduce `systemctl preset-all`, a `/dev/null` mask, or a
  build-time `systemctl enable` outside a manifest.

## Consumption rules that are easy to get wrong

- **Flathub**: ship the pinned `/etc/flatpak/remotes.d/flathub.flatpakrepo`
  descriptor (10-overlay fetches and hashes it). A build-time
  `flatpak remote-add` writes to `/var` and is deleted by cleanup, so the image
  would ship with no remote.
- **Homebrew**: Neptuno auto-installs its Brewfiles on first login, so they go
  to `/usr/share/ublue-os/homebrew/preinstall.d/`. A Brewfile in the parent
  `homebrew/` directory is declaration-only and will not install.
  `brew-preinstall.service` must be enabled with `systemctl --global enable`:
  user-scope presets are inert in a Containerfile build (systemd applies
  presets only for the system manager on a machine's first boot).
- **common**: overlay `common/shared/` only. `common/bluefin/` is product
  opinion and is cherry-picked by path with an assert per path. Never overlay
  `bluefin/` wholesale, and do not import its `just/` directory: Neptuno owns
  `changelogs`.
- **ujust**: recipes live in `custom/ujust/`; 10-overlay merges them into
  `60-custom.just` in sorted order.
- **Cleanup**: Fedora 45 keeps repo files in `/usr/share/dnf5/repos.d` as well
  as `/etc/yum.repos.d`; sweep both or COPRs ship enabled.

## Validation

`just test-unit` (contract + template suites), `just lint`, `just check`, then
`just build`. The manifest contract tests live in
`tests/contract/manifests_test.bats`; the overlay and cleanup suites cover the
enablement wiring.
