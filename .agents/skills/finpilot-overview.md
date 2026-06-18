---
name: finpilot-overview
description: >-
  Architecture, repo layout, and task routing for the finpilot template.
  Use when orienting to the repository or deciding which skill to read next.
metadata:
  context7-sources: []
---

# finpilot Overview

## When to Use

- Starting a new session in this repo
- Understanding how finpilot relates to bluefin/aurora
- Deciding which `.agents/skills/` file covers your change area
- Onboarding a new contributor or agent

## When NOT to Use

- You already know the area — go straight to the relevant skill file
- You need specific build or CI mechanics — see `finpilot-build.md` or `finpilot-ci.md`

## Core Process

1. **Read AGENTS.md `## Start here`** to find the routing table
2. **Identify your change area** (Containerfile/Justfile → build, workflows → ci, etc.)
3. **Read the relevant skill file** before touching anything
4. **Verify against current patterns** in `projectbluefin/actions` before deviating

## Architecture

finpilot follows the **Bluefin multi-stage build architecture** from `@projectbluefin/distroless`:

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
│    FROM silverblue:44                                       │
│    RUN /ctx/build/build.sh         (orchestrator → steps/)  │
│    RUN bootc container lint --fatal-warnings                │
└─────────────────────────────────────────────────────────────┘
```

This template uses a **single monolithic RUN layer** with a `build.sh` orchestrator
that invokes step scripts in numerical order from `build/steps/`. This minimizes
layer count and follows the pattern used by production forks for optimal OTA updates.

## Repo Layout

```
├── Containerfile          # Multi-stage build (OCI context + base image pins)
├── Justfile               # Local build automation
├── build/
│   ├── build.sh           # Orchestrator — invokes steps/ in order
│   ├── steps/             # Build-time scripts (00-image-info, 10-build, etc.)
│   │   ├── 00-image-info.sh
│   │   ├── 10-build.sh
│   │   ├── 20-*.sh
│   │   ├── clean-stage.sh
│   │   └── copr-helpers.sh
│   └── README.md
├── custom/
│   ├── brew/              # Homebrew Brewfiles
│   ├── flatpaks/          # Flatpak preinstall files
│   ├── ujust/             # Custom ujust recipes
│   ├── config/            # User-specific config files (environment.d/, ghostty/, niri/)
│   └── files/             # System file overrides (etc/, usr/)
├── iso/                   # Local testing (disk.toml, iso.toml, rclone/)
├── .github/
│   ├── workflows/         # build-image, pr-validation, renovate, validate-*, clean
│   ├── actions/           # check-token-health composite action
│   ├── copilot-instructions.md
│   ├── SETUP_CHECKLIST.md
│   ├── commit-convention.md
│   └── renovate.json
└── .agents/skills/        # This directory
```

## Factory Role

finpilot is the **upstream template** for community custom images. Forks adopt:
- `projectbluefin/actions/bootc-build/*` composite actions
- `config:best-practices` Renovate config + OCI digest tracking
- ublue-os `image-info.json` convention

## Task Router

| Change area | Read this skill |
|---|---|
| Containerfile, Justfile, build.sh, steps/ | `finpilot-build.md` |
| .github/workflows/, renovate.json, .hadolint.yaml | `finpilot-ci.md` |
| Template init, fork setup, rename | `finpilot-templates.md` |
| New package decisions | `finpilot-packages.md` |
| Brewfiles, Flatpaks, ujust | `finpilot-custom.md` |
| Ongoing maintenance | `finpilot-maintain.md` |
| PR preparation | `finpilot-pr-checklist.md` |
| Debugging | `finpilot-troubleshooting.md` |
| Worked examples | `finpilot-examples.md` |
| Bootstrap a fork | `finpilot-onboarding.md` |

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "AGENTS.md has everything — no need to read skills." | AGENTS.md is the router. Skills are the operating manual. |
| "It's just a template repo, not factory infra." | It ships workflow patterns to every fork. Mistakes multiply. |

## Red Flags

- Making Containerfile changes without reading `finpilot-build.md`
- Adding a workflow without verifying the `projectbluefin/actions` composite action exists
- Updating pinned `@sha256:...` digests manually instead of letting Renovate do it

## Verification

- [ ] Do I know which skill file covers my change area?
- [ ] Have I read that skill file?
- [ ] Does the change match current `projectbluefin/actions` patterns?
