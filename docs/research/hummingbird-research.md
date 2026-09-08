# Fedora Hummingbird / Project Hummingbird — Research Report

**Prepared for:** pluto (finpilot-derived bootc image) rebase evaluation
**Researched & fetched:** 2026-08-28
**Primary sources:** hummingbird-project.io (full docs tree), quay.io API, gitlab.com/redhat/hummingbird (raw files via API), fedoramagazine.org, discussion.fedoraproject.org, fedoraproject.org/wiki/Hummingbird, local pluto repo (commit 27d927d).

---

## 0. Executive summary

There are **two Hummingbirds** that must not be conflated:

1. **Project Hummingbird** — a Red Hat container-image *factory* (GitLab org `redhat/hummingbird`) producing minimal, hardened, *distroless* containers (curl, python, go, nginx, postgres, etc.). Announced at Red Hat Summit 2026. This is a userspace container catalog project.
2. **Fedora Hummingbird** — the *OS* application of the same factory model: a **rolling, bootc-based, minimal server/VM operating system** shipped as an OCI image at **`quay.io/hummingbird-community/bootc-os`**. Announced May 12, 2026 via Fedora Magazine. **Explicitly experimental, "not suitable for production."** It is a *minimal* OS — **no desktop environment, no flatpak, no GNOME** — and is **VM-oriented**, not desktop-oriented.

For pluto (a GNOME desktop image), rebasing means: keep finpilot's runtime layer (ctx stage, custom/, ujust, brew, flatpak preinstall, signing, two-branch model) and replace only the base + base-dependent assumptions — but **the entire desktop stack must be assembled from scratch** on top of a minimal base, because Hummingbird ships no desktop packages at all.

---

## 1. What Hummingbird is (ground truth)

### 1.1 Project Hummingbird (the container factory)

- Positioning (hummingbird-project.io/docs/using/overview/): *"Project Hummingbird builds a collection of minimal, hardened, and secure container images with a significantly reduced attack surface... aiming to minimize CVE counts, targeting near-zero vulnerabilities. All images support amd64 and arm64 architectures."*
- Distroless design: *"no package manager, no shell, just the application and what it strictly needs to run."* Non-root default UID 65532.
- Numbers (Fedora Magazine, 2026-05-12): *"a catalog of 49 unique minimal, hardened, distroless container images (that's 157 variants including FIPS and multi-arch) covering Python, Go, Node.js, Rust, Ruby, OpenJDK, .NET, PostgreSQL, nginx, and dozens more."*
- 95%+ of packages come from Fedora source, rebuilt in Hummingbird's own factory (per Magazine). Spec files derived from Fedora but built on Hummingbird infrastructure (docs "Relationship to Fedora").
- Built with **Konflux** (Tekton-based, konflux-ci.dev), **SLSA level 3**; hermetic builds from **pinned RPM lockfiles**; **chunkah** content-based layers; **fully reproducible builds**; continuous Syft/Grype scanning; VEX feed maintained by Red Hat Product Security.
- License: MIT (containers repo).
- Live CVE catalog: https://catalog-hummingbird.hummingbird-project.io/ ("Hummingbird Image Catalog" — JS app, no static content to cite).
- Code: https://gitlab.com/redhat/hummingbird — monorepos: `containers`, `rpms`, `tools`, `infrastructure`, `pipelines`, `releng`.
- Registries (docs "Registry Organizations"):
  - `registry.access.redhat.com/hi/` — Red Hat supported (recommended, signed, Pyxis-registered)
  - `quay.io/hummingbird/` — mirror of Red Hat supported, no official signing
  - `quay.io/hummingbird-community/` — community: **`bootc-os`**, `minio`, `minio-client`
  - `quay.io/hummingbird-rawhide/` — Fedora Rawhide packages directly
  - `quay.io/hummingbird-ci/` — tooling (e.g. `hummingbird-builder`, `k8s-test-pipeline`)

### 1.2 Fedora Hummingbird / bootc-os (the OS)

