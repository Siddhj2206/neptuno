---
name: finpilot-troubleshooting
description: >-
  Consolidated symptom-cause-fix table for finpilot. Covers local build failures,
  CI failures, runtime issues, Renovate problems, COPR persistence, and ujust
  command not found. Use when something is broken and you need a quick diagnosis.
---

# finpilot Troubleshooting

## When to Use

- A local build fails and you need to diagnose the cause
- CI is failing on a PR and the error is unclear
- A runtime issue appears after deployment (missing packages, failed services)
- Renovate is not creating PRs or is failing
- A COPR repo seems to persist across builds
- A `ujust` command is not found or not working

## When NOT to Use

- You are still setting up the fork for the first time — use `finpilot-onboarding`
- You are deciding where to add a package — use `finpilot-packages`
- You need to plan ongoing maintenance — use `finpilot-maintain`

## Core Process

1. **Identify the symptom** from the tables below
2. **Check the likely cause**
3. **Apply the solution**
4. **Verify the fix**

## Local Build Failures

| Symptom                                | Cause                                                            | Solution                                                                         |
| -------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Build fails: "permission denied"       | Signing misconfigured or `id-token: write` permission missing    | Verify `id-token: write` and `attestations: write` are granted in the workflow   |
| Build fails: "package not found"       | Typo in package name, or package unavailable in configured repos | Check spelling, verify on RPMfusion, add COPR if needed                          |
| Build fails at STEP 9: "Status code: 404 for https://fedoraproject.org/static/RPM-GPG-KEY-fedora-…-primary" | Fedora no longer serves per-release key files on static.fedoraproject.org, and the Hummingbird base's rpmdb only inherited the F43 key (fork era) — dnf5 fetches the gpgkey URL whenever a package is signed by a key absent from the rpmdb | STEP 9 bootstraps `fedora-gpg-keys` with `--nogpgcheck` (chicken-egg, mkosi pattern); repo files use `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-primary` — keys come from the distro package, ARG bump only |
| Build fails: "base image not found"    | Invalid `FROM` line or digest mismatch                           | Check Containerfile syntax, verify base image tag and digest                     |
| Build fails: "shellcheck error"        | Script syntax error in `build/*.sh`                              | Run `shellcheck build/*.sh` locally, fix errors                                  |
| `bootc container lint` fails           | Missing cleanup, leftover artifacts, or invalid image structure  | Run `build/clean-stage.sh` manually, check for stray files in `/opt` or `/var`   |
| Podman/Docker not found                | Container runtime not installed                                  | Install `podman` or `docker`, ensure daemon is running                           |
| Base image pull fails                  | Network issue or invalid digest                                  | Verify network, check digest is correct, try `podman pull <base-image>` manually |
| Multi-stage build fails at `ctx` stage | Missing `COPY --from=` or invalid OCI image reference            | Verify OCI image names and digests in `Containerfile` ctx stage                  |
| `just build` fails immediately         | `just` not installed or `Justfile` syntax error                  | Run `just --list`, check `Justfile` for syntax errors                            |

## NVIDIA-Specific Issues

Pluto ships **no NVIDIA driver** (no NVIDIA layer, no `nvidia-smi`, nouveau
unblocked). On NVIDIA hardware the image runs on nouveau/mesa.

| Symptom                                    | Cause                                              | Solution                                                                                               |
| ------------------------------------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `nvidia-smi` not found after boot          | By design — no NVIDIA driver in the image          | No action; for proprietary-driver support a new `40-*.sh` layer is needed (see `finpilot-build`) |

## CI Failures

