# Hummingbird bootc-os — Second Research Pass (Primary-Source Verification)

**Prepared for:** pluto rebase evaluation (follow-up to `/tmp/opencode/hummingbird-research.md`)
**Researched:** 2026-08-28 (~11:10 UTC)
**Primary sources:** shallow clone of `gitlab.com/redhat/hummingbird/containers` (commit `79d84aa247862470521c10428ec9f3b3bc2bcb46`, main @ 2026-08-28 05:30:49 UTC), GitLab API (`redhat/hummingbird/containers`, `redhat/hummingbird/rpms`), Quay API (anonymous).

**Bottom line up front:**
1. **CONFIRMED:** the shipped `quay.io/hummingbird-community/bootc-os:latest` locks **Fedora 43** repos; ~94 % of its runtime packages are Hummingbird-rebuilt RPMs, the kernel stack comes from Fedora 43 updates.
2. **CONFIRMED:** **no F44 or Rawhide bootc-os image is published anywhere today** — and no rawhide variant of bootc-os is even *configured* in the build pipeline.
3. **CORRECTED:** the ARK-kernel question is now *resolved — the shipped kernel is NOT ARK*. It is the stock Fedora 43 kernel `kernel-7.1.10-100.fc43` from `fedora-43-updates` (both arches). No ARK/CKI references exist anywhere in the containers repo.
4. **NEW (the "visibly coming" part):** a **Draft MR !15860** ("fix(images): pin hummingbird distro to Fedora 44", opened 2026-08-27) switches the `hummingbird` distro to `fedora-44.repo` and **fully regenerates the bootc-os lockfile**, which would ship **kernel `7.1.10-200.fc44`** from `fedora-44-updates`. It is open, not merged. Hummingbird-rebuilt userspace versions are **unchanged** on that branch (still fc43-era `.hum1` builds).

---

## 1. "Confirmed" table (claims from first report, re-verified against primary sources)

