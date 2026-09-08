# Bluefin Multimedia — Detailed Findings (Fedora 44)

> **Scope:** `projectbluefin/bluefin` (NOT `ublue-os/bluefin`); current `main` at HEAD 2026-08-29, `Containerfile` `ARG FEDORA_MAJOR_VERSION="44"` (`Containerfile:2`). All citations are that clone at `/tmp/opencode/bluefin`.

---

## 1. Which repos does Bluefin use for multimedia?

| Repo | ID | Source | When enabled | When disabled | GPG |
|------|----|--------|--------------|---------------|-----|
| **negativo17 fedora-multimedia** | `fedora-multimedia` | `https://negativo17.org/repos/fedora-multimedia.repo` → `baseurl https://negativo17.org/repos/multimedia/fedora-$releasever/$basearch/` (`curl` fetch: single `[fedora-multimedia]` section `enabled=1`, gpgkey `https://negativo17.org/repos/RPM-GPG-KEY-slaanesh`, `gpgcheck=1`, `repo_gpgcheck=0`, 6h metadata) | `build_files/base/03-packages.sh:26-32` — if `dnf5 repolist` lacks it, `dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"` else `setopt fedora-multimedia.enabled=1` fallback; then `dnf5 config-manager setopt fedora-multimedia.priority=90` (`03-packages.sh:32`) | `build_files/shared/disable-repos.sh:10-13` → `build_files/base/17-cleanup.sh:47-48` (`disable_third_party_repos`). Loop disables `fedora-multimedia`, `tailscale`, `fedora-cisco-openh264`. Validated by `build_files/shared/validate-repos.sh:68`. **Final image ships the repo file but with `enabled=0`.** | `RPM-GPG-KEY-slaanesh` fetched via repofile |
| **RPM Fusion free + nonfree** | `rpmfusion-free` / `rpmfusion-nonfree` (transient `_Build` suffix) | `build_files/base/04-install-kernel-akmods.py:104-146` `write_rpmfusion_repos()` writes ephemeral `/etc/yum.repos.d/rpmfusion-free-build.repo` + `rpmfusion-nonfree-build.repo` with `baseurl https://download1.rpmfusion.org/...`, `enabled=1`, `gpgcheck=0`, `skip_if_unavailable=1`, `metadata_expire=3d` | Only inside `04-install-kernel-akmods.py` to install `v4l2loopback` (`install_v4l2loopback`, `04-install-kernel-akmods.py:149-155`) | Deleted immediately after use (`04-install-kernel-akmods.py:314-315` `.unlink(missing_ok=True)`). `disable-repos.sh:22-24` also sweeps any leftover `rpmfusion-*.repo`. Not a user-visible multimedia repo. | `gpgcheck=0` (transient) |
| `fedora-cisco-openh264` | `fedora-cisco-openh264` | Fedora's shipped Cisco OpenH264 repo | Pre-existing in Silverblue base | Disabled alongside multimedia in `disable-repos.sh:10` | Fedora |

**No other multimedia repo.** No `rpmfusion` codec install, no `unitedRPMs`, no custom mesa COPR. The entire non-FOSS codec story hangs on the single negativo17 repo.

### Priority

```
dnf5 config-manager setopt fedora-multimedia.priority=90   # 03-packages.sh:32
```

Default Fedora repos have priority 99 (lower number = higher priority), so negativo17 at 90 wins candidate selection over base/updates without `--repo` filtering. Bluefin also explicitly enables installs with `--enablerepo='fedora-multimedia'` / `--repo='fedora-multimedia'` so the need is double-covered.

### Containerfile cache note

Stage 1 (`Containerfile:65-90`) is tagged `BUILD_FILES_SHA` — any edit to `03-packages.sh` or `base.toml` busts the package layer cache (20-80 min rebuild). This is why multimedia lives in the single `03-packages.sh` rather than a standalone `25-multimedia.sh`.

---

## 2. Package lists

### 2a. `multimedia_overrides` — the "less-crippled" mesa/VA swaps

`build_files/packages/base.toml:12-28`:

```toml
[multimedia_overrides]
packages = [
    "intel-gmmlib",
    "intel-mediasdk",
    "intel-vpl-gpu-rt",
    "libheif",
    "libva",
    "libva-intel-media-driver",
    "mesa-dri-drivers",
    "mesa-filesystem",
    "mesa-libEGL",
    "mesa-libGL",
    "mesa-libgbm",
    "mesa-vulkan-drivers",
]
```