- Announced in Fedora Magazine 2026-05-12 ("Fedora Hummingbird: Taking the Hummingbird model to the full operating system", Harrison Ripps): *"a new container-based rolling Fedora Linux distribution... primarily utilizes an image-based workflow... but also runs in virtual machines and even on bare metal."*
- Image: **`quay.io/hummingbird-community/bootc-os`**, tag **`latest`** (rolling; no version tags), multi-arch **x86_64 + aarch64** (verified via Quay API 2026-08-28: manifest list with 2 child manifests; per-arch uncompressed ~420 MB aarch64 / ~503 MB x86_64).
- Rebuild cadence: **~daily (multiple times/day)** — Quay history shows pushes at 2026-08-24 03:40, 08-25 03:26, 08-26 03:35, 08-26 05:40, 08-26 19:30 UTC. Each build publishes `.sig` (signature), `.att` (SLSA provenance attestation), `.sbom` (SPDX SBOM), and `latest-source` source containers.
- Content (properties.yml, current main): a **minimal VM/server OS**, `main_package: kernel`, plus: bootc, bootupd, bubblewrap, grub2, grub2-efi-x64/aa64, shim-x64/aa64, systemd, systemd-pam, dracut, coreutils-single, bash, selinux-policy-targeted, cloud-utils-growpart, dosfstools, e2fsprogs, NetworkManager, dbus-broker, firewalld, audit, chrony, polkit, ca-certificates, iproute, findutils, grep, less, vim-minimal, passwd, tar, util-linux, sudo, procps-ng, curl, openssh-server/clients, **dnf5**, python3, **podman**, containernetworking-plugins, fuse-overlayfs, skopeo. **No desktop, no display manager, no flatpak, no GNOME/KDE.** `user: root`, `CMD ["/sbin/init"]`.
- **Kernel**: magazine claims ARK (Always Ready Kernel from CKI, tracks Linus mainline): *"Under the hood, Fedora Hummingbird will use the ARK kernel... from the CKI project."* The SIG wiki lists "Coordinate ARK (Always-Ready Kernel) integration for the edition" as a SIG responsibility; the image spec merely says `main_package: kernel`. So ARK is stated as the direction; verify in the shipped image before relying on it.
- Composition (verified from generated Containerfile + `rpms.in.yaml` today): bootc-os is built from **`yum-repos/fedora-43.repo`** (Fedora 43 Everything + updates, mirrored at `https://koji-s3-cache.hummingbird-project.io/download-ib01.fedoraproject.org/...`) **+ `yum-repos/hummingbird.repo`** (`https://packages.redhat.com/api/pulp-content/public-hummingbird/{x86_64,aarch64}/`, priority=10). i.e. the shipped image is **Fedora 43 packages + Hummingbird-rebuilt RPMs** — *not* Rawhide, despite the Magazine's "95%+ from Fedora Rawhide" phrasing. `fedora-44.repo` and `fedora-rawhide.repo` also exist in the repo for other images/streams; the Hummingbird *buildroot* was rebased to F44 in a ~2-week operation (runbook: docs/operating/rebasing-buildroot-to-new-fedora/).
- Governance/status: Fedora HUMBINGBIRD is a **Fedora SIG** (fedoraproject.org/wiki/Hummingbird — members incl. Valentin Rothberg, Stef Walter, Adam Miller, Harrison Ripps, Scott McCarty, Laura Santamaria; meetings every 4 weeks). Trademark approval granted by Fedora Council **via a private ticket** (controversial; see §5). Fedora integration is *"early stages"* — per Council member Justin Wheeler: *"ONLY the trademark. No other special exceptions... If there are changes, expect to see either System-Wide Changes or Self-Contained Changes."* Fedora maintainer Maxwell G: *"there is no such thing as Fedora Hummingbird"* (as a Fedora deliverable). Landing page: https://forge.fedoraproject.org/hummingbird. The Fedora Innovation Lifecycle proposal that would host it is **not yet approved** (forge.fedoraproject.org/council/tickets/issues/564).
- Support level: `support_level: community` in properties.yml; README: *"**Experimental**: This image is a proof of concept and is not suitable for production use. Its package set, configuration, and update mechanism may change without notice."*
- Install path: no native ISO; convert with **bootc-image-builder** (`--type qcow2|ami|vmdk|iso|raw`), then boot; or `podman-bootc` / `bcvk` for local VM testing. Magazine quickstart uses `quay.io/centos-bootc/bootc-image-builder:latest` with `--rootfs ext4`.

---

## 2. Image / build primitives (what pluto would use)

### 2.1 The official derivative pattern (from bootc-os README.md in the containers repo)

```dockerfile
FROM quay.io/hummingbird-community/bootc-os:latest

# Install additional packages
RUN dnf install -y htop && dnf clean all

# Drop in custom configuration
COPY my-service.conf /etc/my-service/
```

