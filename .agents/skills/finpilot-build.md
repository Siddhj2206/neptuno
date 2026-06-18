---
name: finpilot-build
description: >-
  Containerfile multi-stage build, image digest pinning in FROM lines,
  Justfile local build recipes, and build script conventions.
  Use when changing Containerfile, Justfile, or build/*.sh/steps/*.sh.
metadata:
  context7-sources: []
---

# finpilot Build System

## When to Use

- Editing `Containerfile` (ARGs, stages, base image, RUN directives)
- Editing `Justfile` (build recipe, tag strategy, version computation)
- Adding or modifying `build/steps/*.sh` scripts
- Debugging why a local build fails differently from CI

## When NOT to Use

- CI workflow changes (`.github/workflows/`) — see `finpilot-ci.md`
- Runtime customizations (`custom/`) — see `finpilot-custom.md`

## Core Process

1. **Identify which `FROM` line or ARG drives your change**
2. **All image digests** are pinned directly in `Containerfile` `FROM` lines; Renovate updates them
3. **Run `just build`** locally before opening a PR; `just lint` to shellcheck
4. **Add step scripts** in `build/steps/` with numbered prefixes (`00-`, `10-`, `20+`)
5. **Register new step scripts** in `build/build.sh` orchestrator

## Image Pinning Pattern

All OCI images are pinned directly in `Containerfile` `FROM` lines. Renovate's
built-in `dockerfile` manager updates every digest:

```dockerfile
FROM ghcr.io/projectbluefin/common:latest@sha256:<current> AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:<current> AS brew
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:<current>
```

**Never update digests manually.** Let Renovate open PRs for digest bumps.

## Build Architecture

This fork uses a **single monolithic RUN layer** with an orchestrator script:

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/build.sh
```

`build/build.sh` invokes step scripts from `build/steps/` in numerical order.
This single-layer approach minimizes layer count and is the pattern used by
production forks for optimal OTA update deltas.

## Build Script Conventions

### Step Script Prefixes

| Prefix | Purpose |
|---|---|
| `00-image-info.sh` | Metadata only: writes `image-info.json`, customises `os-release` |
| `10-build.sh` | Main script: copies custom files, `dnf5 install`, enables services |
| `20-*.sh` | Feature-specific: DMS/Niri desktop, gaming, ASUS tooling, etc. |
| `clean-stage.sh` | Always runs last: reverts `keepcache`, disables fedora flatpak repo, clears artefacts |

### Rules

- Always use `dnf5` — never `dnf`, `yum`, or `rpm-ostree`
- Always use `dnf5 install -y` (non-interactive)
- COPR: enable → install → `copr_install_isolated` (auto-disables); never leave a repo enabled
- Any new `.sh` script in `build/steps/` must be called from `build/build.sh`

### 00-image-info.sh branding

The comment in the `os-release` append block must use `${IMAGE_NAME}`:

```bash
cat >> "${OS_RELEASE}" << EOF

# ${IMAGE_NAME} image identity
VARIANT_ID="${IMAGE_FLAVOR}"
EOF
```

## Base Image

Current: `quay.io/fedora-ostree-desktops/silverblue:44`

To bump Fedora releases:
1. Update `FEDORA_MAJOR_VERSION` ARG and the `FROM` line in `Containerfile`
2. Update the Renovate rule that blocks major updates for the base image
3. Test with `just build` — expect `bootc container lint --fatal-warnings` to catch regressions

## Image Signing

Signing is **already enabled** using keyless OIDC via Cosign + Fulcio:

- Step: `Sign and publish` in `.github/workflows/build-image.yml` (uncommented)
- Mode: `keyless` — no `cosign.key`, `cosign.pub`, or `SIGNING_SECRET` needed
- `continue-on-error: true` — signing failures never block image publishing

If forking from this template, signing is active by default.

## Rechunking

The `Rechunk image` step in `build-image.yml` is **already enabled**.
It uses `projectbluefin/actions/bootc-build/chunka` to reorganize OCI layers
for smaller OTA update deltas via `max-layers: 128`.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll skip the digest pin and use a floating tag." | Non-reproducible builds. Always pin. |
| "Renovate won't notice a manually pinned digest." | Renovate's dockerfile manager tracks `FROM image:tag@sha256:...` automatically. |
| "I'll add `dnf` as a fallback." | Never. `dnf5` is the canonical tool. |

## Red Flags

- Floating tags (`FROM image:latest` without `@sha256:...`)
- `dnf`, `yum`, or `rpm-ostree` in any build script
- COPR left enabled after package install
- `# finpilot image identity` hardcoded instead of `# ${IMAGE_NAME} image identity`
- New step script not registered in `build/build.sh`

## Verification

- [ ] Are all `FROM` lines pinned with `@sha256:...`?
- [ ] Does `build/00-image-info.sh` use `${IMAGE_NAME}` in the os-release comment?
- [ ] Does `just build` succeed locally?
- [ ] Does `just lint` pass clean (shellcheck)?
- [ ] Does `bootc container lint --fatal-warnings` pass in CI?