| Claim (first report) | Verdict | Evidence (exact paths / lines / API) |
|---|---|---|
| bootc-os locks **Fedora 43** repos | ✅ CONFIRMED | `images/bootc-os/hummingbird/default/rpms/rpms.in.yaml` → `contentOrigin.repofiles: [../../../../../yum-repos/fedora-43.repo, ../../../../../yum-repos/hummingbird.repo]`. All Fedora repoids in `images/bootc-os/hummingbird/default/rpms/rpms.lock.yaml` are `fedora-43` / `fedora-43-updates` / `fedora-43-source` / `fedora-43-updates-source`. Zero matches for `fc44|fc45|rawhide|ark|cki` in the lockfile. |
| Kernel comes from Fedora, not ARK (first report: "unverified") | ✅ RESOLVED: **not ARK** | Both `aarch64` and `x86_64` sections of `rpms.lock.yaml`: `evr: 7.1.10-100.fc43`, `repoid: fedora-43-updates`, `sourcerpm: kernel-7.1.10-100.fc43.src.rpm`, URL `https://koji-s3-cache.hummingbird-project.io/download-ib01.fedoraproject.org/pub/fedora/linux/updates/43/Everything/{arch}/Packages/k/kernel-7.1.10-100.fc43.{arch}.rpm`. `grep -ri "ark\b\|always-ready" documentation/` → no hits. The Magazine's ARK claim (direction) is not reflected in any shipped artifact. |
| No F44/Rawhide bootc-os image | ✅ CONFIRMED (published & configured) | (a) `images/bootc-os/properties.yml`: `distros: [hummingbird]` only (rawhide excluded — the documented off-switch per `documentation/operating/disabling-rawhide-for-images.md`). (b) `konflux-templates/rendered.yml`: component count 8, only `bootc-os--hummingbird--default`; **0× `bootc-os--rawhide`**. (c) Quay anonymous probe `quay.io/api/v1/repository/hummingbird-rawhide/bootc-os/tag/?specificTag=latest` → HTTP 401 "Requires authentication", while sibling public rawhide repos (`hummingbird-builder`, `curl`) return HTTP 200 with tags — i.e. a public rawhide bootc-os would be visible, and isn't. |
| `latest` is the only version tag; digest `ad50d8ad…` | ✅ CONFIRMED | Quay tag listing: only `latest` (+ `latest-source`, digest-pinned `sha256-…` aliases, `.sig`/`.att`/`.sbom` artifacts). Current index digest still `sha256:ad50d8ad73f21b639956d20f0891ccf0bf67e1809a1a8f58b76f4de5fb0e04d7` (multi-arch, 2 children). |
| Rebuild cadence "~daily, several/day" | ⚠️ REFINED | Tag history: pushes 08-21 01:35, 08-24 01:34+03:40, 08-25 03:26, 08-26 03:35+05:40+**19:30**. **No push on 08-27 or 08-28** (at check time), although three bootc-os lockfile-refresh MRs merged 08-27 (15842, 15862 @15:10Z, 15870 @19:14Z). Refreshes are Renovate-driven (~2×/day MRs, e.g. 50+ bootc-os MRs in Aug), but publication is not strictly daily. |
| bootc-os is a minimal VM/server OS, `main_package: kernel`, CMD `/sbin/init`, no desktop/flatpak | ✅ CONFIRMED | `images/bootc-os/properties.yml` (`main_package: kernel`, `stream: "latest"`, `support_level: community`, `user: root`); generated `images/bootc-os/hummingbird/default/Containerfile` ends `USER root` / `CMD ["/sbin/init"]`; package list has zero desktop packages (checked against `rpms.in.yaml` 46 entries). |
| Built from scratch: builder → dnf-installroot from lockfile → chunkah | ✅ CONFIRMED | `images/bootc-os/hummingbird/default/Containerfile`: `FROM quay.io/hummingbird-ci/hummingbird-builder:latest AS builder`, `RUN download-locked-packages /tmp/repo/rpms.lock.yaml`, `chunkah build --rootfs ${NEWROOT} --max-layers 32 > /run/src/out.ociarchive`, `FROM oci-archive:out.ociarchive`. |
| SELinux store relocated to `/usr/lib/selinux` | ✅ CONFIRMED | Containerfile: *"Relocate SELinux module store from `/var/lib/selinux` to `/usr/lib/selinux`… Placing the store under /usr (rather than /etc as fedora-bootc does) avoids 3-way merge overhead"* + `printf '\nstore-root=/usr/lib/selinux\n' >> ${NEWROOT}/etc/selinux/semanage.conf`. |
| systemd-firstboot masked; presets canonical; tmpfiles fixes | ✅ CONFIRMED | Containerfile: `ln -sf /dev/null ${NEWROOT}/usr/lib/systemd/system/systemd-firstboot.service` (comment: interactive prompts "hang on headless/VM boots"); `rm -rf ${NEWROOT}/etc/systemd/system/* && chroot ${NEWROOT} systemctl preset-all`; preset files in `images/bootc-os/rootfs/usr/lib/systemd/system-preset/80-bootc-os.preset`, `90-default.preset`, `99-default-disable.preset` (+ user-preset equivalents); `tmpfiles.d/home.conf` removed, `provision.conf` `/root`→`/var/roothome`. |
| OS package mix: Fedora 43 + Hummingbird pulp (priority 10) | ✅ CONFIRMED + quantified | `yum-repos/hummingbird.repo`: `[public-hummingbird-…]`, `baseurl=https://packages.redhat.com/api/pulp-content/public-hummingbird/{x86_64,aarch64,source}/`, `gpgcheck=0`, **`priority=10`**. Lockfile per-arch repoid breakdown (MAIN): `x86_64` 261 pkgs = 245 hum + 3 `fedora-43` + 13 `fedora-43-updates`; `aarch64` 258 pkgs = 244 hum + 3 `fedora-43` + 11 `fedora-43-updates`. → **~94 % Hummingbird-rebuilt, ~6 % Fedora 43 (includes whole kernel stack)**. |

## 2. Corrected / New findings

