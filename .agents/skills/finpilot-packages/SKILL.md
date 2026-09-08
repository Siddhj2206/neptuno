---
name: finpilot-packages
description: >-
  Decision tree for where to add packages in finpilot. Maps requests to the
  correct file and install method: build-time dnf5, runtime Brewfile, or
  runtime Flatpak. Use when deciding how to add a new package or tool.
---

# finpilot Package Decision Tree

## When to Use

- A user or agent asks "how do I add package X?"
- You need to decide whether a package belongs in build-time or runtime
- Reviewing a PR that adds packages and verifying they are in the right place
- Creating new build scripts or Brewfiles/Flatpak preinstall files

## When NOT to Use

- You already know the target file and install method — go edit it directly
- You are debugging why a package fails to install — use `finpilot-troubleshooting`

## Core Process

1. **Identify the package type** (system utility, CLI tool, GUI app, service)
2. **Use the decision table below** to map it to the correct path
3. **Apply the installation pattern** for that path
4. **Consider scope**: doc tasks (no CI impact) vs CI tasks (trigger validation/build)

## Decision Table

| Request                        | Action                                                        | Location                             |
| ------------------------------ | ------------------------------------------------------------- | ------------------------------------ |
| Add a system package (dnf5)    | Append to the layer manifest                                  | `build/packages/<layer>.toml` `[fedora]` |
| Add a COPR package             | Add a `["copr:owner/project"]` section to the layer manifest  | `build/packages/<layer>.toml`        |
| Add a third-party repo package | Enable repo → install → remove repo (45-dx.sh docker pattern) | Layer script + `[repo]` TOML section |
| Add a CLI tool (runtime)       | `brew "pkg"`                                                  | `custom/brew/default.Brewfile` (only Brewfile) |
| Add a GUI app                  | `[Flatpak Preinstall org.app.id]`                             | `custom/flatpaks/default.preinstall` |
| Add a user command             | Add a recipe (NO dnf5)                                        | `custom/ujust/custom-system.just`    |
| Enable a systemd service       | `systemctl enable service.name`                               | The layer's `build/<nn>-*.sh` script |
| Replace desktop environment    | New `40-<name>.sh` + `packages/<name>.toml` + Containerfile RUN block | `build/` (see 40-niri.sh) |
| Switch base image              | Update `FROM` line                                            | `Containerfile`                      |
| Add OCI containers             | Uncomment/add `COPY --from=`                                  | `Containerfile` ctx stage            |
| Add GPU support                | Same new-layer pattern (no `.example` scripts exist)          | `build/` (see 40-niri.sh)            |

## Build-Time: `build/packages/*.toml`

System packages are declared in TOML manifests (manifest of record) and
installed by the layer script in one transaction with a post-install
assert gate — the build FAILS on a missing name by design.

**Example:**

```toml
# In build/packages/base.toml
[fedora]
packages = [
    "wireguard-tools",
]
```

```bash
# In the layer script (e.g. build/20-base.sh)
install_fedora_section "${PKGS_TOML}" "base packages"
```

**When to use:**

- System utilities and services
- Dependencies required for other build-time operations
- Packages needed immediately on first boot
- Services that need `systemctl enable`

**Rules:**

- Always use `dnf5` (never `dnf`, `yum`, or `rpm-ostree`)
- Always use `-y` flag for non-interactive installs
- For COPR packages, add a `["copr:owner/project"]` section — `install_copr_sections` (in `build/scripts/package-lib.sh`) enables → installs; `clean-stage.sh` removes all COPR repo files
- One transaction per section for efficient layer caching

## COPR: `install_copr_sections`

Community repositories must not persist in the image.

**Example:**

```toml
# In build/packages/niri.toml
["copr:avengemedia/dms"]
packages = ["dms", "dms-cli"]
```

**What `install_copr_sections` does:**

1. Enables each `["copr:..."]` section's repo
2. Installs the section's package(s) with vendor/assert checks
3. Leaves removal to `clean-stage.sh` (`rm -f /etc/yum.repos.d/_copr*.repo`)