- Comment on `base.toml:13`: *"Replace mesa and friends with less-crippled versions from negativo17/fedora-multimedia. Versions are pinned with `dnf5 versionlock` after install."*
- Header comment in `03-packages.sh:17-20`: mitigates <https://bugzilla.redhat.com/show_bug.cgi?id=2332429> and swaps `OpenCL-ICD-Loader → ocl-icd` on F42 (not F44).

### 2b. Inline multimedia install

`build_files/base/03-packages.sh:56-62` (single transaction, `--enablerepo` both tailscale + multimedia):

```bash
dnf5 -y install \
    --enablerepo='tailscale-stable' \
    --enablerepo='fedora-multimedia' \
    -x PackageKit* \
    "${FEDORA_PACKAGES[@]}" \
    tailscale \
    ffmpeg{,-libs} libavcodec @multimedia gstreamer1-plugins-{bad-free,bad-free-libs,good,base} lame{,-libs} libfdk-aac libjxl ffmpegthumbnailer
```

Expanded:

| Package | Notes |
|---------|-------|
| `ffmpeg`, `ffmpeg-libs`, `libavcodec` | Brace-expand `ffmpeg{,-libs}`; negativo17 full builds (epoch `1:`). Fedora proper only has `*-free`. |
| `@multimedia` | Fedora comps group (`comps-f43.xml.xz` in repo). Pulls the distro's "multimedia" group (pulls extra codecs/fonts). Not list-enumerable without `dnf group info`; excluded from pluto which enumerates explicitly so `assert_packages_present` works. |
| `gstreamer1-plugins-bad-free`, `gstreamer1-plugins-bad-free-libs`, `gstreamer1-plugins-good`, `gstreamer1-plugins-base` | **Foss-only split naming** — Fedora's packaging splits `bad` into `-bad-free`. See §4 for F44 caveat (negativo17 now obsoletes the split). |
| `lame`, `lame-libs` | MP3 |
| `libfdk-aac` | Fraunhofer AAC (negativo17 only) |
| `libjxl` | JPEG-XL |
| `ffmpegthumbnailer` | Video thumbnails (Bluefin removed `totem-video-thumbnailer` → `excluded` list `base.toml:131`) |
| `pipewire-libs-extra` etc. | **Not** in the inline line — lives in `[fedora]` `base.toml:84` (`pipewire-libs-extra`) and is asserted as negativo17-sourced via `20-tests.sh:98`. |

**Not installed by Bluefin but by pluto:** `libavdevice`, `libavfilter`, `libavformat`, `libavutil`, `libpostproc`, `libswresample`, `libswscale`, `gstreamer1-plugins-ugly`, `gstreamer1-plugin-libav` — pluto makes the full ffmpeg dep chain explicit and adds ugly/libav (see §7).

### 2c. `excluded` side-channel

`base.toml:115-133` removes `totem-video-thumbnailer` (replaced by `ffmpegthumbnailer`), `gnome-software` etc. — not multimedia per se but the thumbnailer swap is.

---

## 3. Script logic summary

### `03-packages.sh` (`build_files/base/03-packages.sh:1-83`)

```
F42-only workaround          rpm -E %fedora == 42 → swap OpenCL-ICD-Loader → ocl-icd
                            (03-packages.sh:21-24)

Enable negativo17 repo       repolist check → addrepo from negativo17.org OR setopt enabled=1
                             + priority=90                                       (26-32)

multimedia_overrides sync    read-packages multimedia_overrides → 12 pkgs →
                             dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
                             dnf5 versionlock add "${OVERRIDES[@]}"               (35-37)

Fedora packages              read-packages fedora (+ fedora_v${FEDORA_MAJOR_VERSION})
                             + tailscale repo + multimedia inline list →
                             single dnf5 -y install --enablerepo tailscale+multimedia
                                   "${FEDORA_PACKAGES[@]}" tailscale ffmpeg…      (46-62)

COPR isolation                copr_install_isolated "ublue-os/packages" "uupd"    (65-66)
                             (enable→immediate disable→install --enablerepo; see copr-helpers.sh:1-43)

Exclude purge                 read-packages excluded → remove_excluded_packages   (70-71)
```

**No `gdk-pixbuf` loader cache rebuild** in this file — Bluefin does it in `05-override-install.sh:48-49` (`gdk-pixbuf-query-loaders-64 --update-cache`) for the base image's loaders (heif/jxl etc. benefit incidentally). Pluto adds an explicit rebuild after its multimedia install.

