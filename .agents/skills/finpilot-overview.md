---
name: finpilot-overview
description: >-
  Architecture, repo layout, and factory role for the finpilot template.
  Use when orienting to the repository, understanding how it relates to
  projectbluefin/actions, or deciding which skill to read next.
metadata:
  context7-sources: []
---

# finpilot Overview

## When to Use

- Starting a new session in this repo
- Explaining how finpilot relates to bluefin/aurora/dakota
- Deciding which `.agents/skills/` file covers your change area
- Onboarding a new contributor or agent

## When NOT to Use

- You already know the area — go straight to the relevant skill file
- You need specific build or CI mechanics — see `finpilot-build.md` or `finpilot-ci.md`

## Core Process

1. **Read AGENTS.md `## Start here`** to find the routing table
2. **Identify your change area** (Containerfile/Justfile → build, workflows → ci, template init → templates)
3. **Read the relevant skill file** before touching anything
4. **Verify against current patterns** in `projectbluefin/actions` before deviating

## Architecture

finpilot is a **bootc image template** following the Bluefin multi-stage build architecture:

```
┌─────────────────────────────────────────────────────────────┐
│  Stage 1: ctx (FROM scratch)                                │
│    COPY build/  custom/                                    │
│    COPY --from=common  → /oci/common                        │
│    COPY --from=brew    → /oci/brew                          │
└─────────────────────────┬───────────────────────────────────┘
                          │ --mount=type=bind,from=ctx
┌─────────────────────────▼───────────────────────────────────┐
│  Stage 2: Final image                                       │
│    FROM quay.io/fedora-ostree-desktops/silverblue:44        │
│    RUN /ctx/build/00-image-info.sh   (metadata)             │
│    RUN /ctx/build/10-build.sh        (packages)             │
│    RUN /ctx/build/clean-stage.sh     (pre-lint cleanup)     │
│    RUN bootc container lint --fatal-warnings                │
└─────────────────────────────────────────────────────────────┘
```

## Repo Layout

```
├── Containerfile          # Multi-stage build definition (base + OCI context image pins)
├── Justfile               # Local build automation
├── build/                 # Build-time scripts (00-, 10-, 20-, 30-...)
│   ├── 00-image-info.sh   # image-info.json + os-release branding
│   ├── 10-build.sh        # Main package install script
│   └── clean-stage.sh     # Pre-lint artifact cleanup
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
└── .agents/skills/        # This directory
```

## Factory Role

finpilot is the **upstream template** for community custom images. It is not a factory
pipeline repo itself, but it adopts the same composite workflow actions as bluefin/dakota:

- CI uses `projectbluefin/actions/bootc-build/*` composite actions
- Renovate config extends `config:best-practices` and tracks OCI digests
- Image metadata (`image-info.json`) follows the ublue-os convention

## Skill Routing Table

| Change area | Read this skill |
|---|---|
| `Containerfile`, `Justfile` | `finpilot-build.md` |
| `.github/workflows/`, `.hadolint.yaml`, `renovate.json` | `finpilot-ci.md` |
| Template init, fork setup, AGENTS.md, README.md | `finpilot-templates.md` |
| `build/*.sh`, `custom/` | `finpilot-build.md` |

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "AGENTS.md has everything — no need to read skills." | AGENTS.md is for Copilot UX. Skills are the agent operating manual. |
| "It's just a template repo, not factory infra." | It ships workflow patterns to every fork. Mistakes multiply. |

## Red Flags

- Making Containerfile changes without reading `finpilot-build.md`
- Adding a workflow without verifying the `projectbluefin/actions` composite action exists
- Updating pinned `@sha256:...` digests in `Containerfile` manually instead of letting Renovate do it

## Verification

- [ ] Do I know which skill file covers my change area?
- [ ] Have I read that skill file?
- [ ] Does the change match current `projectbluefin/actions` patterns?