Apply to running systems with:

```bash
bootc switch --transport registry quay.io/my-org/my-os:latest
```

This 4-line "Customize" section is **the entirety of Hummingbird's public derivative-image documentation**. There is **no derivative template repo, no starter repo, no documented desktop-image guidance** (docs are silent — see §4).

### 2.2 How Hummingbird itself builds bootc-os (generated Containerfile, current main)

**Not** a layered build on an OS base image. Fully scratch-composed:

```dockerfile
FROM quay.io/hummingbird-ci/hummingbird-builder:latest AS builder
COPY hummingbird/default/rpms/rpms.lock.yaml /tmp/repo/
RUN download-locked-packages /tmp/repo/rpms.lock.yaml
RUN dnf-installroot ${NEWROOT} ${DNF_FLAGS} install filesystem
RUN dnf-installroot ${NEWROOT} ${DNF_FLAGS} install ${MAIN_PACKAGES}
...
RUN chunkah build --rootfs ${NEWROOT} --max-layers 32 > /run/src/out.ociarchive
FROM oci-archive:out.ociarchive

LABEL containers.bootc=1
ENV container=oci
STOPSIGNAL SIGRTMIN+3
USER root
CMD ["/sbin/init"]
```

- Builder base: `quay.io/hummingbird-ci/hummingbird-builder:latest` (distro `hummingbird`) or `quay.io/hummingbird-rawhide/hummingbird-builder:latest` (distro `rawhide`) — see `macros/setup_newroot.yml.j2`.
- All RPMs come from **`rpms.lock.yaml`** (every transitive dep pinned with version/URL/checksum), downloaded in hermetic mode (`download-locked-packages`). EC-policy docs confirm: *"final images are built `FROM scratch`"*.
- **chunkah** (`github.com/coreos/chunkah`) produces content-based layers (package-granular) — the base image's layers are *not* copy-on-write friendly the way layer-on-layer derivatives are; a `COPY`/`RUN` on top still creates an extra layer chain in your derivative (bootc unifies at deployment; layer reuse benefits are reduced relative to a fedora-bootc base).
- GPG keys imported at build: `RPM-GPG-KEY-fedora-43-primary`, `RPM-GPG-KEY-hummingbird-release`.
- Known systemd quirks applied in base (cite for derivative authors): SELinux store relocated to **`/usr/lib/selinux`** (*"Placing the store under /usr (rather than /etc as fedora-bootc does) avoids 3-way merge overhead"*); systemd-firstboot masked; `/etc/systemd/system` presets via `systemctl preset-all`; /var cleared pre-ship; tmpfiles fixes (home.conf removed, provision.conf `/root`→`/var/roothome`); **`bootc container lint --no-truncate --fatal-warnings`** run in CI; `bootupctl backend generate-update-metadata` with SOURCE_DATE_EPOCH timestamp override (bootupd issue #1075 workaround).

### 2.3 Tagging / versioning

- bootc-os: **only `latest`** (+ `latest-source`); `stream: "latest"`, explicitly *"rolling release, no version branches"* (properties.yml comment). No `:<version>` tags, no date tags. The general Hummingbird tagging scheme (`:<major>`, `:<major>.<minor>`, `:<full>`, `-builder`, `-fips`) applies to the versioned catalog images, not to bootc-os.
- Digest availability: yes — pin `quay.io/hummingbird-community/bootc-os:latest@sha256:...` (current index digest at fetch time: `sha256:ad50d8ad73f21b639956d20f0891ccf0bf67e1809a1a8f58b76f4de5fb0e04d7`).

### 2.4 Label conventions (bootc-os labels, current)

`LABEL containers.bootc=1`, `ENV container=oci`, `STOPSIGNAL SIGRTMIN+3`, plus `name="hummingbird-community/bootc-os"`, `com.redhat.component=hummingbird`, `maintainer="Project Hummingbird / Red Hat"`, `vendor="Red Hat, Inc."`, `distribution-scope=public`, `io.hummingbird-project.*` labels (repository=bootc-os, stream=latest, variant=default, support-level=community, application-category="Operating System"), `org.opencontainers.image.*` set. Full label reference: docs/background/containers/container-image-labels/ (labels.json written to `/usr/share/buildinfo/labels.json`). Note: labels like `io.hummingbird-project.*` are Hummingbird-internal consumers; a derivative keeps its own identity labels — no requirement to carry them.

---

## 3. Best practices & tooling used by the project

- **CI/CD**: GitLab + **Konflux** (Tekton) + PipelinesAsCode. MRs build images; tests run via **Testing Farm** (RHEL-9-Nightly, x86_64+aarch64) for container tests and **EaaS** ephemeral clusters for K8s tests.
- **Policy gate**: **Enterprise Contract / Conforma** with `@redhat` rule collection, `EnterpriseContractPolicy` in `konflux-templates/macros/policy.yml.j2`, with documented exclusions (Snyk SAST, Red Hat preflight, `cve.cve_blockers`, `schedule.weekday_restriction` — releases allowed on weekends for urgent CVE fixes; `buildah_build_task.privileged_nested_param` because of dnf-installroot; rpm_repos.ids_known; labels).
- **Signing/attestation**: **Cosign** signing in the release pipeline (docs: *"Images are signed using Cosign as part of the release pipeline"*); SLSA provenance attestations (.att) and SPDX 2.3 SBOMs (.sbom, syft+hermeto→mobster). Verified consumer path documented only for Red Hat supported: `cosign verify --key "https://security.access.redhat.com/data/63405576.txt" --insecure-ignore-tlog registry.access.redhat.com/hi/<image>:<tag>`. Community images (bootc-os) carry `.sig` artifacts on Quay but docs give **no verification instructions** for them.
- **Dependency updates**: **Renovate** (custom instance, MintMaker; forked `rpm-lockfile` manager; `rpm-lockfile-prototype` from konflux-ci) auto-opens MRs refreshing each image's `rpms.lock.yaml` (e.g. "Refresh RPM lockfiles for go-1-25/hummingbird"); auto-merge on green. Same update philosophy as finpilot's Renovate digest PRs, scaled to RPM lockfiles.
- **Reproducibility**: fully reproducible builds; CI verifies via `ci/test_rebuild.sh`; users can rebuild from attestation (`quay.io/hummingbird-ci/hummingbird-builder rebuild < attestation.json`).
- **Testing**: `tests-container.yml` per image; bootc-os tests = `bootc-label` (containers.bootc==1) + `bootc-lint` (`bootc container lint`).
- **Release/promotion**: six-stage pipeline (templates → generation → Konflux build → testing → EC validation → release). Release via Konflux **ReleasePlanAdmission**; tags from Containerfile labels; production advisories RHSA/RHBA/RHEA; VEX feed at security.access.redhat.com; Pyxis registration (Red Hat Hardened Images, Product ID 1071).
- **No GitHub Actions / no ujust / no GitHub-based promotion** — that side of finpilot is entirely pluto's own; nothing from Hummingbird depends on it.

---

## 4. Finpilot compatibility analysis (pluto = finpilot fork, per local repo inspection)

### (i) Carries over cleanly

1. **Multi-stage Containerfile with scratch `ctx` stage** — orthogonal to the base. The ctx pattern (COPY build/, custom/, `COPY --from=common`/`--from=brew`) composes config layers onto any base.
2. **Two-branch model (`main` → `:stable-testing`, `stable` → `:stable`) + promote-main-to-stable squash PR + `validate` job** — pure GitHub-side workflow; Hummingbird has no opinion; unchanged.
3. **Keyless OIDC cosign signing of pluto's images** — bootc native (bootc verifies signatures via policy), and Hummingbird's own images are cosign-signed, so the ecosystem is consistent. Base images need no special handling.
4. **Renovate digest pinning of the FROM line** — bootc-os publishes stable digests daily; same mechanism as today. Expect **much higher churn** (base rebuilt ~daily), so consider batching/minimum interval.
5. **Runtime layer: `custom/` (ujust recipes, Brewfile), `build/` scripts, ublue flavorbits** — base-agnostic. **dnf5 is present in bootc-os** (`dnf5` in package list), satisfying finpilot's "ALWAYS use dnf5" rule. `sudo` present.
6. **bootc switch / Justfile default recipe** — bootc + bootupd are in the base; `bootc switch` works identically.
7. **Multi-arch** — Hummingbird publishes x86_64 + aarch64; pluto can keep its build matrix.
8. **bootc lint** as a CI/test check — the project uses `bootc container lint`; pluto's CI can adopt the same check.

### (ii) Needs modification

1. **FROM line** — `quay.io/fedora-ostree-desktops/silverblue:44@sha256:...` → `quay.io/hummingbird-community/bootc-os:latest@sha256:...` (digest-pinned, Renovate-managed). Corresponding README/Justfile/AGENTS.md/documentation updates (the Containerfile header comment documents the silverblue/base-main/centos-bootc options; add bootc-os).
2. **Full desktop assembly** — bootc-os contains **zero desktop packages**. Pluto's whole GNOME experience (GNOME Shell, gdm, gnome-settings-daemon, gnome-software, plymouth, pipewire, mesa, fonts, flatpak + flathub remote, etc.) must be added in the Containerfile via dnf5 group/package installs. This is the single biggest delta — effectively re-creating Fedora's workstation comps on a minimal base. **No Hummingbird docs describe how to do this** (silent).
3. **Flatpak preinstall** — flatpak is not in base; install via dnf5 + configure flathub + preinstall script stays in build/ or moves to first-boot; also `ujust flatpak` shortcuts unaffected.
4. **Kernel handling** — base ships its own kernel (ARK-tracked per magazine) with its own dracut initramfs; any pluto assumptions about the "Fedora desktop kernel" (e.g., kmod expectations, `linux-firmware` inclusion — not obviously in base lockfile) need re-verification. Note properties.yml does not list `linux-firmware` explicitly.
5. **SELinux paths** — Hummingbird stores the SELinux policy at **`/usr/lib/selinux`** instead of `/etc/selinux` (deliberate difference from fedora-bootc; verified in generated Containerfile). Any pluto/common/brew script that touches the policy store or semanage expects the fedora-bootc layout → audit `custom/` and `@projectbluefin/common` content for `/etc/selinux` references.
6. **ISO/docs workflow** — finpilot `iso/` and README install docs assume ublue/fedora tooling; Hummingbird's published path is **bootc-image-builder** (`--type iso|qcow2|...`). Update docs/scripts accordingly (or keep ublue's ISO tooling — untested against bootc-os base).
7. **@projectbluefin/common & @ublue-os/brew context images** — no documented incompatibility with a bootc-os base (they ship /system_files overlays and brew binaries), but they are built/tested against ublue current bases; nothing in Hummingbird docs validates them (silent — carry-over is best-effort). `@ublue-os/brew` will install/run on Fedora deps — verify glibc compatibility against F43-era base.
8. **Version pinning semantics** — finpilot's "Renovate bumps digest of silverblue:44" relied on stable release streams; bootc-os `latest` is a rolling target; consider pinning the digest and letting Renovate batch updates; horizon: the base "may change without notice."
9. **`rpm-ostree` vs `bootc` references** — Hummingbird is bootc-native; finpilot may reference `rpm-ostree` commands in docs/scripts (e.g. ujust system-update recipes) — switch to `bootc upgrade` semantics (pluto likely already uses bootc; verify).