1. **Kernel provenance — corrected from "unverified" to "verified: NOT ARK".** Shipped kernel: `kernel-7.1.10-100.fc43`, `fedora-43-updates`. `VERSION` file in the image dir (`7.1.10`) simply mirrors the kernel major.minor.patch. The Magazine/SIG "ARK" statements are aspiration, not shipped content.
2. **NEW: F44 pin is in progress, visible in the repo.** Draft MR **!15860** `fix(images): pin hummingbird distro to Fedora 44` (source branch `bsherman/feat/fedora-43-to-44-upgrade`, commit 2026-08-26, MR opened 2026-08-27 13:06Z, `draft: true`, `merge_status: draft_status`). MR description: switches `hummingbird`'s `default_variant_repos` from `fedora-43.repo` → `fedora-44.repo` "following the documented Fedora-stream-switching workflow (previously applied to `rawhide`)". Only **two** image groups get full lockfile regeneration: `hummingbird-builder/hummingbird/default` and **`bootc-os/hummingbird/default`** (`allow_fedora_repos: true`); minio/minio-client get cosmetic GPG-key-only changes; "~287 other hummingbird images, and all `rawhide`-distro files, are unaffected".
3. **NEW: the branch lockfile is fully regenerated and would ship F44 content.** Branch `rpms.lock.yaml` (input-file-hash `a788c1fb…`): kernel `evr: 7.1.10-200.fc44`, `repoid: fedora-44-updates`, `sourcerpm: kernel-7.1.10-200.fc44.src.rpm`; grub2-2.12-64.fc44; repoids only `fedora-44*` + hum. **Caveat:** Hummingbird-rebuilt userspace is byte-identical versions to main (`dnf5 5.4.3.0-2.hum1`, `systemd 261.2-1.hum1`, `glibc 2.43-8.2.hum1`, `python3 3.14.7-1.hum1` on both) — the pulp side has **not** been visibly rebuilt for F44 yet (no matching MRs in `redhat/hummingbird/rpms` beyond routine dist-git updates).
4. **NEW (explains README.rawhide.md):** `images/bootc-os/README.rawhide.md` is the rawhide-flavor README generated by the docs pipeline (`images/variables.yml` → `readme_targets: rawhide: {filename: README.rawhide.md, registry: quay.io/hummingbird-rawhide}`). It is *not* evidence of a shipped rawhide bootc-os; render identical to `README.md` except registry `quay.io/hummingbird-rawhide/bootc-os:latest`. No `bootc-os--rawhide` Konflux component exists.
5. **NEW (rawhide distro already tracks F44):** On `main`, `images/variables.yml` has `default_variant_repos: rawhide: [fedora-44.repo]`; `hummingbird: [fedora-43.repo, hummingbird.repo]`. Per `documentation/operating/switching-fedora-streams.md`, the rawhide *distro* is intentionally pinned to the branched release (F44) while true Rawhide moved to F45; `yum-repos/fedora-rawhide.repo` exists but is currently unused by any distro mapping. `documentation/contributing/adding-images.md` line 267 states the same: "`rawhide` - Uses only Fedora Rawhide packages (`fedora-44.repo`)" / "`hummingbird` - Uses Fedora 43 + Hummingbird packages".
6. **NEW: no feed of newer OS images via the rawhide org.** `hummingbird-rawhide` org only contains *catalog-image* rawhide variants (e.g. `curl`, `hummingbird-builder` public) — bootc-os has no rawhide variant configured, so the rawhide org is not a path to a newer OS image either.
7. **Cadence caveat:** last published `latest` = 2026-08-26 19:30 UTC (digest `ad50d8ad…`, identical to first report's fetch). The three 08-27 lockfile MRs have not produced a published image as of the check (08-28 ~11:10 UTC).

## 3. Kernel + stream configuration (exact)

- **Kernel (shipped `latest`, from `main` lockfile):** `kernel-7.1.10-100.fc43` — package set `kernel`, `kernel-core`, `kernel-modules`, `kernel-modules-core`, all `repoid: fedora-43-updates`, sourced from `koji-s3-cache.hummingbird-project.io` mirror of `dl.fedoraproject.org/pub/fedora/linux/updates/43/Everything/{aarch64,x86_64}/Packages/k/kernel-7.1.10-100.fc43.{arch}.rpm`. **Not ARK, not rawhide, not fc44.**
- **Kernel (F44 branch, Draft MR !15860):** `kernel-7.1.10-200.fc44` from `fedora-44-updates` (same mirror, `updates/44/`).
- **Fedora stream config of bootc-os:** `rpms.in.yaml` → `fedora-43.repo` + `hummingbird.repo`. `yum-repos/` contains 5 files: `fedora-43.repo` (enabled sections `fedora-43`, `fedora-43-source`, `fedora-43-updates`, `fedora-43-updates-source`; no priority), `fedora-44.repo` (same shape for 44; used by rawhide distro), `fedora-rawhide.repo` (unused by current distro mapping), `hummingbird.repo` (`priority=10`, `gpgcheck=0`, x86_64/aarch64/source), `konflux-ci-rpm-lockfile-prototype-main-fedora-rawhide.repo` (COPR, lockfile tooling only).
- **Package counts:** lockfile `aarch64` 258 / `x86_64` 261 runtime packages (+ 339 source-RPM entries); ~94 % hummingbird-rebuilt; 14–16 Fedora 43 packages per arch (kernel stack + grub2 2.12-63/64.fc43*, shim 15.8-3, etc.).

## 4. Image inventory (Quay, anonymous, 2026-08-28 ~11:10 UTC)

| Org | Status | Verified repos (HTTP 200 = public, tags returned) |
|---|---|---|
| `hummingbird-community` | org listing not anonymously enumerable (API → HTTP 403 login page) | `bootc-os` ✅ (latest digest in §5), `minio` ✅, `minio-client` ✅ |
| `hummingbird-rawhide` | same 403 limitation | `hummingbird-builder` ✅ (digest `sha256:5538c8c9…`, 2026-08-26 05:54Z), `curl` ✅; `bootc-os` –, `go-1-27` – (HTTP 401 = no anonymous access; rawhide bootc-os not configured anywhere in the repo, see §1/§2.6) |
| `hummingbird` (mirror) | same 403 limitation | `curl` ✅ (public; digest `sha256:909d0d4e…`); `bootc-os` –, `hummingbird-builder` – (HTTP 401 — private or absent; docs describe this org as mirror of Red Hat supported images) |
| `hummingbird-ci` | n/a | `hummingbird-builder` ✅ (HTTP 200) — the builder base used by bootc-os |

## 5. Current `latest` state (check time)

- Registry: `quay.io/hummingbird-community/bootc-os`
- Tag: `latest` → manifest-list digest **`sha256:ad50d8ad73f21b639956d20f0891ccf0bf67e1809a1a8f58b76f4de5fb0e04d7`**, child manifests x86_64 `sha256:f69acee938…` + aarch64 `sha256:fa72553980…` (2/2 present)
- **Last modified: Wed, 26 Aug 2026 19:30:06 UTC** (Quay API `last_modified`)
- **Not rebuilt since**; 2026-08-27 and (to check time) 2026-08-28 have no push.

## 6. Verification limitations (stated explicitly)

- Quay org-listing endpoints (`/api/v1/repository/<org>?includeStats=false`) return HTTP 403 (Red Hat-hosted Quay login page) anonymously; org *inventory* beyond the probed repos could not be enumerated. Per-repo tag probes (HTTP 200/401) are the only anonymous signal; 401 means "no anonymous access" and cannot distinguish private-vs-nonexistent.
- GitLab MR search responses >~150 KB truncated on first attempt; retried with `per_page=50` (clean). GitLab is otherwise fully open anonymously.
- The `rpms` monorepo F44 rebuild status is inferred from MR titles/branches only (top ~100, updated-desc); no explicit "rebase to F44" MR existed in that window, and hum package versions in the containers F44-branch lockfile are unchanged — consistent with pulp rebuilding not yet landed publicly.
- The clone is `main` @ `79d84aa2` (2026-08-28 05:30 UTC), depth 1; branch/MR-level content fetched live from GitLab API.

## 7. Key facts sheet (delta vs first report)

| Fact (now) | Value | Evidence anchor |
|---|---|---|
| Shipped kernel | `kernel-7.1.10-100.fc43` from **fedora-43-updates** (both arches) — **NOT ARK** | rpms.lock.yaml lines 79–104 (main) |
| F44 pin MR | **!15860 Draft**, opened 2026-08-27; bootc-os lockfile fully regenerated → kernel `7.1.10-200.fc44` (fedora-44-updates) | GitLab API MR 15860 + branch raw lockfile |
| rawhide distro pin | `fedora-44.repo` on main (rawhide≠rolling since F44 branch); fedora-rawhide.repo unused | images/variables.yml; switching-fedora-streams.md |
| bootc-os variants | `hummingbird` only; **no rawhide/community-F44 image published or configured** | properties.yml; rendered.yml (0× bootc-os--rawhide); Quay probes |
| Package provenance | ~94 % hum-rebuilt (pulp, prio 10), ~6 % Fedora 43 incl. kernel | lockfile per-arch repoid counts |
| Latest image | digest `ad50d8ad…`, last push 2026-08-26 19:30 UTC, **no 08-27/08-28 push** | Quay tag API |
