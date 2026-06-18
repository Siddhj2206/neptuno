# finpilot Skills

Task-oriented agent skill files for the finpilot bootc image template ecosystem.

## Skill Index

| File | When to load |
|---|---|
| `finpilot-overview.md` | Orient to repo architecture, repo layout, and the skill routing table |
| `finpilot-onboarding.md` | Bootstrap a new fork: rename, Actions, token, first green build |
| `finpilot-packages.md` | Decide where a package goes: dnf5 (build-time) vs Brew vs Flatpak (runtime) |
| `finpilot-custom.md` | Edit Brewfiles, Flatpak preinstall files, or ujust commands |
| `finpilot-build.md` | Edit Containerfile, Justfile, build scripts, or debug local builds |
| `finpilot-ci.md` | Edit GitHub Actions workflows, Renovate config, or .hadolint.yaml |
| `finpilot-maintain.md` | Handle Renovate PRs, signing, or the local test loop |
| `finpilot-troubleshooting.md` | Debug build, CI, runtime, or Renovate failures |
| `finpilot-pr-checklist.md` | Open a PR: validation gates by change type, conventional commits |
| `finpilot-examples.md` | Follow runnable examples: third-party repos, desktop swaps, activation patterns |
| `finpilot-templates.md` | Initialize a fork, update rename locations, or configure signing |

## Quick Router

| I need to… | Load |
|---|---|
| Understand the repo | `finpilot-overview.md` |
| Bootstrap a fork | `finpilot-onboarding.md` |
| Add/remove a package | `finpilot-packages.md` |
| Change Brewfiles/Flatpaks/ujust | `finpilot-custom.md` |
| Change Containerfile/Justfile/build | `finpilot-build.md` |
| Fix CI or Renovate | `finpilot-ci.md` / `finpilot-maintain.md` |
| Open a PR | `finpilot-pr-checklist.md` |
| Debug a failure | `finpilot-troubleshooting.md` |
| See a worked example | `finpilot-examples.md` |
| Initialize/rename template | `finpilot-templates.md` |

## Extending Skills

- Each skill has YAML frontmatter (`name`, `description`, `metadata`)
- Add new skills by creating a file matching `finpilot-<topic>.md`
- Update the routing tables in `finpilot-overview.md` and `README.md`
