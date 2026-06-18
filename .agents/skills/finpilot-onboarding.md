---
name: finpilot-onboarding
description: >-
  Fork bootstrap playbook: rename, enable Actions, add RENOVATE_TOKEN,
  branch protection, first green build, signing.
  Use when initializing a new fork of this template.
metadata:
  context7-sources: []
---

# finpilot Onboarding

## When to Use

- Creating a new custom image from this template
- Setting up a fork for the first time
- Enabling production features (signing, token validation)

## When NOT to Use

- Already have a green build — see `finpilot-maintain.md`
- Debugging a failed build — see `finpilot-troubleshooting.md`

## Core Process

1. **Create the fork via "Use this template"**
2. **Rename `finpilot` in 7 locations** (see `finpilot-templates.md`)
3. **Enable GitHub Actions** in the Actions tab
4. **Add `RENOVATE_TOKEN`** — Classic PAT with `repo` + `workflow` scopes
5. **Enable auto-merge** in Settings → General → Pull Requests
6. **Configure branch protection** for `main` with `validate` as required check
7. **Push a commit** to trigger the first build
8. **Wait for green** — check `build-image.yml` in Actions

## Fork Bootstrap Playbook

### Step 1: Create the Fork

Click "Use this template" on the GitHub repo page. Name your repository and
create it. Do not include all branches.

### Step 2: Rename

Follow `finpilot-templates.md` — there are exactly 7 files to update.
The most commonly missed is `.github/workflows/clean.yml`.

### Step 3: Enable Actions

1. Go to your repository's **Actions** tab
2. Click **"I understand my workflows, go ahead and enable them"**
3. No changes needed to workflow permissions (defaults are correct)

### Step 4: RENOVATE_TOKEN

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with `repo` (full control) and `workflow` scopes
3. Copy the token value
4. Repository → Settings → Secrets and variables → Actions
5. Add **`RENOVATE_TOKEN`** with the token value

### Step 5: Branch Protection

1. Repository → Settings → Branches → Add branch protection rule
2. Branch name pattern: `main`
3. Enable:
   - **Require a pull request before merging**
   - **Require status checks to pass before merging** → add `validate`
   - **Require branches to be up to date before merging** (recommended)

### Step 6: First Build

Push any commit to `main` (or run `build-image.yml` manually via Actions tab).
First build takes 30-60 minutes depending on package load.

### Step 7: Verify Signing

If signing was enabled in the template fork, verify after first push:
```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/YOUR_ORG/YOUR_REPO:stable
```

## Production Checklist

- [ ] Rename complete (7 locations verified)
- [ ] GitHub Actions enabled
- [ ] RENOVATE_TOKEN set and valid
- [ ] Auto-merge enabled
- [ ] Branch protection on `main` with `validate` check
- [ ] First build succeeded
- [ ] Image signed (if active)
- [ ] README.md "What Makes This Image Different?" section written
- [ ] Last updated date in AGENTS.md current