**Never ship an enabled COPR.**

## Verifying Package Sources

New packages are verified against the BUILD repos (Fedora proper + the
manifest's own COPR sections), NOT the host's repolist. The host can install
a same-named package from a COPR that is not enabled in the build — e.g.
`oversteer-udev` exists only in `copr:ublue-os/packages`; a "host-proven"
pick otherwise fails 20-base.sh with `No match for argument`. When a
host-proven package is missing from Fedora, find its real source with
`rpm -qi <pkg>` on the host — the Vendor/Packager fields name the COPR
(`Fedora Copr - user <owner>`).

**`dnf5 repoquery` exits 0 and prints NOTHING for names absent from the
enabled repos** — an empty result means "not found", never "verified".
Always repoquery-against-the-build-repos before adding a package, and spot
each vendor assertion (assert_vendor) for third-party installs.

**assert_vendor matches the raw `%{VENDOR}` field** — verify it on the host
before asserting (`rpm -q --qf '%{NAME} %{VENDOR}\n' <pkg>`), it is not
always the project name: docker-ce* report `Docker`, but `containerd.io`
reports an EMPTY vendor (containerd project packaging) and must be
presence-asserted instead (2026-08-29 build failure).

## Third-Party Repos: layer script + TOML section

For docker-ce style third-party repos, follow the 45-dx.sh pattern.

**Pattern:**

1. Add GPG key (if required)
2. Create repo file in `/etc/yum.repos.d/`
3. `dnf5 install -y` the package(s)
4. **CRITICAL**: Remove the repo file at end of script (unless the repo is an intentional exception like negativo17 multimedia, which stays enabled)

See `build/45-dx.sh` (docker-ce) for the complete working pattern.

## Runtime Brew: `custom/brew/*.Brewfile`

Homebrew is for CLI tools and development environments, installed by users
after first boot. File locations, syntax, and validation:
`finpilot-custom`.

## Runtime Flatpak: `custom/flatpaks/*.preinstall`

Flatpaks are for GUI apps, installed post-first-boot (not in the ISO or
container). INI syntax, `Branch=stable`, Flathub ID lookup, and validation:
`finpilot-custom`.

## Scope Rules

### Doc Tasks (No CI Impact)

README edits, comments, `.gitignore`, and `custom/ujust/README.md` trigger no CI.

### CI Tasks (Trigger Validation/Build)

Which `validate-*.yml` workflow fires for your file type — see the Workflow Map
in `finpilot-ci`.

## Common Rationalizations

| Rationalization                                                           | Reality                                                                                                                         |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| "I'll put this CLI tool in `build/10-build.sh` so it's always available." | Build-time packages bloat the image and slow updates. Runtime Brew is preferred for CLI tools that users can install on demand. |
| "I'll add a GUI app via dnf5 so it works offline."                        | Flatpaks are the standard for GUI apps. They update independently and avoid base image bloat.                                   |
| "COPR packages are safe to leave enabled."                                | Enabled COPRs persist and can cause conflicts on updates. Always use `copr_install_isolated`.                                   |
| "I'll just add the package to the example script and rename it later."    | Active `.sh` scripts run on every build. Only `.example` files are inactive. Rename carefully.                                  |

## Red Flags

- Using `dnf` or `yum` instead of `dnf5`
- Leaving a COPR enabled after install
- Not removing a third-party repo file after package install
- Adding GUI apps via `dnf5` instead of Flatpak
- Adding CLI tools to `build/10-build.sh` without considering runtime Brew first
- Modifying `build/*.example` files without renaming to `.sh`

## Verification

- [ ] Does the package type match the chosen installation method?
- [ ] For build-time: does it use `dnf5 install -y`?
- [ ] For COPR: is `copr_install_isolated` used?
- [ ] For third-party repo: is the repo file removed at end of script?
- [ ] For Flatpak: is the app ID verified on Flathub?
- [ ] For Brewfile: does `brew bundle check --file` pass locally?
- [ ] Does the changed path trigger the correct `validate-*.yml` workflow?