### `disable-repos.sh` / `17-cleanup.sh` / `clean-stage.sh` / `validate-repos.sh`

- `17-cleanup.sh:47-48` sources `disable-repos.sh` and calls `disable_third_party_repos`:
  - Named: `fedora-multimedia`, `tailscale`, `fedora-cisco-openh264` → `sed s/enabled=1/enabled=0/` (`disable-repos.sh:10-14`)
  - Glob `_copr:*.repo` (`:17-19`)
  - Glob `rpmfusion-*.repo` (`:22-24`)
  - `fedora-coreos-pool.repo` if present (`:27-29`)
- `clean-stage.sh:13-14` clears the versionlock and dnf keepcache (`dnf5 config-manager setopt keepcache=0` + `dnf5 versionlock clear`). The lock only lives for the build.
- `validate-repos.sh:52-87` runs in Stage 2 (`Containerfile:151`) and **fails the build** if any `negativo17-fedora-multimedia.repo`, `tailscale.repo`, `fedora-cisco-openh264.repo`, COPR or rpmfusion repo still has `enabled=1`. `fedora-updates-testing` is also checked (allowed only for `beta`).

Net effect: **Bluefin's final image has `fedora-multimedia` present but disabled** — codec updates don't come via `dnf5 update` without manual `config-manager setopt enabled=1`. (Pluto diverges: keeps it `enabled=1` intentionally for runtime codec updates; see §7.)

### `04-install-kernel-akmods.py` (RPM Fusion tangent)

Not multimedia per se, but note: the only other third-party codec-adjacent repo bluefin ever touches is the transient RPM Fusion free/nonfree pair used solely for `v4l2loopback` kernel deps, immediately unlinked. It does not provide codecs.

### `20-tests.sh:91-105`

Build-time smoke test asserting 7 packages' `VENDOR` contains `negativo17.org`:

```bash
NEGATIVO=(ffmpeg libheif libva mesa-filesystem pipewire-libs-extra x264-libs x265-libs)
rpm -q --qf "%{NAME} %{VENDOR}" "${package}" | grep -q "negativo17\.org"
```

`x264-libs`/`x265-libs` are *transitive deps* of ffmpeg/gstreamer, not in `multimedia_overrides`; `pipewire-libs-extra` is from `[fedora]` but rebuilt by negativo17 (so the vendor check catches it). This is the user-visible proof the repo actually provided the packages.

---

## 4. Fedora 44 specific notes

| Concern | Handling |
|---------|----------|
| **`FEDORA_MAJOR_VERSION` ARG** | `Containerfile:2,57,116` = `44`; `BASE_IMAGE=quay.io/fedora-ostree-desktops/silverblue` (`:3`). Stage 1 uses `BASE_IMAGE:${FEDORA_MAJOR_VERSION}` so the base is `silverblue:44`. |
| **Version-specific fedora packages** | Generic loader: `readarray -t _ver_pkgs < <($READ_PKGS "$PKGS_TOML" "fedora_v${FEDORA_MAJOR_VERSION}" 2>/dev/null \|\| true)` (`03-packages.sh:49`). Missing section is silently empty (`|| true`). |
| **`[fedora_v44]` content** | `base.toml:110-113`: only `gnupg2-scdaemon`. (F42 had `evolution-ews-core`; F43 both `evolution-ews-core` + `gnupg2-scdaemon` — evolution migrates out by F44.) **No multimedia delta for F44.** |
| **F42-only hack** | `03-packages.sh:21-24` `if [[ "$(rpm -E %fedora)" == "42" ]]` swap `OpenCL-ICD-Loader → ocl-icd`; comment says remove when F42 dropped, *"F43 is not affected"*. Irrelevant on F44. |
| **GStreamer `bad-free` split deprecation** | Bluefin still installs `gstreamer1-plugins-bad-free` / `bad-free-libs` (`03-packages.sh:62`). Upstream change (F43 era, verified by pluto 2026-08-28): negativo17 now ships a single `gstreamer1-plugins-bad` (epoch `1:1.26.x`) that `Obsoletes: gstreamer1-plugins-bad-free`. On F44 `dnf5 -y install …` will still resolve because the old names `Obsolete`-provide or dnf maps them, but **pluto switched to `gstreamer1-plugins-bad` / `ugly` / `plugin-libav`** and added a vendor-assert to catch the slip (see `multimedia.toml` header comment). If azul transplanted Bluefin's inline string verbatim to Hummingbird on F44 it would still work today but relies on Obsoletes; pluto's unsplit naming is the forward-compatible form. Similarly `gstreamer1-libav` → `gstreamer1-plugin-libav` rename. |
| **Negativo17 F44 availability** | Repo URL uses `$releasever` → `.../fedora-$releasever/...`, so F44 content is auto-picked up once negativo17 publishes it. No per-version repofile handling. Validated that `fedora-multimedia.repo` today still serves via `.../fedora-44/...` on negativo17 infra (repo fetch returns 200). |

