---
name: finpilot-build
description: >-
  Containerfile multi-stage build, image digest pinning in FROM lines,
  Justfile local build recipes, and build script conventions.
  Use when changing Containerfile, Justfile, or build/*.sh.
---

# finpilot Build System

## When to Use

- Editing `Containerfile` (ARGs, stages, base image, RUN directives)
- Editing `Justfile` (build recipe, tag strategy, version computation)
- Adding or modifying `build/*.sh` scripts
- Debugging why a local build fails differently from CI

## When NOT to Use

- CI workflow changes (`.github/workflows/`) — use `finpilot-ci`
- Runtime customizations (`custom/`) — use `finpilot-custom`

## Core Process

1. **Identify which `FROM` line or ARG drives your change**
2. **All image digests** are pinned directly in `Containerfile` `FROM` lines; Renovate updates them
3. **Run `just build`** locally before opening a PR; `just lint` to shellcheck
4. **Add `00-` prefix** for metadata scripts, `10-` for overlay/wiring, `20-` for base packages, `25-` for multimedia, `40-` for compositor, `45-` for dx; `clean-stage.sh` always last

## Image Pinning Pattern

All OCI images are pinned directly in `Containerfile` `FROM` lines. Renovate's
built-in `dockerfile` manager updates every digest.

```dockerfile
# OCI context images
FROM ghcr.io/projectbluefin/common:latest@sha256:<current> AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:<current> AS brew

# Base image (Hummingbird bootc-os — minimal F44-era bootc OS, no desktop)
ARG FEDORA_MAJOR_VERSION="44"
FROM quay.io/hummingbird-community/bootc-os:latest@sha256:<current>
```

**Never update digests manually.** Let Renovate open PRs for digest bumps.

To change an image or tag, edit its `FROM` line. To bump the Fedora major
release, update both the `FEDORA_MAJOR_VERSION` ARG and the base image tag.

## Build Script Conventions

### Numbering

| Prefix             | Purpose                                                                                                        |
| ------------------ | -------------------------------------------------------------------------------------------------------------- |
| `00-image-info.sh` | Metadata only: writes `image-info.json`, brands `os-release`                                                   |
| `10-build.sh`      | Overlay & wiring: OCI overlays (brew, common), `custom/` tree, skel — no `dnf` installs                        |
| `20-base.sh`       | WM-agnostic desktop foundation from `build/packages/base.toml` + `firmware.toml`                         |
| `25-multimedia.sh` | negativo17 multimedia + mesa overrides (versionlocked) from `build/packages/multimedia.toml`                   |
| `40-niri.sh`       | Compositor layer (niri + DMS, COPRs) from `build/packages/niri.toml`                                           |
| `45-dx.sh`         | Dev stack (docker-ce, adb, libvirt) from `build/packages/dx.toml`                                              |
| `clean-stage.sh`   | Always runs last: reverts `keepcache`, removes COPR repo files (keeps mesa versionlocks), disables fedora flatpak repo, clears artefacts |

### Manifest-driven package rules

- **Packages live in `build/packages/*.toml`** (manifest of record + post-install assert gate) — never `dnf5 install <name>` loose in a script. Consumer scripts call `install_fedora_section` / `install_copr_sections` from `build/scripts/package-lib.sh`.
- **tmux/gum ship via `base.toml`**: tmux smoke-tests that the DNF cache is warm, gum is required by the ujust recipes' interactive prompts. Do not remove.
- Always use `dnf5` — never `dnf`, `yum`, or `rpm-ostree`
- Always use `dnf5 install -y` (non-interactive)
- COPR: `install_copr_sections` enables → installs per `["copr:owner/project"]` section; `clean-stage.sh` removes all `_copr*.repo` files. Never ship an enabled COPR.

### Compositor / GPU layers

There is no NVIDIA layer and no `.example` scripts in `build/`. A new
layer (e.g. compositor swap, NVIDIA support) follows the established
pattern: `build/40-<name>.sh` + `build/packages/<name>.toml` + one explicit
Containerfile `RUN` block. See `40-niri.sh` + `niri.toml` as the reference.

### 00-image-info.sh branding

The comment in the `os-release` append block must use `${IMAGE_NAME}`:

```bash
cat >>"${OS_RELEASE}" <<EOF

# ${IMAGE_NAME} image identity   ← use variable, not literal "pluto"
VARIANT_ID="${IMAGE_NAME}"
...
EOF
```

## Base Image

Default: `quay.io/hummingbird-community/bootc-os:latest` (digest-pinned, rolling `:latest` — Renovate batches digest bumps)

The major version is controlled by the `FEDORA_MAJOR_VERSION` ARG and the `FROM` line in `Containerfile`. To bump Fedora releases:

1. Update `FEDORA_MAJOR_VERSION` and the `FROM` line in `Containerfile`
2. Update the Renovate rule that blocks major updates for the base image
3. Test with `just build` — expect `bootc container lint --fatal-warnings` to catch regressions

## Common Rationalizations

| Rationalization                                                      | Reality                                                                                                |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| "I'll skip the digest pin and use a floating tag."                   | Non-reproducible builds and breaks supply-chain traceability. The `FROM` line should always be pinned. |
| "Renovate won't notice a manually pinned digest in `Containerfile`." | Renovate's dockerfile manager tracks `FROM image:tag@sha256:...` in `Containerfile` automatically.     |
| "I'll add `dnf` as a fallback since dnf5 might not be installed."    | Never. `dnf5` is the canonical tool. Using `dnf` or `rpm-ostree` diverges from Bluefin.                |

## Red Flags

- Floating tags (`FROM image:latest` without `@sha256:...`)
- `FROM ${FOO}@${BAR}` where `BAR` could be empty
- `dnf`, `yum`, or `rpm-ostree` in any build script
- COPR repo files surviving `clean-stage.sh` (missing `_copr*.repo` removal)
- `# pluto image identity` hardcoded instead of `# ${IMAGE_NAME} image identity`

## Verification

- [ ] Are all `FROM` lines pinned with `@sha256:...`?
- [ ] Does `build/00-image-info.sh` use `${IMAGE_NAME}` in the os-release comment?
- [ ] Does `just build` succeed locally?
- [ ] Does `just lint` pass clean (shellcheck)?
- [ ] Does `bootc container lint --fatal-warnings` pass in CI?