### (iii) Must be removed / conflicts

1. **`quay.io/fedora-ostree-desktops/silverblue:44` base + its digest pin** — replaced outright.
2. **Any package or overlay that duplicates what the base already ships in a Fedora-specific way** — e.g., if pluto's build scripts install `kernel`, `dnf5`, `systemd` et al. (already in bootc-os), dedupe to avoid version conflicts with the Hummingbird-rebuilt RPM stream.
3. **Bluefin-specific desktop overlays from @projectbluefin/common that assume GNOME desktop layout shipped by *fedora-ostree-desktops*** — only if/when they reference paths/profiles that the minimal base lacks (e.g., gdm autologin config paths, /usr/share/ublue-os assumptions). Audit before keeping.
4. **Docs/README statements** claiming "Fedora 44 / GNOME included" base semantics (Containerfile header, README raptor section, artifacthub description) — must be rewritten.
5. Nothing in Hummingbird's docs requires removing GitHub Actions, keyless signing, ujust, or the brew layer — those are pluto-owned. **Also note the inverse:** Hummingbird's own CI (Konflux/EC/Testing Farm) is *not* transferable to GitHub Actions; don't attempt to replicate EC policy checks; there is no Hummingbird-native derivative CI to adopt (docs silent).

---

## 5. Open questions the docs leave unanswered

