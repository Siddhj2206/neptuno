---
name: build
description: >-
  The Containerfile, Justfile, build phases and pins. Use when changing how
  the image is assembled, adding a phase, or bumping the base.
---

# Build

## The Containerfile

Structure, in order:

1. **Context** — `ctx` copies `build/`, `system_files/` and `flatpaks/`.
2. **Base** — the `FROM` line, pinned by digest.
3. **Identity** — `IMAGE_NAME`, `IMAGE_VENDOR`, `BASE_IMAGE_NAME`, `VERSION`.
   CI passes `IMAGE_NAME` from the repository name.
4. **Phases** — one `RUN` per script. Packages come before the overlay, so an
   edit under `system_files/` (the common change) reuses the package layer.
5. **Metadata** — `IMAGE_CREATED` and `SHA_HEAD_SHORT` are declared late so a
   new commit only rebuilds the label layer.

`90-cleanup.sh` runs without a tmpfs on `/run` on purpose: it must delete
image-layer files there (`/run/dnf`) or lint's nonempty-run check fails.

## The Justfile

Every step CI runs is a recipe, so a red run reproduces locally with the same
command; `just --list` is the index. Build through `just build`: it derives
`VERSION` (`45.YYYYMMDD`) from the `FROM` tag and unsets an inherited
`NOTIFY_SOCKET`, which would otherwise land in `/run` and fail lint. `just
rechunk` runs chunkah rootless over the built image and lints the result;
`build-qcow2` and `build-iso` need root storage and copy the image there with
`root-copy`.

## Pins

Renovate pins every image and action by digest; let it propose digest bumps.
The Fedora major is the exception: `.github/renovate.json` disables majors for
`quay.io/fedora-ostree-desktops/*` because that namespace tags unreleased
branches. Bump `base-atomic:N` by hand once the release is out, and in the
same PR re-check `doc/product.md` section 4 (what the base ships).

Versions Renovate tracks outside standard managers use the regex managers in
`.github/renovate.json`: Justfile `env()` defaults, inline image refs in
workflows and the neptuno justfile, and a `# renovate: datasource=… depName=…`
comment above a variable in workflows and `build/*.sh`. An asset fetched
at build time is verified against a checksum file published with it, never a
hash in this repo, because Renovate can bump a version but not recompute a
hash (`NX_VERSION` in `20-overlay.sh` is the pattern).

## Adding a phase

Give it a number that says where it sits, a header comment saying what it
owns, and a `RUN` block with the `ctx` bind mount. Packages still go through
manifests and `10-packages.sh`, and enablement through `40-services.sh`; a new
phase that installs or enables directly bypasses the unit audit.