**In short:** no F44-specific multimedia logic; the path is version-agnostic. The only risk on F44 is stale gstreamer package names.

---

## 5. Repo handling mechanics (deep dive)

- **`distro-sync --repo='fedora-multimedia' --skip-unavailable`** (`03-packages.sh:36`): re-syncs already-installed multilib/mesa/libva packages to the negativo17 builds. `--repo` restricts the *entire transaction* to that repo (affects deps). `--skip-unavailable` means if an override doesn't exist for this Fedora release, it doesn't fail the build (important during version bumps).
- **`versionlock`** (`:37` then `clean-stage.sh:14` `clear`): locks the 12 overrides so later `dnf5 update` / `distro-sync` in the same build doesn't downgrade them back to Fedora's builds. Cleared at the end, so the stranded lockfile isn't shipped; on the live booted system there's no lockfile — updates will prefer negativo17 by `priority=90`, but if Fedora ever rebases mesa to a higher EVR without negativo17 catching up quickly, a `dnf update` could theoretically revert (priority vs EVR interplay; Bluefin accepts this).
- **`dnf5 copr enable/disable/install --enablerepo`** pattern (`copr-helpers.sh:33-42`): every COPR install is *isolated* — repo is disabled before the `dnf5 install --enablerepo` call, preventing a malicious COPR from injecting fake Fedora packages (see header comment). Multimedia is not a COPR, so it uses the simpler `addrepo` + `priority` + `--enablerepo` pattern.
- **`priority=90` vs versionlock**: both are used — priority for the multimedia ffmpeg/gstreamer stack (runtime preference), versionlock for the mesa/libva swap (build-time pin). Priority alone would be sufficient for mesa too given negativo17's `Epoch: 1` bump, but Blues chose the belt-and-braces approach.

---

## 6. File map

| File | Role |
|------|------|
| `Containerfile:1-6,53-90,112-154` | Declares `FEDORA_MAJOR_VERSION=44`, Stage 1 installs (`03/04/05-*.sh`), Stage 2 validates/cleans |
| `build_files/base/03-packages.sh:1-83` | **Main multimedia logic** — repo enable, overrides distro-sync+versionlock, inline ffmpeg/gstreamer install |
| `build_files/packages/base.toml:1-133` | Package manifest — `[multimedia_overrides]` (12), `[fedora]` (common), `[fedora_v44]` (gnupg2-scdaemon), `[excluded]` |
| `build_files/shared/read-packages` | Python `tomllib` reader for the TOML (also used by COPR helpers, tests) |
| `build_files/shared/disable-repos.sh:1-30` | Disables `fedora-multimedia` et al. at cleanup |
| `build_files/shared/validate-repos.sh:1-120` | Fail-closed lint that no third-party repo stayed enabled |
| `build_files/shared/clean-stage.sh:1-32` | `versionlock clear` + cache/cache-cleanup |
| `build_files/shared/copr-helpers.sh:1-43` | Isolated COPR install (security boundary, not multimedia) |
| `build_files/base/04-install-kernel-akmods.py:104-315` | Transient RPM Fusion repos for `v4l2loopback` only |
| `build_files/base/20-tests.sh:91-105` | Vendor assert for 7 negativo17 packages |
| `tests/unit/03-packages_test.bats` | Mocks dnf5/rpm to test F42/F43/F44 branching, OpenCL swap, copr call |
| `tests/unit/disable-repos_test.bats` | Asserts `disable_third_party_repos` flips `enabled=1→0` |
| `tests/unit/validate-repos_test.bats` | `check_repo_file` unit coverage |
| `tests/unit/clean-stage_test.bats` | Asserts `keepcache=0` + `versionlock clear` |

---

## 7. Comparison to pluto's current `25-multimedia.sh` approach