1. **Maturity/risk**: bootc-os self-describes as experimental POC, "may change without notice," support_level=community. No ETA or roadmap for production readiness of the OS image (the roadmap item says only "Bootable containers: Expanding support for image-based OS deployments and updates").
2. **Base content drift**: current bootc-os locks Fedora **43** repos, while the Magazine says Rawhide and the F44 buildroot rebase is done. Which Fedora stream will bootc-os track when it rolls? No public statement.
3. **Upgrade path**: no documented upgrade path between Fedora releases for bootc-os consumers; no LTS/kernel-pinned tags; no stability guarantees for `latest`.
4. **Kernel provenance**: ARK integration is stated in the Magazine/SIG wiki, but the image spec simply declares `kernel`; no docs confirm whether the shipped bootc-os kernel is currently ARK-built or fedora-43-built.
5. **Derivative guidance**: beyond the 4-line Customize snippet, no docs on building desktop/derivative images, no starter template, no tag conventions for derivatives, no guidance on layering over chunkah images, no documented interaction with chained bootc upgrades.
6. **Governance**: Fedora integration "early stages"; trademark approved via private ticket; Innovation Lifecycle proposal unapproved; community channels (SIG meetings, forge page) still forming. Trust/momentum risk is real and documented in the public record.
7. **Signing verification for community images**: cosign verification documented only for `registry.access.redhat.com/hi/`; no verification docs for `quay.io/hummingbird-community/*` (though .sig/.att/.sbom artifacts exist).
8. **Ecosystem silence**: docs say nothing about brew/Homebrew, ujust, flatpak, GH Actions, Renovate digest pinning of bootc-os, or coexistence with @projectbluefin/common overlays — treat as unvalidated.
9. **Team/practices outside docs**: much operational detail lives behind redhat.atlassian.net (HUM-* tickets) and internal-documentation.hummingbird-project.io; the public web docs are the only citable source.

