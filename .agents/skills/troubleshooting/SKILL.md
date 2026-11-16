---
name: troubleshooting
description: >-
  Symptom to cause to fix for build, CI and runtime failures, plus the
  pre-pull-request checklist. Use when something is broken or before opening
  a pull request.
---

# Troubleshooting

## Before a pull request

- [ ] Conventional Commit message ending in the `Assisted-by:` line.
- [ ] `just lint check test-unit`.
- [ ] `just validate-flatpaks` if `flatpaks/` changed.
- [ ] `just build rechunk test-image` if the image changed.
- [ ] The owning skill updated if you learned something the hard way.

## Build

| Symptom | Cause | Fix |
|---|---|---|
| `bootc container lint` fails on a nonempty `/run` | a phase left files in `/run`, or a host `NOTIFY_SOCKET` was bind-mounted in | remove them in `90-cleanup.sh`; build through `just build`, which unsets the socket |
| the build fails in `90-cleanup.sh` naming a unit | something enabled a unit no manifest declares (often an RPM scriptlet) | declare it in `[services]`, or disable it in `[services].disabled` |
| a package is "not installed" after the transaction | a typo, or a runtime Recommends that weak deps (off) skipped | fix the name, or list the dependency explicitly |
| a COPR replaced a Fedora package | the COPR section did not limit what it may supply | list allowed extras under that section's `.deps` only |
| a COPR repo is live in the final image | Fedora 45 keeps repo files in `/usr/share/dnf5/repos.d` too | cleanup sweeps both directories; keep it that way |
| the package layer rebuilds on every overlay edit | a phase before `20-overlay.sh` reads `system_files/` | keep overlay work in `20-overlay.sh` or later |
| hadolint flags the Containerfile | a rule in `.github/hadolint.yaml` | fix it, or add a suppression with a reason |

## CI

| Symptom | Cause | Fix |
|---|---|---|
| a pull request never becomes mergeable | branch protection requires a check no workflow reports | require exactly `required` |
| `:latest` did not move after a green build | `publish` failed to sign or verify, by design | read the `publish` job; the digest stays on `:candidate` |
| a Renovate PR waits forever | auto-merge is off, or the update type is excluded | "Allow auto-merge" in settings; see the `ci` skill for which updates automerge |
| the boot test runs very slowly | the runner exposed no `/dev/kvm`, so it fell back to TCG | rerun; the step warns when this happens |

## Runtime

| Symptom | Cause | Fix |
|---|---|---|
| no Flatpaks yet after first boot | the preinstall runs 2 minutes after boot, only on AC power, and retries hourly until it succeeds | plug in, or `sudo systemctl start neptuno-flatpak-preinstall` |
| an app reports its saved secrets missing | the keyring was unlocked by fingerprint, so `pam_oo7` got no password | log in with the password; see PAM in the `neptuno` skill |
| a system file shows the old image's version after `bootc switch` | ostree kept a locally modified `/etc` file | `sudo ostree admin config-diff`, then restore the file from `/usr/etc` |
| a Nix-built binary stops starting after `nx clean` | it was linked by Nix's toolchain against a store glibc that was collected | rebuild it |
| `nx` itself misbehaves | nx is a separate project | fix it in Siddhj2206/nx and bump `NX_VERSION` |
