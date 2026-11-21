# Neptuno: Fedora base-atomic + niri + DankMaterialShell. See doc/product.md.
#
# Phases run in the order of the RUN blocks below. Packages come before the
# filesystem overlay so editing system_files/ reuses the package layer.

FROM scratch AS ctx
COPY build /build
COPY system_files /system_files
COPY flatpaks /flatpaks

# Renovate keeps the digest current; the major is bumped by hand.
FROM quay.io/fedora-ostree-desktops/base-atomic:45@sha256:ec86944e5b331b58d48b8375f678e4e30e95ad55db79304462391569c012c6df

# Identity. CI passes IMAGE_NAME from the repository name, so a copy of this
# repository publishes under its own name with a matching update reference.
ARG IMAGE_NAME="neptuno"
ARG IMAGE_VENDOR="siddhj2206"
ARG BASE_IMAGE_NAME="base-atomic"
ARG VERSION=""

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

RUN dnf5 config-manager setopt keepcache=1 install_weak_deps=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-packages.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/20-overlay.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/30-desktop.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/40-services.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/50-initramfs.sh

# /run is not a tmpfs here on purpose: cleanup must remove image-layer files
# such as /run/dnf for bootc lint's nonempty-run-tmp check.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/90-cleanup.sh

# /opt is writable state on an image-based system.
RUN rm -rf /opt && ln -s /var/opt /opt

# Volatile metadata stays late so a new commit or date only rebuilds labels.
ARG IMAGE_CREATED=""
ARG SHA_HEAD_SHORT=""
LABEL org.opencontainers.image.title="${IMAGE_NAME}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${SHA_HEAD_SHORT}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.description="Neptuno: niri and DankMaterialShell on Fedora base-atomic" \
      org.opencontainers.image.source="https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}" \
      org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      containers.bootc="1"

CMD ["/sbin/init"]

RUN bootc container lint --fatal-warnings
