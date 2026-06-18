---
name: finpilot-maintain
description: >-
  Ongoing maintenance: Renovate PR handling, signing verification,
  local test loop, README raptor section updates, and keeping
  the image healthy.
  Use when responding to Renovate PRs or performing regular upkeep.
metadata:
  context7-sources: []
---

# finpilot Maintenance

## When to Use

- Reviewing or merging Renovate PRs
- Verifying image signing is working
- Running local test builds
- Updating the README "What Makes This Image Different?" section
- Adding new GitHub secrets or tokens

## When NOT to Use

- Opening a new PR with changes — see `finpilot-pr-checklist.md`
- Debugging a failed build — see `finpilot-troubleshooting.md`

## Core Process

1. **Check Renovate PRs** daily — most are safe-to-automerge digest bumps
2. **Review non-automerge PRs** (minor/patch base image changes) manually
3. **Run local test loop** before major changes
4. **Keep README updated** when packages change

## Renovate PR Handling

### Automerge (no action needed)

Renovate automatically merges these PR types:

| Update type | Scope | Auto-merge |
|---|---|---|
| Digest pin update | `projectbluefin/actions` | ✅ Yes |
| Digest pin update | Any dependency | ✅ Yes |
| Minor/patch | `projectbluefin/actions` | ✅ Yes |

These PRs merge as soon as `validate` passes. You may see them appear and
disappear quickly.

### Manual Review (you act)

| Update type | Scope | Action |
|---|---|---|
| Major version | `quay.io/fedora-ostree-desktops/silverblue` | Blocked (Renovate config) |
| Minor/patch | Any non-actions dependency | Review and approve |
| New major | Any dependency | Review carefully — may be breaking |

For manual review PRs:
1. Check the change is compatible
2. Look at CI status (must pass)
3. Approve and squash-merge

### Failed Renovate PRs

If a Renovate PR fails `validate`:
1. Check the failure reason (shellcheck, actionlint, etc.)
2. It may be a legitimate incompatibility — investigate
3. Close the PR, fix the issue, and Renovate will recreate

## Signing Health Check

This image uses keyless OIDC signing. Verify after each stable build:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/siddhj2206/neptuno/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/siddhj2206/neptuno:stable
```

If signing fails:
- Check `id-token: write` permission in workflow
- Check the `Sign and publish` step isn't commented out
- `continue-on-error: true` means CI won't fail — check logs manually

## Local Test Loop

```bash
# Full test cycle
just build
just build-qcow2
just run-vm-qcow2

# Quick check (lint only)
just lint
just check

# Test specific changes
just build && just build-qcow2
```

## README Raptor Section

Keep the "What Makes neptuno Different?" section in README.md current:

- Update **every time** you add/remove packages
- Keep explanations brief and user-focused (why, not just what)
- Update the `*Last updated:*` date
- Write for typical Linux users, not developers

## Token Health

- `RENOVATE_TOKEN` should be a Classic PAT with `repo` + `workflow` scopes
- If Renovate stops creating PRs, regenerate the token
- The `check-token-health` action validates scopes at workflow start

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Renovate automerges everything — I don't need to check." | Only digest/pin and projectbluefin/actions are auto-merged. Check the rest. |
| "Signing failed but CI passed — must be fine." | `continue-on-error: true` means signing failures are silent. Check manually. |
| "I'll update README when I have time." | Users depend on it. Update it with the change. |

## Red Flags

- Renovate PRs piling up without review
- `RENOVATE_TOKEN` expired (Renovate stops creating PRs)
- Signing verification fails after a successful build
- README "What's Different" section outdated

## Verification

- [ ] Renovate PRs reviewed or confirmed auto-merged this week?
- [ ] Signing verified on latest stable image?
- [ ] README "What Makes This Image Different?" section up to date?
- [ ] `RENOVATE_TOKEN` valid (Renovate creating PRs)?