---

## 6. Key facts sheet (citation-ready)

| Fact | Value | Source |
|---|---|---|
| OS image | `quay.io/hummingbird-community/bootc-os:latest` (multi-arch x86_64+aarch64, amd64/arm64) | quay.io API (2026-08-28); Magazine 2026-05-12 |
| Support level | community; "Experimental… not suitable for production" | images/bootc-os/properties.yml; README.md |
| Build cadence | ~daily, several pushes/day | quay.io API tag history (2026-08-24…26) |
| Official derivative pattern | `FROM quay.io/hummingbird-community/bootc-os:latest` + `RUN dnf install` + `COPY`; update via `bootc switch --transport registry ...` | images/bootc-os/README.md |
| Hummingbird build model | `FROM quay.io/hummingbird-ci/hummingbird-builder:latest AS builder` → dnf-installroot from `rpms.lock.yaml` → `chunkah build` → `FROM oci-archive:out.ociarchive`; final images "built FROM scratch" | generated Containerfile; docs image-pipeline; EC policy exclusions |
| OS packages in base | kernel (main), bootc, bootupd, systemd, dracut, grub2, shim, NetworkManager, firewalld, dnf5, python3, podman, skopeo, fuse-overlayfs, openssh-*, sudo, curl, … **no desktop, no flatpak** | properties.yml (fetched 2026-08-28) |
| Repos composing bootc-os | fedora-43 Everything+updates (koji-s3-cache.hummingbird-project.io mirror) + hummingbird pulp (packages.redhat.com/api/pulp-content/public-hummingbird/, prio 10) | rpms.in.yaml; yum-repos/*.repo |
| Kernel | ARK per Magazine/SIG responsibility; spec says `kernel` | fedoramagazine.org; wiki/Hummingbird |
| Signing | Cosign; SLSA .att; SPDX .sbom; verify hi/ images: `cosign verify --key https://security.access.redhat.com/data/63405576.txt --insecure-ignore-tlog` | docs using/overview; docs image-pipeline §Release |
| Dependency automation | Renovate (custom instance, MintMaker) + rpm-lockfile-prototype refreshing rpms.lock.yaml MRs | docs image-pipeline §RPM Dependency Updates |
| Governance | Fedora Council trademark approval (private ticket); SIG active; Innovation Lifecycle not approved; "ONLY the trademark. No other special exceptions" — Justin Wheeler | discussion.fedoraproject.org/t/191184 |
| F44 buildroot rebase | ~2 weeks; runbook + HUM-2018 epic | docs operating/rebasing-buildroot-to-new-fedora |

Fetch date: 2026-08-28. All quoted text verbatim from the sources above.
