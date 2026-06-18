---
name: finpilot-troubleshooting
description: >-
  Symptom → cause → fix for build, CI, runtime, and Renovate failures.
  Use when debugging a failed build, CI job, or post-deploy issue.
metadata:
  context7-sources: []
---

# finpilot Troubleshooting

## When to Use

- A local `just build` fails
- A CI workflow (build-image, validate-*) fails
- An image doesn't boot or has missing features
- Renovate isn't creating PRs

## When NOT to Use

- Need to make a change — see the relevant skill file
- Need to open a PR — see `finpilot-pr-checklist.md`

## Local Build Failures

| Symptom | Cause | Fix |
|---|---|---|
| Build fails: "permission denied" | `GITHUB_TOKEN` secret not available locally | `export GITHUB_TOKEN=...` or skip the secret mount |
| Build fails: "package not found" | Typo or unavailable package | Check spelling, verify on RPMfusion, add COPR if needed |
| Build fails: "base image not found" | Invalid FROM line | Check syntax in `Containerfile` `FROM` line |
| Build fails: "shellcheck error" | Script syntax error | Run `shellcheck build/steps/*.sh` locally, fix errors |
| Build fails: "bootc container lint" | Image has issues | Check the lint output — usually a missing or misconfigured service |
| Build hangs | DNF cache corruption | `just clean && just build` |
| Build fails: "digest mismatch" | Renovate updated a FROM digest | Pull latest changes from main |

## CI Failures

| Symptom | Cause | Fix |
|---|---|---|
| PR validation fails: shellcheck | Script syntax error | Run `shellcheck build/steps/*.sh` locally |
| PR validation fails: Brewfile | Invalid Brewfile syntax | `brew bundle check --file custom/brew/default.Brewfile` |
| PR validation fails: Flatpak | Invalid app ID | Verify app ID exists on https://flathub.org/ |
| PR validation fails: justfile | Invalid just syntax | Run `just --unstable --fmt --check -f custom/ujust/<file>.just` |
| PR validation fails: hadolint | Containerfile lint error | Check the `DLxxxx` rule — fix or document suppression |
| Build CI fails: "no space left" | Runner disk full | Rerun the job |
| Build CI fails: timeout (360m) | Build takes too long | Check for large downloads or installs |
| Build CI succeeds but no image pushed | Wrong branch | Only main pushes images. Push via PR to main. |
| Sign and publish fails | OIDC token issue | Check `id-token: write` permission. Non-fatal step. |

## Runtime Failures

| Symptom | Cause | Fix |
|---|---|---|
| Image boots to blank screen | Desktop session not configured | Check systemd services, display manager configuration |
| ujust commands not found | Files not copied to image | Verify files in `custom/ujust/` and build copy logic |
| Flatpaks not installed after first boot | Expected behavior | Flatpaks install on first boot with internet. Takes 1-2 minutes. |
| Homebrew not found | Brew not installed yet | User must run `ujust install-default-apps` |
| Boot fails: "switch to new deployment" | bootc update issue | `bootc status && bootc upgrade` |
| Missing packages after update | COPR repo disabled | COPR packages don't persist on next build. Use dnf5 for base packages. |

## Renovate Failures

| Symptom | Cause | Fix |
|---|---|---|
| Renovate not creating PRs | `RENOVATE_TOKEN` expired or missing | Regenerate Classic PAT with `repo` + `workflow` scopes |
| Renovate creates PRs but they fail | Incompatible update | Check CI logs — close PR and investigate |
| Renovate PR closes without merging | Automerge disabled or branch protection blocks | Enable auto-merge, check branch protection settings |
| Renovate workflow fails at "Validate RENOVATE_TOKEN" | Token has wrong scopes | Regenerate token with correct scopes |
| Renovate workflow fails at "Run Renovate" | Rate limiting or network issue | Rerun the workflow |

## Diagnostic Commands

```bash
# Image info
bootc status

# Check running services
systemctl list-units --failed

# Check logs
journalctl -b -p err

# Signing verification
cosign verify \
  --certificate-identity-regexp="https://github.com/siddhj2206/neptuno/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/siddhj2206/neptuno:stable

# Local build debug
just build
just lint
shellcheck build/steps/*.sh

# Workflow validation
actionlint .github/workflows/*.yml

# Renovate config validation
renovate-config-validator .github/renovate.json
```