| Symptom                                                                 | Cause                                                                                                                                       | Solution                                                                                                                  |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| PR validation fails: shellcheck                                         | Syntax error in modified `.sh` file                                                                                                         | Run `shellcheck build/*.sh` locally, fix errors                                                                           |
| PR validation fails: hadolint                                           | Dockerfile lint rule violation                                                                                                              | Check `.hadolint.yaml` for allowed suppressions, fix or document new ones                                                 |
| PR validation fails: Brewfile                                           | Invalid Brewfile syntax                                                                                                                     | Check Ruby syntax, ensure packages exist (`brew search`)                                                                  |
| PR validation fails: Flatpak                                            | Invalid app ID                                                                                                                              | Verify app ID exists on https://flathub.org/                                                                              |
| PR validation fails: justfile                                           | Invalid just syntax                                                                                                                         | Run `just --list` locally to test, fix syntax                                                                             |
| CI build fails: workflow permissions                                    | Missing `id-token: write` or `packages: write`                                                                                              | Verify `.github/workflows/build-image.yml` has correct permissions                                                        |
| CI build fails: token health                                            | `RENOVATE_TOKEN` or `GITHUB_TOKEN` invalid/expired                                                                                          | Check token expiry, verify scopes, regenerate if needed                                                                   |
| CI build fails: signing misconfig                                       | OIDC token unavailable (self-hosted runner or restricted permissions)                                                                       | Verify `id-token: write` is granted and the runner supports OIDC; signing is `continue-on-error`, so builds still publish |
| CI build fails: composite action not found                              | Wrong commit SHA or repo name in `uses:`                                                                                                    | Verify `projectbluefin/actions` SHA, check network access                                                                 |
| CI build succeeds but image not published                               | Wrong `IMAGE_NAME` or `IMAGE_VENDOR`                                                                                                        | Check `Containerfile` ARGs, verify `clean.yml` package name matches                                                       |
| Promotion gate blocked: `release/blocked`, cosign "no signatures found" | Image pushed by an older template snapshot before signing was default, or the `Sign and publish` step failed silently (`continue-on-error`) | Merge a new build on `main` so a signed `:testing` image is published; check the build log's sign step for errors         |
| CI build fails: multimedia layer deadlock — `libdnf5-plugin-systemd-inhibit ... requires libfmt.so.12` vs `openal-soft`'s `libfmt.so.11` | Hummingbird pulp rolled a `dnf5-plugins` build whose weak deps now pull `libdnf5-plugin-systemd-inhibit` during the Containerfile STEP-10 bootstrap — `install_weak_deps=0` is configured only AFTER that install, so weak deps are ON for it (the base ships fmt 12, Fedora packages need fmt 11 → unsolvable) | Keep `--setopt=install_weak_deps=0` on the bootstrap install (the plugin is vestigial on bootc images). To compare builds: `gh run view <id> --log \| grep -A4 "Installing weak dependencies"` and diff transaction summaries |

## Runtime Issues

| Symptom                                 | Cause                                                       | Solution                                                                                                                        |
| --------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Flatpaks not installed                  | Expected behavior — they install post-first-boot            | Ensure internet connection on first boot, or run `ujust install-default-apps`                                                   |
| Brew missing or not found               | Homebrew not extracted yet or service failed | Run `systemctl status brew-setup.service`. Homebrew is extracted on first boot via systemd service, not user-installed. Check `/var/home/linuxbrew/.linuxbrew/bin/brew` |
| `bootc switch` fails                    | Wrong image URL or missing registry credentials             | Verify bootc switch URL matches your repo (see `iso/iso.toml`), check registry access                                           |
| `bootc switch` fails: "image not found" | Image not yet published to GHCR                             | Trigger a build on `main`, verify image appears under Packages                                                                  |
| Service not starting                    | Service not enabled or missing dependency                   | Check `systemctl status service.name`, verify `systemctl enable` in `build/10-build.sh`                                         |
| Missing package after boot              | Installed in wrong layer or runtime vs build-time confusion | Check if it's in `build/10-build.sh` (build-time) or `custom/brew/` (runtime)                                                   |
| `/opt` is not writable                  | `/opt` is symlinked to `/var/opt` by default                | In `Containerfile`, replace `RUN rm -rf /opt && ln -s /var/opt /opt` with `RUN rm /opt && mkdir /opt` if immutability is needed |

## Renovate Issues

| Symptom                       | Cause                                              | Solution                                                                   |
| ----------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------- |
| Renovate not creating PRs     | `RENOVATE_TOKEN` missing, expired, or wrong scopes | Verify token is Classic PAT with `repo` + `workflow`, regenerate if needed |
| Renovate PRs fail CI          | Renovate branch is out of date with `main`         | Rebase Renovate branch, or close and let Renovate recreate                 |
| Renovate updates wrong files  | Misconfigured `renovate.json`                      | Run `renovate-config-validator .github/renovate.json`, fix regex patterns  |
| Renovate creates too many PRs | Broad match in `renovate.json`                     | Scope `matchPackageNames` or `matchPaths` more narrowly                    |
| Renovate workflow times out   | Large number of repositories or heavy load         | Check Renovate logs, increase timeout, or run manually                     |

