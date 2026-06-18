---
name: finpilot-ci
description: >-
  GitHub Actions workflows, projectbluefin/actions composite actions,
  Renovate configuration, and PR validation for finpilot.
  Use when changing .github/workflows/, renovate.json, or .hadolint.yaml.
metadata:
  context7-sources: []
---

# finpilot CI

## When to Use

- Editing any `.github/workflows/*.yml`
- Editing `renovate.json`
- Adding new tooling to `build-image.yml`
- Debugging CI failures
- Deciding what to automerge vs require review

## When NOT to Use

- Containerfile / Justfile / build script changes — see `finpilot-build.md`
- Runtime customisations — see `finpilot-custom.md`

## Core Process

1. **Identify the workflow responsible** for your change (see table below)
2. **Check `projectbluefin/actions`** to confirm the composite action exists and what inputs it takes
3. **Pin any new tool** with a specific version + Renovate tracking comment
4. **Validate** locally: `actionlint .github/workflows/*.yml`
5. **Do not widen automerge scope** beyond `digest/pin/pinDigest` for the broad rule

## Workflow Map

| File | Trigger | Purpose |
|---|---|---|
| `build-image.yml` | push main, schedule (10:05 UTC), manual | Build + push `:stable` + rechunk + sign |
| `pr-validation.yml` | PR → main | shellcheck + hadolint + pre-commit via `validate-pr` |
| `renovate.yml` | schedule 6h, push renovate config | Self-hosted Renovate with token validation |
| `clean.yml` | schedule weekly | Delete GHCR images older than 90 days |
| `validate-brewfiles.yml` | PR paths: `custom/brew/**` | Homebrew Brewfile syntax check |
| `validate-flatpaks.yml` | PR paths: `custom/flatpaks/**` | Flathub app ID existence check |
| `validate-justfiles.yml` | PR paths: `Justfile`, `custom/ujust/**` | `just --list` syntax check |
| `validate-renovate.yml` | PR paths: `renovate.json` | `renovate-config-validator` |

## Composite Action Pins

All actions from `projectbluefin/actions` are pinned to a **commit SHA**:

```yaml
uses: projectbluefin/actions/bootc-build/setup-runner@6e0a29f20e504ff34df21952f15a0699ca8c82c7 # v1
```

**Never use a floating tag like `@v1` or `@main`.** Renovate updates the SHA automatically.
The comment (`# v1`) is for human readability only.

## Adding a New Tool

Always pin to a specific version with a Renovate tracking comment:

```yaml
- name: Install <tool>
  env:
    # renovate: datasource=github-releases depName=owner/repo
    TOOL_VERSION: "1.2.3"
  run: |
    sudo wget -qO /usr/local/bin/<tool> \
      "https://github.com/owner/repo/releases/download/v${TOOL_VERSION}/<tool>-linux-amd64"
    sudo chmod +x /usr/local/bin/<tool>
```

The `renovate.json` custom manager tracks this pattern. Never use `/releases/latest/`.

## Renovate Automerge Scope

### ✅ Safe to automerge broadly (digest/pin only)

```json
{
  "matchUpdateTypes": ["digest", "pin", "pinDigest"],
  "automerge": true
}
```

### ✅ Safe to automerge for trusted first-party actions

```json
{
  "matchPackageNames": ["projectbluefin/actions"],
  "matchUpdateTypes": ["digest", "pinDigest", "pin", "patch", "minor"],
  "automerge": true
}
```

### ❌ Do NOT automerge broadly for `minor`/`patch`

Minor and patch updates can change workflow behaviour or introduce regressions.

## Renovate OCI Digest Tracking

All OCI images in `Containerfile` `FROM` lines are tracked by Renovate's built-in
`dockerfile` manager. When Renovate updates a digest, it opens a PR that changes
only the relevant line. The next CI build uses it directly.

## Renovate Token Validation

The `renovate.yml` workflow includes a `Validate RENOVATE_TOKEN` step before
running Renovate, using the local `.github/actions/check-token-health` composite
action. If `RENOVATE_TOKEN` is missing, expired, or has wrong scopes, the workflow
fails before running Renovate.

## Image Signing

The `Sign and publish` step in `build-image.yml` is **already active**:
- Keyless OIDC mode via Cosign + Fulcio
- `continue-on-error: true` (non-fatal)
- SLSA Build L2 attestation attached
- Certificate identity regexp scoped to this repo's workflows

## Image Rechunking

The `Rechunk image` step in `build-image.yml` is **already active**:
- Uses `projectbluefin/actions/bootc-build/chunka`
- `max-layers: 128`
- Runs on non-PR builds on the default branch

## hadolint Config (.hadolint.yaml)

Suppressions are documented with reasons:

```yaml
ignore:
  - DL3006  # Commented-out alternative FROM lines use ARG interpolation
  - DL3059  # Multiple consecutive RUN — intentional design
  - SC2312  # Style preference — command substitution in conditions
```

Add suppressions sparingly. Document the reason inline.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll use `/releases/latest/` for now and pin it later." | You won't. Non-reproducible builds silently fail. Pin immediately. |
| "Minor/patch automerge is fine — it's just a template." | Images ship to users' machines. A bad automerge can break all forks. |
| "I don't need Renovate tracking for this one tool." | Unpinned tools silently break when upstream releases a breaking change. |

## Red Flags

- Tool installed via `/releases/latest/` without version pin
- Automerge rule includes `minor` or `patch` for all packages (unscoped)
- Composite action used with a floating tag (`@v1`, `@main`) instead of a SHA
- `GITHUB_TOKEN` used as the Renovate token (it cannot open PRs to other repos)
- `renovate.json` changed without running `renovate-config-validator`

## Verification

- [ ] Every `uses:` in workflows is pinned to a commit SHA with a version comment?
- [ ] Every new tool install has a pinned version + `# renovate: datasource=...` comment?
- [ ] Automerge broad rule is `digest/pin/pinDigest` only (not `minor`/`patch`)?
- [ ] `actionlint .github/workflows/*.yml` passes clean?
- [ ] `renovate-config-validator .github/renovate.json` passes clean?
- [ ] `RENOVATE_TOKEN` secret documented in SETUP_CHECKLIST.md?
