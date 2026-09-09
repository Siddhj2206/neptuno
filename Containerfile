###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: neptuno
#
# IMPORTANT: Change "neptuno" above if you rename the project again.
# This name should be used consistently throughout the repository in:
#   - Justfile: export IMAGE_NAME := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
#   - build/00-image-info.sh: ${IMAGE_VENDOR:-...}/${IMAGE_NAME:-...} fallbacks
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references above
# to maintain consistency.
###############################################################################

###############################################################################
# MULTI-STAGE BUILD ARCHITECTURE
###############################################################################
# This Containerfile follows the Bluefin architecture pattern as implemented in
# @projectbluefin/distroless. The architecture layers OCI containers together:
#
# 1. Context Stage (ctx) - Combines resources from:
#    - Local build scripts and custom files
#    - @projectbluefin/common - Desktop configuration shared with Aurora
#    - @ublue-os/brew - Homebrew integration
#
# 2. Base Image (edit the FROM line below):
#    `quay.io/fedora-ostree-desktops/silverblue:44` (Fedora Silverblue with
#    GNOME/GDM; Niri is added as a second session)
#
# See: https://docs.projectbluefin.io/contributing/ for architecture diagram
###############################################################################

# OCI context images - imported below and pinned directly in their FROM lines.
# The base image is pinned in the FROM line below and updated by Renovate.
FROM ghcr.io/projectbluefin/common:latest@sha256:b3c4e8fef89d27cdf16f003632ee9bf0a19ac2e0d40526c4ca6ec41909282546 AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:d52b3f578f01623636aff534291b0bd8ff0a0244ef225bf51aecb5fa05a137af AS brew

# Context stage - combine local and imported OCI container resources
FROM scratch AS ctx

COPY build /build
COPY custom /custom

# Copy from OCI containers to distinct subdirectories to avoid conflicts
COPY --from=common /system_files /oci/common
COPY --from=brew /system_files /oci/brew

# Base Image - Fedora Silverblue supplies the supported GNOME/GDM desktop stack.
# Niri is added as a second Wayland session by build/40-niri.sh.
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:c05886ff0e2ebfa27b842dcb4200d2e246dae3fd0960e9c7f0c34f257aac70bf

ARG IMAGE_NAME="neptuno"
ARG IMAGE_VENDOR="siddhj2206"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG VERSION=""
ARG SHA_HEAD_SHORT=""

### MODIFICATIONS
## Silverblue already supplies Fedora repositories, DNF plugins, rsync, kernel
## drivers, firmware, and GNOME. Do not import Hummingbird bootstrap logic.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

# Match Bluefin's image-wide package policy: only explicitly requested
# dependencies are installed by the remaining package layers.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    dnf5 config-manager setopt install_weak_deps=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

### BASE PACKAGES — wm-agnostic desktop foundation (base.toml).
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/20-base.sh

### MULTIMEDIA — negativo17 ffmpeg + mesa/VA overrides (multimedia.toml).
## The third-party repo is disabled by clean-stage.sh after its packages and
## version locks are baked into the image.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/25-multimedia.sh

### NIRI COMPOSITOR LAYER — niri + DMS (COPRs, disabled by clean-stage.sh).
## GNOME/GDM remains the display manager; Niri is an additional session.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/40-niri.sh

### DX LAYER — docker-ce (repo removed after install), adb, libvirt/qemu
## host daemon, all socket-activated (dx.toml).
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/45-dx.sh

### CLEANUP
## Pre-lint cleanup (clean-stage.sh). /run is deliberately not tmpfs here:
## clean-stage.sh must remove image-layer files like /run/dnf for bootc
## lint's nonempty-run-tmp check (it tolerates busy Buildah bind mounts).
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

### /opt
## Makes /opt writeable by default. Needs to be here to make the main image
## build strict (no /opt there). This is for downstream images/stuff like k0s.
## If you need /opt as an immutable real directory for build-time packages
## (e.g. google-chrome, docker-desktop), replace the next line with:
##   RUN rm /opt && mkdir /opt
RUN rm -rf /opt && ln -s /var/opt /opt

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
RUN bootc container lint --fatal-warnings
