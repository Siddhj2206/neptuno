---
name: finpilot-overview
description: >-
  Architecture, repo layout, and factory role for the finpilot template.
  Use when orienting to the repository, understanding how it relates to
  projectbluefin/actions, or before picking a skill with finpilot-router.
---

# finpilot Overview

## When to Use

- Starting a new session in this repo
- Explaining how finpilot relates to bluefin/aurora/dakota
- Orienting before using `finpilot-router` to pick a skill
- Onboarding a new contributor or agent

## When NOT to Use

- You already know the area — use the relevant skill directly
- You need specific build or CI mechanics — use `finpilot-build` or `finpilot-ci`

## Core Process

1. **Read AGENTS.md `## Start here`** for repository-wide rules and the skill sequence
2. **Identify your change area** (Containerfile/Justfile → build, workflows → ci, template init → templates)
3. **Load the relevant skill** before touching anything
4. **Verify against current patterns** in `projectbluefin/actions` before deviating

## Architecture

finpilot is a **bootc image** following the Bluefin multi-stage build architecture,
customised here for a Hummingbird base + niri/DMS desktop:

```
┌─────────────────────────────────────────────────────────────┐
│  Stage 1: ctx (FROM scratch)                                │
│    COPY build/  custom/                                     │
│    COPY --from=common  → /oci/common                        │
│    COPY --from=brew    → /oci/brew                          │
└─────────────────────────┬───────────────────────────────────┘
                          │ --mount=type=bind,from=ctx
┌─────────────────────────▼───────────────────────────────────┐
│  Stage 2: Final image                                       │
│    FROM quay.io/hummingbird-community/bootc-os:latest       │
│    RUN /ctx/build/00-image-info.sh   (metadata)             │
│    RUN /ctx/build/10-build.sh        (overlays + wiring)    │
│    RUN /ctx/build/20-base.sh         (base packages)        │
│    RUN /ctx/build/25-multimedia.sh   (multimedia)           │
│    RUN /ctx/build/40-niri.sh         (compositor)           │
│    RUN /ctx/build/45-dx.sh           (dev stack)            │
│    RUN /ctx/build/clean-stage.sh     (pre-lint cleanup)     │
│    RUN bootc container lint --fatal-warnings                │
└─────────────────────────────────────────────────────────────┘
```

## Repo Layout

```
├── Containerfile          # Multi-stage build definition (base + OCI context image pins)
├── Justfile               # Local build automation
├── build/                 # Build-time scripts (00/10/20/25/40/45 + clean)
│   ├── 00-image-info.sh   # image-info.json + os-release branding
│   ├── 10-build.sh        # OCI overlays + custom tree wiring (no dnf)
│   ├── 20-base.sh         # WM-agnostic base packages (base.toml)
│   ├── 25-multimedia.sh   # negativo17 multimedia (multimedia.toml)
│   ├── 40-niri.sh         # Compositor layer (niri.toml)
│   ├── 45-dx.sh           # Dev stack (dx.toml)
│   ├── packages/          # TOML manifests of record (one per layer)
│   ├── scripts/           # package-lib.sh + read-packages helpers
│   └── clean-stage.sh     # Pre-lint artifact cleanup (disables COPRs)
├── custom/                # Runtime: brew/, flatpaks/, ujust/
├── .github/
│   ├── workflows/
│   │   ├── build-image.yml      # Main CI build via projectbluefin/actions
│   │   ├── pr-validation.yml    # Consolidated PR checks
│   │   ├── renovate.yml         # Self-hosted Renovate runner
│   │   └── validate-*.yml       # Per-tool validation workflows
│   ├── actions/
│   │   └── check-token-health/  # PAT validation composite action
│   └── renovate.json            # Renovate config (OCI digests, GH Actions)
└── .agents/skills/        # Discoverable <skill-name>/SKILL.md directories
```

## Factory Role

finpilot is the **upstream template** for community custom images. It is not a factory
pipeline repo itself, but it adopts the same composite workflow actions as bluefin/dakota:

- CI uses `projectbluefin/actions/bootc-build/*` composite actions
- Renovate config extends `config:best-practices` and tracks OCI digests
- Image metadata (`image-info.json`) follows the ublue-os convention
- The label-enforcement workflow maintains the shared seven-label lifecycle;
  an issue creator's form opt-in admits their new issue to
  `3-clanker-queue` for Hive-connected agents; maintainers may also set that
  label explicitly

## Task Router

The canonical task → skill routing table lives in the `finpilot-router` skill —
load it when you don't know which skill covers a task.

## Scope Rules

To keep changes minimal and safe:

- **Doc tasks** (README, Agent Skills) → No CI impact, free to edit
- **CI tasks** (`.github/workflows/`, `renovate.json`) → Trigger `pr-validation.yml`, must pass `actionlint` and `renovate-config-validator`
- **Build tasks** (`Containerfile`, `build/`, `Justfile`) → Trigger full build, must pass `hadolint` + `shellcheck`
- **Runtime tasks** (`custom/`) → Trigger respective `validate-*.yml`

### Files to AVOID Modifying

**Do NOT modify unless specifically asked:**

- `.github/renovate.json` - Renovate configuration (auto-updates)
- `.github/workflows/renovate.yml` - Managed by projectbluefin/actions
- `.github/workflows/validate-*.yml` - Validation workflows
- `.gitignore` - Prevents committing secrets
- `build/scripts/package-lib.sh` - Shared install/assert helpers (stable API)
- `LICENSE` - Repository license

**Modify with extreme caution:**

- `.github/workflows/build-image.yml` - Core build workflow
- `Justfile` - Users rely on these commands

## Common Rationalizations

| Rationalization                                      | Reality                                                             |
| ---------------------------------------------------- | ------------------------------------------------------------------- |
| "AGENTS.md has everything — no need to use skills." | AGENTS.md holds global rules. Skills provide task-specific instructions. |
| "It's just a template repo, not factory infra."      | It ships workflow patterns to every fork. Mistakes multiply.        |

## Red Flags

- Making Containerfile changes without using `finpilot-build`
- Adding a workflow without verifying the `projectbluefin/actions` composite action exists
- Updating pinned `@sha256:...` digests in `Containerfile` manually instead of letting Renovate do it

## Verification

- [ ] Do I know which skill covers my change area?
- [ ] Have I loaded that skill?
- [ ] Does the change match current `projectbluefin/actions` patterns?