> Sources: `build/25-multimedia.sh`, `build/packages/multimedia.toml`, `build/scripts/package-lib.sh`, `build/clean-stage.sh`, `Containerfile`. Line refs are that repo.

| Dimension | Bluefin (`03-packages.sh` + `base.toml`) | Pluto (`25-multimedia.sh` + `multimedia.toml`) | Assessment |
|-----------|-------------------------------------------|-------------------------------------------------|------------|
| **File layout** | Multimedia inline in the monolithic `03-packages.sh` (single dnf transaction with Fedora base + tailscale). | Dedicated `25-multimedia.sh` (runs in its own `RUN` layer after `20-base.sh`), own `multimedia.toml`. | Pluto cleaner separation & caching (can rebuild multimedia layer without re-running base). Parity with bluefin's `10-build.sh/20-base.sh/40-niri.sh` split in pluto. |
| **Override package list** | 12 incl. `intel-vpl-gpu-rt` (`base.toml:12-28`) | 11 excl. `intel-vpl-gpu-rt` (`multimedia.toml:12-24`) | Pluto missing `intel-vpl-gpu-rt` (Intel VPL runtime). On Intel iGPU systems this is the QSV/VPL backend — absence may affect QSV encode/decode path. Recommend adding unless Hummingbird base already provides it. |
| **Override install method** | `dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"` (`03-packages.sh:36`) — `--repo` locks whole txn to that repo; `--skip-unavailable` tolerates missing overrides during version bumps; requires pkg already installed (or it errors — not an issue on Silverblue which ships mesa/intel libs). | `dnf5 install -y --enablerepo='fedora-multimedia' "${OVERRIDES[@]}"` (`25-multimedia.sh:53`) — header comment explains why: Hummingbird base is minimal and lacks `intel-mediasdk`/`intel-gmmlib`/`libva-intel-media-driver` preinstalled so `distro-sync` would fail; also `--repo` would block cross-repo deps (neg17 `x265-libs` needs `numactl-libs` from Fedora). `--enablerepo` with `priority=90` + negativo's `Epoch:1` still wins. | **Pluto's change is correct for Hummingbird**; if pluto ever rebases onto Silverblue, either form works. |
| **GStreamer naming** | `gstreamer1-plugins-{bad-free,bad-free-libs,good,base}` (`03-packages.sh:62`) — Fedora's FOSS split. | `gstreamer1-plugins-{base,good,bad,ugly}` + `gstreamer1-plugin-libav` (`multimedia.toml:28-35`) — negativo17 unsplit naming (epoch 1). Comment documents rename `gstreamer1-libav → gstreamer1-plugin-libav` verified 2026-08-28. | **Pluto is forward-compatible for F44**; Bluefin's names work via Obsoletes today but are technically stale. Neither installs `-ugly-free` split vs `ugly` nuance — pluto's `ugly` is correct for non-FOSS. |
| **FFmpeg dep chain explicitness** | `ffmpeg{,-libs} libavcodec @multimedia` — relies on `@multimedia` group + ffmpeg's `Requires` to pull `libavdevice/filter/format/util/postproc/swresample/swscale`. | Enumerates all `libav*` + `libpostproc/swresample/swscale/libfdk-aac` explicitly (`multimedia.toml:14-27`), deliberately avoids `@multimedia` group so `assert_packages_present` can verify each. | Pluto more auditable; avoids opaque group membership changes. |
| **`@multimedia` group** | Installed (`03-packages.sh:62`) | Not used | Pluto docs note the rationale: groups aren't `rpm -q`-verifiable. |
| **`lame-libs` etc.** | `lame{,-libs}` + `libjxl` + `ffmpegthumbnailer` inline | Same plus `libfdk-aac` already in explicit list; `lame`/`lame-libs`/`libjxl`/`ffmpegthumbnailer` retained | Same coverage. |
| **Vendor assert** | In tests (`20-tests.sh:93-104`): 7 names checked post-build (`ffmpeg libheif libva mesa-filesystem pipewire-libs-extra x264-libs x265-libs`), failure aborts test. | In build itself (`25-multimedia.sh:78-82`): `assert_vendor "multimedia" "negativo17.org"` over `[vendor_assert]` manifest (`ffmpeg libavcodec libfdk-aac mesa-dri-drivers mesa-vulkan-drivers` — 5 names, plus `libavcodec`/`libfdk-aac` gate). Fails the build layer immediately. | Both cover it; pluto's in-layer gate fails faster (before the image is committed), bluefin's is only a final-stage test. Pluto's set overlaps but omits `libheif/libva/pipewire-libs-extra/x264/x265` — could broaden to match bluefin's list for extra slip detection. |
| **`gdk-pixbuf` cache** | `gdk-pixbuf-query-loaders-64 --update-cache` in `05-override-install.sh:49` (runs after all Stage 1 installs) | Explicit rebuild right after multimedia install (`25-multimedia.sh:68`) | Equivalent; pluto's placement is arguably safer (runs right when `libheif`/`libjxl` loaders land). |
| **Repo lifecycle — final-image `enabled`?** | Disabled via `disable-repos.sh` → `validate-repos.sh` expects `fedora-multimedia.repo` `enabled=0` on final image. | **Kept enabled** (`25-multimedia.sh:17-19` header: *"intentionally KEPT enabled ... runtime codec updates — same as bluefin"* — comment is inaccurate about bluefin, but the intent is pluto's divergence). `clean-stage.sh` does NOT disable it (pluto's `clean-stage.sh` is bluefin's minus the `disable-repos.sh` call — it only does `versionlock clear` + cache cleanup). No `validate-repos.sh` in pluto that would fail on it. | Intentional divergence. Trade-off: enabled repo gives `dnf update` automatic codec updates inside the booted image but means a compromised negativo17 repo could be pulled at update time (same as if the user re-enabled it). Bluefin chooses defense-in-depth (fail-closed). If pluto wants bluefin parity, it would either disable the repo and tell users to enable on demand, or add a `validate-repos.sh`-style check that allows it. Current behavior matches pluto's stated design. |
| **`versionlock` lifecycle** | Add after distro-sync (`03-packages.sh:37`), clear in `clean-stage.sh:14` (same as pluto). | Same (`25-multimedia.sh:55` add, `clean-stage.sh:12` clear). | Identical. |
| **`priority=90`** | Yes (`03-packages.sh:32`) | Yes (`25-multimedia.sh:35`) | Identical. |
| **F42 `ocl-icd` swap** | Present, F42-only | Not needed (Hummingbird base not affected; pluto's base has no mesa conflict). | N/A. |
| **Extra pluto concern: missing comps `totem-video-thumbnailer` exclusion** | Bluefin `excluded` drops `totem-video-thumbnailer` because `ffmpegthumbnailer` replaces it. | Pluto's `base.toml`/`multimedia.toml` doesn't list either excluded, but `ffmpegthumbnailer` is installed — on Hummingbird the totem thumbnailer may not even be present; if it is, both can coexist. Low risk. | Non-issue unless Hummingbird pulls totem thumbnailer in base. |

### Quick recommendation delta for pluto

1. **Add `intel-vpl-gpu-rt`** back to `multimedia_overrides` unless Hummingbird deliberately ships an alternative QSV runtime.
2. **Fix bluefin comment copy** in `25-multimedia.sh:17-19` — bluefin disables the repo; pluto's "same as bluefin" is false. Either own the divergence explicitly or match bluefin's disable + `validate-repos` lint.
3. **Broaden `vendor_assert`** to include `libheif`, `libva`, `pipewire-libs-extra`, `x264-libs`, `x265-libs` (bluefin's set) so repo-priority slip on those non-ffmpeg packages is also caught.
4. Keep the `install --enablerepo` divergence over `distro-sync --repo` — it's correct for Hummingbird.

---

## 8. Gotchas / open questions

- **`disable-repos.sh:12` sed is global** (`s@enabled=1@enabled=0@g`) — flips every `enabled=1` in the file, including per-section `[fedora-multimedia]`, `[fedora-multimedia-source]`, `[fedora-multimedia-debug]`. Harmless since source/debug are already `0`, but confirms pluto's "repo file present but disabled" ends with all sections disabled.
- No negativo17 GPG trust bootstrap is explicit in Bluefin — it relies on the repofile's `gpgkey=` URL fetched over TLS. No detached key import step to compare with pluto.
- Fedora 44 negativo17 package availability: the `intel-vpl-gpu-rt` override was added for Intel iGPU QSV, but if negativo17 dropped `intel-gmmlib`/`intel-mediasdk` for F44 (Intel moved to `libvpl`/VPL), `distro-sync --skip-unavailable` would silently skip them — vendor assert wouldn't fire because the package was never installed. Worth a manual `dnf --repo` dry-run on F44 to confirm all 12 overrides still exist upstream.
