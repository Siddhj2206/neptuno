---
name: finpilot-templates
description: >-
  Template initialization, fork setup, renaming conventions, and the
  seven files that must be updated when creating a new image from finpilot.
  Use when initializing a fork, updating AGENTS.md, or documenting setup.
metadata:
  context7-sources: []
---

# finpilot Templates & Fork Setup

## When to Use

- Initializing a new custom OS image from this template
- Updating AGENTS.md or copilot instructions
- Updating README.md setup sections or SETUP_CHECKLIST.md
- Documenting new mandatory setup steps for forks

## When NOT to Use

- Build system changes — see `finpilot-build.md`
- CI workflow changes — see `finpilot-ci.md`

## Core Process: Creating a New Fork

1. **Click "Use this template"** on GitHub → create new repository
2. **Rename `finpilot` in exactly 7 locations** (see table below)
3. **Enable GitHub Actions** in the Actions tab
4. **Add `RENOVATE_TOKEN` secret** (Classic PAT, `repo` + `workflow` scopes)
5. **Enable auto-merge** (Settings → General → Pull Requests → Allow auto-merge)
6. **Configure branch protection for `main`** with `validate` as required check
7. **Update README.md** with a "What Makes This Image Different?" section
8. **Trigger first build** — push any commit or run the workflow manually

## The Seven Rename Locations

When forking, change `finpilot` → your image name in exactly these locations:

| # | File | What to change |
|---|---|---|
| 1 | `Containerfile` | `# Name:` comment, `ARG IMAGE_NAME`, `ARG IMAGE_VENDOR` |
| 2 | `Justfile` | `export IMAGE_NAME := env("IMAGE_NAME", "finpilot")`, `export REPO_ORG := env(... "projectbluefin")` |
| 3 | `README.md` | Title `# finpilot` |
| 4 | `artifacthub-repo.yml` | `repositoryID: finpilot` |
| 5 | `custom/ujust/README.md` | `localhost/finpilot:stable` in the bootc switch example |
| 6 | `.github/workflows/clean.yml` | `packages: finpilot` |
| 7 | `.agents/skills/finpilot-templates.md` | Rename locations table (this file) |

Missing any of these causes the image to be published or cleaned up under the wrong name.

## Image Identity ARGs

```dockerfile
ARG IMAGE_NAME="finpilot"          # Your image's name
ARG IMAGE_VENDOR="projectbluefin"  # Your GitHub org/username
ARG UBLUE_IMAGE_TAG="stable"       # Stream name
ARG BASE_IMAGE_NAME="silverblue"   # Base image for image-info.json
```

These are consumed by `build/00-image-info.sh` to write:
- `/usr/share/ublue-os/image-info.json`
- `/usr/lib/os-release` branding fields

## Signing Setup (Keyless OIDC)

This template uses **keyless OIDC signing** via Cosign + Fulcio. No `cosign.key`,
`cosign.pub`, or `SIGNING_SECRET` are needed.

**In production forks**, signing may already be enabled (uncommented in `build-image.yml`).
Verify by checking the `Sign and publish` step. If it's commented, uncomment to enable:

1. Edit `.github/workflows/build-image.yml`
2. Find the `Sign and publish` step (it may already be active)
3. If commented: remove the `#` prefix

Users verify images with:
```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/YOUR_ORG/YOUR_REPO:stable
```

**Never** add a `cosign.pub` file with a placeholder. Static-key signing is not supported.

## AGENTS.md Update Rules

- **Line-number references are fragile** — use semantic references (`ARG IMAGE_NAME`, `FROM`) not line numbers
- **Keep the `## Start here` section pointing to the skills router table**
- **Update `Last Updated` date** on every substantive change
- **Do not add resolved items** (PR numbers, "✅ done" entries) — those belong in git history

## Adding Skills to a Fork

When customising for a fork, you may want to add new skill files or modify existing ones:
- Create new skills as `finpilot-<topic>.md` in `.agents/skills/`
- Update the router table in `finpilot-overview.md`
- Update the `## Start here` section in `AGENTS.md` if adding a high-traffic document

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I only need to rename it in the obvious places." | There are exactly 7 locations. Missing `clean.yml` or `templates.md` causes stale references. |
| "Keyless signing is complicated — I'll use static keys." | Keyless OIDC is simpler: no secrets, no key rotation. No static keys supported. |
| "I'll update AGENTS.md later once the build is working." | AGENTS.md drives Copilot behaviour on every session. Update it now. |

## Red Flags

- Fork repo still has `finpilot` in `clean.yml` (image cleanup targets wrong package)
- `cosign.pub` placeholder file added to a fork
- AGENTS.md referencing line numbers instead of semantic identifiers
- `## Start here` section removed or not pointing to skill files
- `RENOVATE_TOKEN` not set but Renovate workflow is enabled

## Verification

- [ ] All 7 rename locations updated?
- [ ] GitHub Actions enabled in the fork?
- [ ] `RENOVATE_TOKEN` secret added?
- [ ] Auto-merge enabled in repository settings?
- [ ] Branch protection for `main` configured with `validate` as required check?
- [ ] First build triggered and succeeded?
- [ ] `AGENTS.md` `Last Updated` date current?