## COPR Persistence Issues

| Symptom                                 | Cause                                                         | Solution                                                                                      |
| --------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| COPR packages missing after boot        | COPRs disabled by clean-stage.sh (final image) before packages installed | COPRs install in build layers via `install_copr_sections` (`build/scripts/package-lib.sh`), whose assert gate fails the build if any package is missing; clean-stage.sh then removes the `copr:*.repo` files |
| COPR conflicts on update / install      | Multiple COPRs enabled sequentially pulled conflicting builds (e.g. a coprdep dragged in plain quickshell before quickshell-git) | `install_copr_sections` enables ALL COPR sections first, then installs every section's packages in ONE transaction — explicit args win over coprdep-pulled builds |
| `dnf5 copr list` shows unexpected repos | Repo files left over in the built image                       | Check `/etc/yum.repos.d/` in the final image — clean-stage.sh should have removed `copr:*.repo`; if not, the disable step is broken |

## ujust Command Not Found

| Symptom                                | Cause                                                           | Solution                                                                             |
| -------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `ujust` not found                      | `ujust` not in PATH, or shell not reloaded                      | Open a new terminal, or source shell profile (`source ~/.bashrc`)                    |
| `ujust --list` missing custom commands | `.just` files not copied during build                           | Verify `custom/ujust/*.just` files exist and are copied in `build/10-build.sh`       |
| `ujust my-command` fails               | Script error in `.just` file                                    | Run `just --list` to check syntax, or run the script block manually for error output |
| `ujust install-default-apps` fails     | Brew not installed or Brewfile path wrong                       | Verify brew is installed, check `BREWFILE` path in the just command                  |
| ujust on ISO vs installed system       | ujust commands may differ between live ISO and installed system | Ensure commands are designed for the target environment (ISO vs installed)           |

## Common Rationalizations

| Rationalization                                                   | Reality                                                                                                                                              |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| "The build failed in CI but works locally — it must be a CI bug." | CI is the source of truth. Local environments often have cached layers or different podman versions. Start with `just build` on a clean environment. |
| "Renovate is broken — it hasn't made a PR in days."               | Renovate runs on a schedule (default 6h). Check the workflow run logs before assuming failure.                                                       |
| "I don't need to run shellcheck locally — CI will catch it."      | Running `shellcheck` locally is faster and keeps CI queues free. It's a 5-second check.                                                              |
| "The COPR was disabled, so it can't be the problem."              | Repo files can persist in `/etc/yum.repos.d/` even if `copr` metadata is gone. Check the directory directly.                                         |
| "Fedora HTTPS gpgkey URLs work — the 43 build passes."             | The 43 build never fetches a key: the base's rpmdb inherited the F43 key from the fork era, so verification is local. Every per-release key URL (static.fedoraproject.org, dist-git, tree root) is dead — 44+ must use `fedora-gpg-keys` + `file://`. |
| "The build passed yesterday — upstream must be fine."              | The Hummingbird pulp repo is a **rolling `:latest`**: builds (dnf5-plugins, fmt, libdnf5) roll at any time and change weak-dep resolution or sonames mid-week. Same base digest + same trees ≠ same resolution — diff the two runs' transaction summaries before blaming CI or the local cache. |

## Red Flags

- Skipping local `just build` before opening a PR
- Ignoring CI failures because "it worked on my machine"
- Manually updating digests in `Containerfile` instead of using Renovate
- Leaving COPRs enabled after install
- Not verifying app IDs on Flathub before adding to `.preinstall`
- Pushing fixes directly to `main` instead of opening a PR

## Verification

- [ ] Did you identify the correct category (local, CI, runtime, Renovate, COPR, ujust)?
- [ ] Did you check the symptom-cause table for your specific error?
- [ ] Did you apply the recommended solution?
- [ ] Did you verify the fix by running the relevant test (build, just --list, etc.)?
- [ ] If the issue persists, did you check the workflow logs or run with verbose output (`--log-level=debug`)?
