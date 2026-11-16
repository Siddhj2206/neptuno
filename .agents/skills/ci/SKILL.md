---
name: ci
description: >-
  GitHub Actions, Renovate, signing, tags, releases and GHCR retention. Use when
  changing a workflow, the dependency policy, or how an image is published.
---

# CI

Plain GitHub Actions on `ubuntu-26.04`; no `projectbluefin/actions`. Every
step CI runs on the image is a `just` recipe, so a red CI run reproduces
locally with the same command.

## Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `build.yml` | pull request, push to `main`, daily 05:17 UTC, dispatch | Static checks and a full image build + test on every run; on `main` also push, sign, verify, tag and write a release. |
| `clean.yml` | weekly, dispatch (dry run by default) | GHCR retention and release pruning. |

Renovate is the hosted Mend app (no workflow, no token).

### `build.yml` jobs

1. `changes`: on a pull request, classifies the changed files. Docs only
   (`*.md`, `doc/`, `.agents/`) skips the image build.
2. `static` (about 1 min, in parallel with `build`): `just lint`, `just check`,
   `just test-unit`, `just validate-flatpaks`, hadolint, actionlint, zizmor,
   and the Renovate validator when the config changed.
3. `build`: `just build` → `just rechunk` (chunkah, then `bootc container lint
   --fatal-warnings`) → `just test-image` (tests/image/check.sh) → `just
   test-boot` (bcvk ephemeral VM, KVM) → on `main` only, push by digest to
   `:candidate`.
4. `publish` (`main` only): `cosign sign`, then `cosign verify` against this
   exact workflow on `refs/heads/main`, then `skopeo copy --preserve-digests` to
   `:45.YYYYMMDD` and `:latest`. A failure anywhere leaves `:latest` where it
   was.
5. `release`: a GitHub release named after the dated tag, with the package
   diff against the previous release (`packages.txt` is attached to each).
6. `required`: the only status a ruleset should require. Green when every job
   above it passed or was skipped on purpose.

Concurrency: pull requests cancel their own stale runs; `main` never cancels a
run in progress. `clean.yml` shares the `main` group so it never prunes while a
publish is running.

## Tags

| Tag | Meaning |
|---|---|
| `:latest` | Newest build that passed everything. What installs follow. |
| `:45.YYYYMMDD` | That day's build (a second build the same day replaces it). The retention unit: the newest 30 are kept. |
| `:candidate` | Staging: the last pushed digest, possibly not yet signed. Never install it. |

The testing repository (`neptuno-testing`) runs the same file and publishes
`ghcr.io/siddhj2206/neptuno-testing`; `IMAGE_NAME` comes from the repository
name.

## Signing

Keyless cosign (v3, GitHub OIDC). Only `publish` holds `id-token: write`. The
identity is the workflow file and branch, matched exactly in CI. The owner's
capitalisation is preserved in the certificate (`Siddhj2206`), so
`neptuno verify` on a device matches case-insensitively. Devices pull over
`ostree-unverified-image`; doc/product.md 11 explains why CI is the only
enforcement point. Signing must stay in `build.yml` itself: moving it into a
reusable workflow changes the certificate identity.

## Renovate

Policy in `.github/renovate.json` (`config:best-practices`, semantic commits,
weekly schedule). Non-majors automerge through platform automerge, which is
only safe because the `required` check builds, boots and tests the image on
every pull request: keep that true. The base image's digest bumps skip the
schedule. Fedora majors are disabled; rebase by hand. Actions are grouped,
wait 3 days after release, and only `actions/*` and `sigstore/*` automerge.

Pinned versions outside standard managers use:
- `export x := env("X", "image:tag@sha256:…")` in the root Justfile,
- `registry/image:tag@sha256:…` inline in workflows and the neptuno justfile,
- `# renovate: datasource=… depName=…` above an env var in workflows.

## Retention

`clean.yml` runs `dataaxiom/ghcr-cleanup-action`: newest 30 dated tags kept,
untagged digests older than 14 days and orphaned signature artifacts (`sha256-*`
tags; GHCR has no referrers API) deleted. `stable` and `stable-testing` are
excluded until the laptop leaves the pre-rebuild image. Releases are pruned to
the newest 30. A manual dispatch is a dry run unless unticked.

## Repository settings this relies on

- A ruleset on `main` requiring the `required` status check, and "Allow
  auto-merge" on (for Renovate's platform automerge).
- Actions: "Read and write permissions" are not needed; jobs declare their own.
- The GHCR package grants this repository's Actions write access (automatic
  when the workflow created it).

## Known gaps

- Measured only locally: chunkah rootless (96 layers, largest 270 MB) and the
  content tests. The bcvk boot test and the cosign v3 / GHCR referrer fallback
  are first verified on the first CI run.
- There is no ISO workflow yet; `just build-iso` is local only. A first
  `iso.yml` (dispatch, `just iso` around the published tag) was dropped
  until it can be finished. On `ubuntu-26.04` osbuild failed with
  `mount: /run/osbuild/containers/storage: permission denied` and
  `fchownat ... Operation not permitted`. Resetting root storage to overlay
  (osbuild/bootc-image-builder#446) and setting
  `kernel.apparmor_restrict_unprivileged_userns=0` did not fix it; `just iso`
  now adds `--security-opt apparmor=unconfined` on AppArmor hosts, which was
  never tested in CI. The ISO is also about 4 GB, over the 2 GiB
  release-asset limit, so it needs a home besides a release.
