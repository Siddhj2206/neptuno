---
name: finpilot-pr-checklist
description: >-
  PR preparation gates by change type: build scripts, workflows,
  packages, custom files, docs. Includes pre-commit checklist
  and conventional commit format.
  Use when opening a pull request.
metadata:
  context7-sources: []
---

# finpilot PR Checklist

## When to Use

- Opening a pull request with changes
- Preparing a commit
- Validating changes before pushing

## When NOT to Use

- Debugging a failure — see `finpilot-troubleshooting.md`
- Ongoing maintenance — see `finpilot-maintain.md`

## Pre-Commit Checklist

Run before EVERY commit:

- [ ] **Conventional Commits** — message follows `<type>(<scope>): <description>` format
- [ ] **Shellcheck** — `shellcheck build/steps/*.sh` passes clean
- [ ] **YAML validation** — `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` on all modified YAML
- [ ] **Justfile syntax** — `just --list` succeeds
- [ ] **No syntax errors** — never commit files with syntax errors
- [ ] **Confirm with user** — always confirm before committing and pushing

## Validation Gates by Change Type

### Build Script Changes (`build/steps/*.sh`)

- [ ] `shellcheck build/steps/*.sh` passes clean
- [ ] `set -euo pipefail` at top of every script
- [ ] No `dnf`, `yum`, or `rpm-ostree` — only `dnf5`
- [ ] COPRs use `copr_install_isolated` and are disabled after use
- [ ] New script registered in `build/build.sh` orchestrator

### Workflow Changes (`.github/workflows/*.yml`)

- [ ] `actionlint .github/workflows/*.yml` passes clean
- [ ] Every `uses:` pinned to commit SHA with version comment
- [ ] Every new tool install has pinned version + renovate tracking comment
- [ ] No floating tags (`@v1`, `@main`) in `uses:`
- [ ] `renovate-config-validator .github/renovate.json` if renovate.json changed

### Brewfile Changes (`custom/brew/*.Brewfile`)

- [ ] `brew bundle check --file custom/brew/default.Brewfile` passes
- [ ] Ruby syntax is valid
- [ ] Packages exist on Homebrew

### Flatpak Changes (`custom/flatpaks/*.preinstall`)

- [ ] App ID validated on Flathub (`flatpak search APP_ID`)
- [ ] INI format correct (`[Flatpak Preinstall APP_ID]`)
- [ ] `Branch=stable` specified

### ujust Changes (`custom/ujust/*.just`)

- [ ] `just --unstable --fmt --check -f custom/ujust/<file>.just` passes
- [ ] No `dnf5` in any ujust recipe
- [ ] `[group('Category')]` header present

### Containerfile or Justfile Changes

- [ ] `just build` succeeds locally
- [ ] `just lint` passes

### README or Documentation Changes

- [ ] "What Makes neptuno Different?" section updated if packages changed
- [ ] Last updated date bumped

## Conventional Commit Format

```
<type>(<scope>): <description>
```

| Type | When to use |
|---|---|
| `feat` | New feature, package, or capability |
| `fix` | Bug fix or correction |
| `docs` | Documentation changes |
| `build` | Containerfile, build script changes |
| `ci` | Workflow, Renovate config changes |
| `chore` | Maintenance, dependency updates |
| `refactor` | Code restructuring, no behavior change |

Examples:
```
feat(packages): add vim and htop to base image
ci(workflow): enable signing for stable builds
docs: update What's Different section
fix(build): disable COPR after package install
```

## Attribution Footer

All commits from AI agents must include:

```text
Assisted-by: [Model Name] via [Tool Name]
```
