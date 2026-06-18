# Repository Setup Checklist

## Initial Setup

### 1. Fork from finpilot Template
- [ ] Click "Use this template" on `projectbluefin/finpilot`
- [ ] Name your repository and create

### 2. Rename in 7 Locations
Update `finpilot` → your image name in:
- [ ] `Containerfile` (`ARG IMAGE_NAME`, `ARG IMAGE_VENDOR`, `# Name:` comment)
- [ ] `Justfile` (`export IMAGE_NAME`, `export REPO_ORG`)
- [ ] `README.md` (title)
- [ ] `artifacthub-repo.yml` (`repositoryID`)
- [ ] `custom/ujust/README.md` (bootc switch example)
- [ ] `.github/workflows/clean.yml` (`packages`)
- [ ] `.agents/skills/finpilot-templates.md` (rename locations table)

### 3. Enable GitHub Actions
- [ ] Settings → Actions → General → Enable workflows

### 4. Add RENOVATE_TOKEN (Required)
- [ ] Create a **Classic PAT** (Settings → Developer settings → Personal access tokens → Tokens (classic))
  - Scopes: `repo` (full control) + `workflow` (update workflows)
- [ ] Add as repository secret **`RENOVATE_TOKEN`** (Settings → Secrets and variables → Actions)
- [ ] Enable **Settings → General → Pull Requests → Allow auto-merge**
- [ ] Configure branch protection for `main`:
  - Settings → Branches → Add branch protection rule
  - **Branch name pattern**: `main`
  - **Require a pull request before merging** ✅
  - **Require status checks to pass before merging** ✅
  - Add `validate` as required status check
  - **Require branches to be up to date** ✅

### 5. First Build
- [ ] Push any commit to `main` — build starts automatically
- [ ] Wait for green check on `build-image.yml` workflow

### 6. Deploy
```bash
sudo bootc switch --transport registry ghcr.io/YOUR_USERNAME/YOUR_REPO:stable
sudo systemctl reboot
```

## Production Features

Signing and rechunking are **already enabled** in this fork:
- [ ] Verify `Sign and publish` step is active in `build-image.yml`
- [ ] Verify `Rechunk image` step is active in `build-image.yml`
- [ ] Verify with: `cosign verify --certificate-identity-regexp="https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/" --certificate-oidc-issuer="https://token.actions.githubusercontent.com" ghcr.io/YOUR_ORG/YOUR_REPO:stable`
