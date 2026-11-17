---
name: neptuno
description: >-
  Neptuno's rules: manifests, unit enablement, the overlay, PAM, Nix and nx,
  and the pitfalls already paid for. Use when changing a package, a unit, a
  file under system_files/, or anything on the desktop or Nix path.
---

# neptuno

The rules that keep the image from drifting back into patterns that broke.
`overview` says where a change goes; this skill says how to make it safely.

## Manifests are the declaration of record

`build/packages/*.toml` carries packages, removals, repositories and systemd
enablement. Nothing installs or enables anything that is not declared there.

| File | Contents |
|---|---|
| `base.toml` | shells, CLI glue, power, containers, networking, Nix, Tailscale, topgrade |
| `desktop.toml` | niri, DMS, greetd, portals, keyring, theming, input; the `duxlabs` COPRs |
| `hardware.toml` | the Zenbook: asusctl, fingerprint |
| `devlibs.toml` | `-devel` packages so a plain `cargo build` works on the host |
| `removals.toml` | packages removed from the base, and base units disabled |

`10-packages.sh` applies every package section; `40-services.sh` applies
every `[services]` and `[[wants]]`. Schema: `[remove].packages`,
`[fedora].packages`, `["copr:<owner>/<project>"].packages` (plus `.deps`, the
only other names that COPR may supply), `["third-party:<id>"]` with
`repo_url`/`repo_id`/`repo_file`/`packager`, `[services].system` / `.user` /
`.disabled`, and `[[wants]]` (`scope`, `target`, `units`) for a unit linked
into one target instead of enabled globally. `build/scripts/read-packages` is
the reader and `build/scripts/package-lib.sh` holds the `install_*`,
`remove_*`, `assert_*` and `enable_*` helpers.

Versions float: COPRs prune old builds within weeks, so a pin would break the
daily build. The CI boot test is the gate (doc/product.md R1).

## Enablement policy

Enable explicitly, never by applying presets, and never mask.

- `10-packages.sh` snapshots the base's enabled set to
  `/var/tmp/neptuno-units.before` before any package installs.
- `40-services.sh` is the only enablement pass, and writes a preset file with
  the same choices so a machine's first-boot preset run agrees with it.
- `90-cleanup.sh` runs `build/scripts/systemd-units check` against every
  manifest and fails if a unit is enabled that the snapshot and manifests do
  not name. That catches RPM scriptlets and overlay `.wants` symlinks.
- `systemctl preset-all`, a `/dev/null` mask and a build-time `systemctl
  enable` outside a manifest each bypass that audit; disable through
  `[services].disabled` instead.

## Consumption rules that are easy to get wrong

- **Flathub**: ship the pinned `/etc/flatpak/remotes.d/flathub.flatpakrepo`
  descriptor (`20-overlay.sh` fetches and hashes it). A build-time
  `flatpak remote-add` writes to `/var`, which cleanup deletes, so the image
  would ship with no remote.
- **ghostty comes from `duxlabs/dux-repo`**: Fedora doesn't package it and
  the `scottames/ghostty` COPR stops at Fedora 44. dux-repo also rebuilds
  Fedora packages (greetd, cava, quickshell, xwayland-satellite), which is
  why each COPR section is limited to the names it lists plus `.deps`.
- **The system comes first on PATH**: nix-core's `nix-daemon.sh` and
  `nix.fish` prepend the Nix profiles; `60-nix.conf` appends them instead, and
  `/etc/profile.d/zz-neptuno-nix.sh` and `zz-neptuno.fish` move them back
  after `/usr/bin`. Otherwise `nx add clang` replaces `/usr/bin/cc` and `ld`,
  binaries link against Nix's glibc, and anything that loads the host's Mesa
  (Bevy, wgpu) finds no Vulkan driver. Compilers belong in `devlibs.toml`, and
  nothing links against `~/.nix-profile/lib`: build against `-devel` RPMs or
  the devbox.
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
  `zz-neptuno.fish` so their `command -q` guards see them and the PATH move
  runs after nix.fish; a bats test pins the order. Fish sources vendor dirs
  one directory at a time, so testing a copy through `XDG_DATA_DIRS` runs it
  before `/usr/share`'s nix.fish unless nix.fish is copied alongside it.
- **Rebasing a machine from the Bluefin-era image** (the laptop, 2026-11-16):
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

`just lint check test-unit`, then `just build rechunk test-image` for
anything that changes the image. Contract tests that read a path take a
sandbox root (`CLEAN_ROOT`, `UNIT_ROOT`, a temporary `TEST_ROOT`): an assert
on an absolute host path passes on a Neptuno host and fails in CI. The
manifest contract is `tests/contract/manifests_test.bats`; overlay
promises (nx, fish order, PAM, env) are in `tests/contract/system-files_test.bats`.
