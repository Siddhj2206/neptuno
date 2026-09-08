---
name: finpilot-examples
description: >-
  Index of runnable example scripts and the activation pattern. Covers
  existing .example files and how to activate them.
  Use when adding new build scripts or explaining the activation pattern to
  contributors.
---

# finpilot Example Scripts

## When to Use

- You need to add a third-party repository or desktop swap
- You want to understand the `.example` → `.sh` activation pattern
- You are creating a new build script and want a starting point
- You need to document a new pattern for contributors

## When NOT to Use

- You are modifying existing active `.sh` scripts directly — edit them, don't activate an example
- You are adding a simple package — use `build/10-build.sh` directly, no example needed

## Core Process

1. **Find the relevant example** in `build/` directory
2. **Copy and rename** from `.example` to `.sh`
3. **Add its explicit `RUN` block** after `10-build.sh` in `Containerfile`
4. **Customize** for your specific use case
5. **Validate** with `shellcheck` and `just build`
6. **Commit** (via PR to `main`)

## The Activation Pattern

All example scripts in `build/` follow the pattern:

1. **Inactive**: Named `NN-descriptive-name.sh.example`
2. **Activate the file**: Rename to `NN-descriptive-name.sh`
3. **Activate execution**: Add an explicit `RUN` block after `10-build.sh` in `Containerfile`

The template does not automatically discover numbered scripts. See `build/README.md` for the standard mounted `RUN` block; replace its script path with the activated example.

## Existing Example Scripts

No `.example` files ship in `build/` — every layer is live. The reference
implementation for a new layer is `build/40-niri.sh` + `build/packages/niri.toml`:
a `40-<name>.sh` script consuming a TOML manifest via `package-lib.sh`
helpers, wired by one explicit Containerfile `RUN` block. The 45-dx.sh
docker-ce pattern is the reference for third-party repos.

---

## Creating New Example Scripts

When adding a new pattern that others might reuse, create an `.example` file:

1. **Name it** with the correct prefix: `40-` for compositor/desktop layers, `45-` for dev-stack style extras
2. **Include comments** explaining what it does and how to customize
3. **Follow conventions**: `set -euo pipefail`, `dnf5`, TOML manifest + `package-lib.sh` helpers, `install_copr_sections` for COPRs
4. **Add the new example to this skill** so agents discover it

### Template for New Examples

```bash
#!/usr/bin/env bash
set -euo pipefail

# Description: [What this script does]
# Activate by: rename this file to build/NN-name.sh, then add its explicit
# RUN block after 10-build.sh in Containerfile (see build/README.md).
# Customize: [What to change]

# Example: Add a third-party repository
# dnf config-manager addrepo --from-repofile=https://example.com/repo.repo
# dnf5 install -y package-name
# rm -f /etc/yum.repos.d/example.repo  # Clean up repo file
```

## Validation by Example Type

| Example                      | Shellcheck | Build Test | Additional Validation                   |
| ---------------------------- | ---------- | ---------- | --------------------------------------- |
| Third-party repo (`45-*.sh`) | Yes        | Yes        | Verify repo URL accessible              |
| Desktop swap (`40-*.sh`)     | Yes        | Yes        | Test in VM (`just run-vm-qcow2`)        |
| COPR install (TOML section)  | Yes        | Yes        | Verify COPR exists and packages install |
| NVIDIA GPU (new `40-*.sh`)   | Yes        | Yes        | Test on NVIDIA hardware; verify `nvidia-smi` after boot |

## Link to Package Decision Tree

For deciding whether to add a new layer script or extend a `build/packages/*.toml` manifest, use `finpilot-packages`.

**Quick guide:**

- Simple system packages → `build/10-build.sh`
- Third-party repo or complex install → `build/20-*.sh` (activate an example or create new)
- Desktop environment swap → `build/30-*.sh` (activate an example or create new)

## Common Rationalizations

| Rationalization                                              | Reality                                                                                                  |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| "I'll just add my script directly — no need for an example." | If the pattern is reusable, an example helps future contributors. If it's one-off, add to `10-build.sh`. |
| "I'll leave it as `.example` and never rename it."           | `.example` files are inactive. Rename one to `.sh` and add its explicit Containerfile `RUN` block.       |
| "I renamed the example, so it will run."                      | The template runs only scripts explicitly named in Containerfile. Add the matching `RUN` block.           |

## Red Flags

- `.example` file modified but not renamed to `.sh`
- Renamed `.sh` file without a matching Containerfile `RUN` block
- New `.sh` file without `set -euo pipefail`
- Script using `dnf` or `yum` instead of `dnf5`
- COPR repo not disabled after install
- Third-party repo file not removed after install
- Missing shellcheck validation before committing

## Verification

- [ ] Did you rename the `.example` file to `.sh`?
- [ ] Did you add its `RUN` block after `10-build.sh` in Containerfile?
- [ ] Did you run `shellcheck` on the new `.sh` file?
- [ ] Did the build succeed with `just build`?
- [ ] For desktop swaps: did you test in a VM (`just run-vm-qcow2`)?
- [ ] For desktop swaps: did you verify the new session works at the login screen?
- [ ] Did you document the new pattern in `AGENTS.md` or this skill?
