# Repository Setup Checklist

## Initial Setup

### 1. Rename Template

- [ ] Update `finpilot` to your name in **7 files** (use the `finpilot-templates` skill):
  1. `Containerfile` — `ARG IMAGE_NAME` and `ARG IMAGE_VENDOR`
  2. `Justfile` — `export IMAGE_NAME`
  3. `README.md` — title
  4. `artifacthub-repo.yml` — `repositoryID`
  5. `custom/ujust/README.md` — bootc switch example
  6. `.github/workflows/clean.yml` — `packages`
  7. `iso/iso.toml` — bootc switch URL

**Agent skills:** `finpilot-templates` (rename rules), `finpilot-onboarding` (fork bootstrap)

### 2. Enable GitHub Actions

- [ ] Settings → Actions → General → Enable workflows
- [ ] Set "Read and write permissions"

### 3. Configure the Release Branch

`main` is the only release branch and publishes the `:stable` image tag.
Configure branch protection for `main` to require the validation checks that
fit your repository.

### 4. First Push

```bash
git add .
git commit -m "feat: initial customization

Assisted-by: <Model> via <Tool>"
git push origin main
```

### 5. Enable Renovate (Required)

- [ ] Create a **Classic PAT** (Settings → Developer settings → Personal access tokens → Tokens (classic))
  - Scopes: `repo` (full control) + `workflow` (update workflows). The `repo`
    scope also grants Renovate access to repository vulnerability alerts.
  - If using a fine-grained token instead, grant repository access plus
    **Dependabot alerts: Read-only** and **Contents: Read and write**.
- [ ] Add the token as repository secret **`RENOVATE_TOKEN`** (Settings → Secrets and variables → Actions)
- [ ] Enable **Settings → General → Pull Requests → Allow auto-merge**
- [ ] Configure branch protection for `main`:
  - Settings → Branches → Add rule
  - Set **Branch name pattern** to `main`
  - Enable "Require a pull request before merging"
  - Enable "Require status checks to pass before merging"
  - Add `validate` as a required status check
  - Enable "Require branches to be up to date before merging"
- [ ] Renovate will create a PR to pin your GitHub Actions to SHAs

Renovate targets `main`.

**Agent skills:** `finpilot-onboarding` (branch protection), `finpilot-ci` (Renovate config)

### 6. Add "What Makes this Raptor Different" to README

- [ ] Open `README.md`
- [ ] Paste the raptor section template (see README or use the `finpilot-onboarding` skill)
- [ ] Fill in placeholders with your planned customizations
- [ ] Update the `*Last updated: [date]*` timestamp

**Agent skills:** `finpilot-onboarding` (raptor section), `finpilot-maintain` (maintenance requirement)

### 7. Participate in finpilot maintenance
- [ ] Use [finpilot issues](https://github.com/projectbluefin/finpilot/issues/new/choose)
  for reusable template or build-system improvements.
- [ ] Select the Clanker opt-in only on issues you create to send them to
  `3-clanker-queue`; maintainers may also apply that label.
- [ ] Port structural template changes to this repository through a focused PR.
  Renovate manages dependencies only; it does not synchronize arbitrary
  template files.

### 8. Deploy

After a successful `main` build, deploy the published image:
```bash
sudo bootc switch --transport registry ghcr.io/YOUR_USERNAME/YOUR_REPO:stable
sudo systemctl reboot
```

## Optional: Production Features

### Verify Image Signing (Enabled by Default)

Images are signed automatically with keyless OIDC signing — no keys or
secrets to configure. After the first green build, verify the signature:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/YOUR_REPO/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/YOUR_USERNAME/YOUR_REPO:stable
```

To disable signing (not recommended), comment out the `Sign and publish`
step in `.github/workflows/build-image.yml`.

**Agent skill:** `finpilot-templates` (signing verification)

### Enable Rechunking (Optional)

- [ ] Edit `.github/workflows/build-image.yml`
- [ ] Set `ENABLE_RECHUNKING: "true"`
- [ ] Keep the default `RECHUNK_MAX_LAYERS: "128"` unless you have measured a reason to change it
- [ ] Confirm a publish build completes before deploying the new image

The current OCI-native chunkah action does not use `/usr/libexec/bootc-base-imagectl`. Package cadence classification is a separate advanced setup and is not required for basic rechunking.

**Agent skill:** `finpilot-ci` (rechunking compatibility and workflow setup)

## Agent Handoff Reference

Which skill to load for each checklist block above:

| Checklist step                        | Skill                                       |
| ------------------------------------- | ------------------------------------------- |
| Rename (step 1)                       | `finpilot-templates`, `finpilot-onboarding` |
| Enable Actions (step 2)               | `finpilot-onboarding`                       |
| Branches + promotion (step 3)         | `finpilot-onboarding`, `finpilot-ci`        |
| Renovate + branch protection (step 5) | `finpilot-onboarding`, `finpilot-ci`        |
| Raptor section (step 6)               | `finpilot-onboarding`, `finpilot-maintain`  |
| Signing verification (default on)     | `finpilot-templates`                        |
| Rechunking (optional)                 | `finpilot-ci`                               |

**Cross-link requirement**: Whenever you add or remove a package, app, or service **after** initial setup, update the README raptor section and its `*Last updated*` date. This is required by the `finpilot-maintain` skill.
