###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: neptuno
#
# IMPORTANT: Change "finpilot" above to your desired project name.
# This name should be used consistently throughout the repository in:
#   - Justfile: export IMAGE_NAME := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
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
# 2. Base Image Options (edit the FROM line below):
#    - `quay.io/fedora-ostree-desktops/silverblue:44` (Fedora 44 and GNOME)
#    - `quay.io/fedora-ostree-desktops/base-main:44` (Fedora 44, no desktop)
#    - `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based)
#
# See: https://docs.projectbluefin.io/contributing/ for architecture diagram
###############################################################################

# OCI context images - imported below and pinned directly in their FROM lines.
# The base image is a Fedora official OSTree desktop image.
FROM ghcr.io/projectbluefin/common:latest@sha256:633ae6efa2f28f451812586cfeb5162d7b70054dda3e25510abdb3c6afa13be8 AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:14ad3acb89bea0a7d98cacc206a4f590efcb794b7da7385bbeba4ed943289ad4 AS brew

# Context stage - combine local and imported OCI container resources
FROM scratch AS ctx

COPY build /build
COPY custom /custom

# Copy from OCI containers to distinct subdirectories to avoid conflicts
COPY --from=common /system_files /oci/common
COPY --from=brew /system_files /oci/brew

# Base Image - GNOME included (Fedora official OSTree desktop)
# Renovate will keep the digest pin up to date.
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:2b8f8279b3c326e131ad6cb64aa416565053d268a5a337807141f353b0354696

# Image identity - these define how bootc, fastfetch, and the ublue ecosystem
# recognize your image. Change these to match your project name.
ARG IMAGE_NAME="neptuno"
ARG IMAGE_VENDOR="siddhj2206"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG VERSION=""

### MODIFICATIONS
## Make modifications desired in your image and install packages by modifying the build scripts.
## The following RUN directive mounts the ctx stage which includes:
##   - build.sh orchestrator from /build
##   - Step scripts from /build/steps/
##   - Local custom files from /custom
##   - Files from @projectbluefin/common at /oci/common (includes branding/artwork content)
##   - Files from @ublue-os/brew at /oci/brew
## All build step scripts are orchestrated by build.sh which calls them in order.
## clean-stage.sh and /opt symlink are also handled inside this RUN (not separate layers),
## matching the Bluefin pattern of one monolithic build layer for optimal OTA updates.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/build.sh

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
RUN bootc container lint --fatal-warnings
