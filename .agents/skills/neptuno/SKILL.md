# neptuno

This repository's delta on top of finpilot. Read `overview` first for how the
image is assembled; this skill covers only what Neptuno changes and the rules
that keep it from drifting back into stale patterns.

## Base and desktop

Fedora Silverblue 45 (GNOME/GDM) plus Niri with DankMaterialShell as a second
session. GDM stays the display manager. The base pin is the `FROM` line in
`Containerfile`; Renovate holds the major, so bump it deliberately.

ghostty is not in Fedora and the upstream `scottames/ghostty` COPR stops at
fedora-44, so the terminal installs from `duxlabs/dux-repo` in `niri.toml`
(the COPR that carries the DMS dependencies; formerly `avengemedia/danklinux`). Moving it back to `base.toml` means a COPR section that
only ever resolves the stale Fedora 45 build, or a second COPR with no Fedora 45
build at all.

## Manifests are the declaration of record

`build/packages/*.toml` carries packages, removals, repositories, and systemd
enablement. No layer may install or enable anything that is not declared there.

| File | Applied by | Contents |
|---|---|---|
| `overlay.toml` | `10-overlay.sh` | services whose units arrive with the overlays |
| `base.toml` | `25-neptuno-packages.sh` | removals, base RPMs, Tailscale, the uupd COPR, base services |
| `multimedia.toml` | `25-neptuno-packages.sh` | negativo17 codec stack and Mesa/VA overrides |
| `niri.toml` | `40-niri.sh` | niri, DMS and ghostty COPRs, compositor services |

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
- **PAM and the keyring**: `pam_oo7` unlocks the oo7 login keyring only with
  a typed password. authselect `with-fingerprint` puts `pam_fprintd` in
  `system-auth` as `sufficient` ahead of `pam_unix`, so any service that
  includes it can log in by finger and hand `pam_oo7` nothing; apps then
  report their secrets as missing. `/etc/pam.d/greetd` takes auth from
  `password-auth` for that reason; `30-desktop.sh` fails the build if it drifts.
- **nx lives in its own repo**: `/usr/bin/nx` is the Go release from
  Siddhj2206/nx, installed by `20-overlay.sh` at `NX_VERSION` and checked
  against that release's `SHA256SUMS` (Renovate can bump a version but not
  recompute an asset hash). Change nx there, tag a release, and let Renovate
  (or a manual `NX_VERSION` bump) bring it in; don't add a script back to
  `system_files`.
- **fish vendor_conf.d order**: fish sources it in name order, and nx tools
  only reach PATH in nix-core's `nix.fish`. Our defaults are
  `zz-neptuno.fish` so their `command -q` guards see them; a bats test pins
  the order. Brew's own hooks hid this on the pre-rebuild laptop.
- **Rebasing a machine from the old ublue image** (the laptop, 2026-11-16):
  ostree's /etc merge keeps any file the old system modified, so the old
  image's state shadows ours. Found: `/etc/selinux` (a local semanage rule
  kept the old compiled policy and dropped dms-greeter's file contexts, so the
  greeter could not write its cache), an `fstab` line for `/` (composefs root
  cannot be remounted, so `systemd-remount-fs` fails), old unit files in
  `/etc/systemd/system` overriding image packages (asusd), and a stale
  `/etc/pam.d/dankshell`. Dynamic system uids also moved between the images,
  leaving `/var` files owned by the wrong account. A fresh `/etc` (ISO or
  bcvk) never shows any of this; check `ostree admin config-diff` after a
  rebase.
- **DMS_PRIVESC is sudo, not run0**: run0 execs its command directly as
  `unconfined_t`, and the Fedora policy refuses `usermod` and `restorecon` as
  entrypoints for that domain, so the greeter sync dies with exit 203/EXEC.
  The AVC (`denied { entrypoint }`) is in the journal, not the DMS output.
- **Weak deps are off at build time** (`install_weak_deps=0`), so a
  Recommends that a package needs at runtime must be named in a manifest.
  Found: `nix-core` recommends busybox, its sandbox `/bin/sh`.
- **The initramfs is ours**: `50-initramfs.sh` rebuilds it, because the
  base's was generated before our removals and without
  `dracut.conf.d/90-neptuno.conf`. Anything that should change what boots
  (drivers, firmware, dracut modules) goes in that conf, not a removal alone.
- **Cleanup**: Fedora 45 keeps repo files in `/usr/share/dnf5/repos.d` as well
  as `/etc/yum.repos.d`; sweep both or COPRs ship enabled.

## Validation

`just test-unit` (contract + template suites), `just lint`, `just check`, then
`just build`. The overlay suite sandboxes paths through `CHERRY_PICK_ROOT`;
an assert that reads an absolute host path will pass on a Neptuno host and fail
on CI, so give every new path assert a sandbox root. The manifest contract tests live in
`tests/contract/manifests_test.bats`; the overlay and cleanup suites cover the
enablement wiring.
