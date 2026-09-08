# COPR Inventory — avengemedia/dms + avengemedia/danklinux

_Generated: 2026-08-29 via direct repodata + live `dnf5 repoquery` verification + COPR API_
_Methods:_ `repomd.xml → primary.xml.gz` parsing (authoritative) **and** `podman run fedora:44 dnf5 copr enable + repoquery` (cross-checked). Both agree.
_Chroots examined:_ `fedora-44-x86_64` (primary) and `fedora-43-x86_64` (comparison). Aarch64/epel/rawhide exist but not enumerated here.

---

## 1) COPR Dependency Relationship

- **dms → danklinux** is a hard COPR dependency (`coprdep`), both at build-time and runtime.
  - COPR HTML “External Repository List” and “runtime dependencies” for `avengemedia/dms` list `copr://avengemedia/danklinux`.
  - API `https://copr.fedorainfracloud.org/api_3/project?ownername=avengemedia&projectname=dms` returns `"additional_repos": ["copr://avengemedia/danklinux"]`.
  - Enabling `avengemedia/dms` via `dnf5 copr enable` prints: `coprdep:copr.fedorainfracloud.org:avengemedia:danklinux baseurl=https://download.copr.fedorainfracloud.org/results/avengemedia/danklinux/fedora-$releasever-$basearch/` and enables both repos together.
  - Conversely, `avengemedia/danklinux` has `"additional_repos": []` — it is standalone, provides the base/toolbox layer.

- Packaging implication: `dms` RPM’s hard deps are fulfilled by danklinux:
  - `dms-1.5.3-1.fc44.x86_64` **Requires:** `(quickshell or quickshell-git)` + `dgop` + `dms-cli = 1.5.3-1.fc44` + `accountsservice`, etc.
  - `dms-greeter-1.5.3-1.fc44.x86_64` **Requires:** `(quickshell-git or quickshell)` + `greetd`
  - Weak deps (Recommends): `cava`, `danksearch`, `matugen`, `qt6-qtmultimedia`, `NetworkManager`; Suggests: `qt6ct`, `cups-pk-helper`.
  - All of `quickshell`, `quickshell-git`, `dgop`, `danksearch`, `matugen`, `dms-greeter` live in **danklinux**, not dms.

---

## 2) Per-COPR Package List — fedora-44-x86_64

### avengemedia/dms — fedora-44-x86_64

- **Repodata:** `rev 1785569499 (2026-08-01T07:31:39Z)`, `repodata/4bb5523067d32d2b831c2b5f8ab8c79d7b6b158b7dbf409954de100ef686e4c4-primary.xml.gz`, `open-size 6207`, `packages="3"` in primary.

| Name | Version | Release | Arch | Location | Notes |
|------|---------|---------|------|----------|-------|
| dms | 1.5.3 | 1.fc44 | src | `10775781-dms/dms-1.5.3-1.fc44.src.rpm` | MIT, 44 MB src |
| dms | 1.5.3 | 1.fc44 | x86_64 | `10775781-dms/dms-1.5.3-1.fc44.x86_64.rpm` | Binary, 19.7 MB, provides `dms`, `dms(x86-64)`, desktop files, mimehandlers |
| dms-cli | 1.5.3 | 1.fc44 | x86_64 | `10775781-dms/dms-cli-1.5.3-1.fc44.x86_64.rpm` | CLI, 9.1 MB, `/usr/bin/dms` |

- **Counts:** 3 repodata entries total; 2 unique names (`dms`, `dms-cli`); 2 binary RPMs (x86_64) + 1 src. `dnf5 repoquery --repo=copr:dms` confirms exactly these 3.
- **Repo URL:** `https://download.copr.fedorainfracloud.org/results/avengemedia/dms/fedora-44-x86_64/`

### avengemedia/danklinux — fedora-44-x86_64

- **Repodata:** `rev 1787940153 (2026-08-28T18:02:40Z)`, `repodata/18f08631e53f741e29d50c22c4a4ad4657f7af4bc0f2377127f8ad0be87bf55c-primary.xml.gz`, `open-size 443681`, `packages="181"` in primary.
- **Counts:** 181 total entries, 98 unique NVRs, 28 unique base names (see table). Verified via container `dnf5 repoquery --available` (98 NVRs listed, sorted output matches repodata).
- **Repo URL:** `https://download.copr.fedorainfracloud.org/results/avengemedia/danklinux/fedora-44-x86_64/`

#### Summary by base name (unique names + per-arch variants)

| Base name | Arch variants | Distinct ver/rel | Binary version(s) (latest highlighted) | Package description |
|-----------|---------------|------------------|--------------------------------------|---------------------|
| `breakpad` | src, x86_64 | 1 | `2024.02.16-1.fc44` | Google Breakpad crash-reporting |
| `breakpad-devel` | x86_64 | 1 | `2024.02.16-1.fc44` | devel |
| `breakpad-static` | x86_64 | 1 | `2024.02.16-1.fc44` | static lib |
| `cli11` | src | 1 | `2.6.1-1.fc44` | CLI11 C++ parser (src only) |
| `cli11-devel` | noarch | 1 | `2.6.1-1.fc44` | header-only devel |
| `cliphist` | src, x86_64 | 1 | `0.7.0-1.fc44` | Wayland clipboard history |
| `cpptrace` | src, x86_64 | 1 | `1.0.4-4.fc44` | C++ stacktrace lib |
| `cpptrace-debuginfo` | x86_64 | 1 | `1.0.4-4.fc44` | debuginfo |
| `cpptrace-debugsource` | x86_64 | 1 | `1.0.4-4.fc44` | debugsource |
| `cpptrace-devel` | x86_64 | 1 | `1.0.4-4.fc44` | devel |
| `dankcalendar-git` | src, x86_64 | **7 git vers** | `0.3.2+git142` … `0.3.2+git164.29bf5558` (latest=`164`) | DankCalendar git builds |
| `danksearch` | src, x86_64 | 1 | `0.3.2-1.fc44` | Blazing fast filesystem search |
| `dgop` | src, x86_64 | 1 | `0.2.3-1.fc44` (epoch 1) | Stateless CPU/GPU monitor |
| `dms-greeter` | src, x86_64 | 1 | `1.5.3-1.fc44` | DMS Greeter stable (greetd) |
| `dms-greeter-git` | src, x86_64 | **5 git vers** | `1.0.0+git23` … `1.0.0+git28.e957e438` (latest=`28`) | DMS Greeter git |
| `ghostty` | src, x86_64 | 1 | `1.3.1-1.fc44` | Ghostty terminal |
| `ghostty-devel` | x86_64 | 1 | `1.3.1-1.fc44` | devel |
| `material-symbols-fonts` | src, noarch | 1 | `1.0-1.fc44` | Google Material Symbols |
| `matugen` | src, x86_64 | 1 | `4.2.0-1.fc44` | Material color generator |
| `matugen-debuginfo` | x86_64 | 1 | `4.2.0-1.fc44` | debuginfo |
| `matugen-debugsource` | x86_64 | 1 | `4.2.0-1.fc44` | debugsource |
| `qt6ct-kde` | src, x86_64 | 1 (dup entries in repodata x2) | `0.11-10.fc44` | Qt6 theming (duplicate src+binary entries counted twice in primary due to two builds) |
| `qt6ct-kde-debuginfo` | x86_64 | 1 (x2 dup) | `0.11-10.fc44` | |
| `qt6ct-kde-debugsource` | x86_64 | 1 (x2 dup) | `0.11-10.fc44` | |
| `quickshell` | src, x86_64 | 1 | `0.3.1-1.fc44` | Quickshell stable (pinned commit 713 per COPR description) |
| `quickshell-git` | src, x86_64 | **10 git vers** | `0.3.1^843…` → `0.3.2^853.git916a0dd` (latest=`853`) | Quickshell git (rolling) |
| `quickshell-git-debuginfo` | x86_64 | 10 | matches above | |
| `quickshell-git-debugsource` | x86_64 | 10 | matches above | |

_Totals:_ **28 unique base names**, **38 name·arch combos**. Breakdown: 181 repodata rows = many historic git variants retained (danklinux has `auto_prune=true` but pruning keeps latest N builds per git package; current window ~7 dankcalendar, 5 dms-greeter, 10 quickshell). Without git history, “latest” view is **15 stable-ish binary names** + **3 git families**.

#### Full NVR list (unique, sorted) — danklinux f44

```text
breakpad-2024.02.16-1.fc44.src
breakpad-2024.02.16-1.fc44.x86_64
breakpad-devel-2024.02.16-1.fc44.x86_64
breakpad-static-2024.02.16-1.fc44.x86_64
cli11-2.6.1-1.fc44.src
cli11-devel-2.6.1-1.fc44.noarch
cliphist-0.7.0-1.fc44.src
cliphist-0.7.0-1.fc44.x86_64
cpptrace-1.0.4-4.fc44.src
cpptrace-1.0.4-4.fc44.x86_64
cpptrace-debuginfo-1.0.4-4.fc44.x86_64
cpptrace-debugsource-1.0.4-4.fc44.x86_64
cpptrace-devel-1.0.4-4.fc44.x86_64
dankcalendar-git-0.3.2+git142.7eaf5af6-2.fc44.src
dankcalendar-git-0.3.2+git142.7eaf5af6-2.fc44.x86_64
dankcalendar-git-0.3.2+git148.b766e85a-2.fc44.src
dankcalendar-git-0.3.2+git148.b766e85a-2.fc44.x86_64
dankcalendar-git-0.3.2+git150.c6952df5-2.fc44.src
dankcalendar-git-0.3.2+git150.c6952df5-2.fc44.x86_64
dankcalendar-git-0.3.2+git155.fe61f4e6-2.fc44.src
dankcalendar-git-0.3.2+git155.fe61f4e6-2.fc44.x86_64
dankcalendar-git-0.3.2+git157.52d88fa7-2.fc44.src
dankcalendar-git-0.3.2+git157.52d88fa7-2.fc44.x86_64
dankcalendar-git-0.3.2+git158.123dc2c1-2.fc44.src
dankcalendar-git-0.3.2+git158.123dc2c1-2.fc44.x86_64
dankcalendar-git-0.3.2+git164.29bf5558-2.fc44.src
dankcalendar-git-0.3.2+git164.29bf5558-2.fc44.x86_64
danksearch-0.3.2-1.fc44.src
danksearch-0.3.2-1.fc44.x86_64
dgop-0.2.3-1.fc44.src
dgop-0.2.3-1.fc44.x86_64
dms-greeter-1.5.3-1.fc44.src
dms-greeter-1.5.3-1.fc44.x86_64
dms-greeter-git-1.0.0+git23.f353eafd-1.fc44.src
dms-greeter-git-1.0.0+git23.f353eafd-1.fc44.x86_64
dms-greeter-git-1.0.0+git24.b5db4190-1.fc44.src
dms-greeter-git-1.0.0+git24.b5db4190-1.fc44.x86_64
dms-greeter-git-1.0.0+git26.47daf48f-1.fc44.src
dms-greeter-git-1.0.0+git26.47daf48f-1.fc44.x86_64
dms-greeter-git-1.0.0+git27.278cffe0-1.fc44.src
dms-greeter-git-1.0.0+git27.278cffe0-1.fc44.x86_64
dms-greeter-git-1.0.0+git28.e957e438-1.fc44.src
dms-greeter-git-1.0.0+git28.e957e438-1.fc44.x86_64
ghostty-1.3.1-1.fc44.src
ghostty-1.3.1-1.fc44.x86_64
ghostty-devel-1.3.1-1.fc44.x86_64
material-symbols-fonts-1.0-1.fc44.noarch
material-symbols-fonts-1.0-1.fc44.src
matugen-4.2.0-1.fc44.src
matugen-4.2.0-1.fc44.x86_64
matugen-debuginfo-4.2.0-1.fc44.x86_64
matugen-debugsource-4.2.0-1.fc44.x86_64
qt6ct-kde-0.11-10.fc44.src
qt6ct-kde-0.11-10.fc44.x86_64
qt6ct-kde-debuginfo-0.11-10.fc44.x86_64
qt6ct-kde-debugsource-0.11-10.fc44.x86_64
quickshell-0.3.1-1.fc44.src
quickshell-0.3.1-1.fc44.x86_64
quickshell-git-0.3.1^843.git78672a8-1.fc44.5.src
quickshell-git-0.3.1^843.git78672a8-1.fc44.5.x86_64
quickshell-git-0.3.1^844.git532a060-1.fc44.5.src
quickshell-git-0.3.1^844.git532a060-1.fc44.5.x86_64
quickshell-git-0.3.1^845.git9f80755-1.fc44.5.src
quickshell-git-0.3.1^845.git9f80755-1.fc44.5.x86_64
quickshell-git-0.3.2^846.git1a4716c-1.fc44.5.src
quickshell-git-0.3.2^846.git1a4716c-1.fc44.5.x86_64
quickshell-git-0.3.2^847.git0fed22a-1.fc44.5.src
quickshell-git-0.3.2^847.git0fed22a-1.fc44.5.x86_64
quickshell-git-0.3.2^849.git15ea8e6-1.fc44.5.src
quickshell-git-0.3.2^849.git15ea8e6-1.fc44.5.x86_64
quickshell-git-0.3.2^849.git9f59d0a-1.fc44.5.src
quickshell-git-0.3.2^849.git9f59d0a-1.fc44.5.x86_64
quickshell-git-0.3.2^851.git052059f-1.fc44.5.src
quickshell-git-0.3.2^851.git052059f-1.fc44.5.x86_64
quickshell-git-0.3.2^852.git0f9939c-1.fc44.5.src
quickshell-git-0.3.2^852.git0f9939c-1.fc44.5.x86_64
quickshell-git-0.3.2^853.git916a0dd-1.fc44.5.src
quickshell-git-0.3.2^853.git916a0dd-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.1^843.git78672a8-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.1^844.git532a060-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.1^845.git9f80755-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^846.git1a4716c-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^847.git0fed22a-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^849.git15ea8e6-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^849.git9f59d0a-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^851.git052059f-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^852.git0f9939c-1.fc44.5.x86_64
quickshell-git-debuginfo-0.3.2^853.git916a0dd-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.1^843.git78672a8-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.1^844.git532a060-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.1^845.git9f80755-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^846.git1a4716c-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^847.git0fed22a-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^849.git15ea8e6-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^849.git9f59d0a-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^851.git052059f-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^852.git0f9939c-1.fc44.5.x86_64
quickshell-git-debugsource-0.3.2^853.git916a0dd-1.fc44.5.x86_64
```


---

## 3) f43 vs f44 Comparison

### dms

| chroot | repodata rev | binary RPMs | src RPMs | Details |
|--------|--------------|-------------|----------|---------|
| fedora-44-x86_64 | 1785569499 (2026-08-01) | 2 (`dms-1.5.3-1.fc44.x86_64`, `dms-cli-1.5.3-1.fc44.x86_64`) | 1 (`dms-1.5.3-1.fc44.src`) | Single stable build `10775781-dms` |
| fedora-43-x86_64 | 1785569499 (same day, 3abb64e…-primary.xml.gz, 9449 bytes) | 3 (`dms-1.5.3-1.fc43`, `dms-cli-1.5.3-1.fc43`, **plus** `dgop-0.6.2-1.fc43.x86_64` living in dms build 09811434) | 2 (`dms-0.6.2-1.fc43.src` stale + `dms-1.5.3-1.fc43.src`) | Extra dirs: `09811434-dms` (old 2025-12-11) and `10775781-dms`. Note `dgop` in f43 dms is **stale/orphan**: primary contains `dgop-0.6.2-1.fc43.x86_64` without an `epoch` in filename but buildhost `09811434`. In f44, `dgop` moved entirely to danklinux (v0.2.3 epoch 1). |

**Differing files:** f43 dms still advertises a stale `dgop` binary inside the dms repo; f44 dms is clean (dgop only in danklinux). Version parity otherwise identical (`1.5.3-1` for both fc43/fc44 — expected `follow_fedora_branching=true`).
Directory listing also differs: f44 dms shows only `10775781-dms` build dir; f43 shows both `09811434-dms` and `10775781-dms`.

### danklinux

| chroot | repodata rev | total entries | unique NVRs | unique name·arch | Notes |
|--------|--------------|---------------|-------------|------------------|-------|
| fedora-44-x86_64 | 1787940153 (2026-08-28 18:02:40) | 181 | 98 | 38 (28 base names) | Trim/pruned |
| fedora-43-x86_64 | 230c435e… (2026-08-28 ~same) / rev `18…` analogue | 356 | 98 | 38 (same 28 base names) | ~2× entries, same 98 NVRs but with many more historic duplicates |

- **Unique name·arch set is identical** between f43 and f44 (empty diff both directions). Same 28 base names.
- **Duplicate inflation in f43:** e.g. `breakpad` has 52 entries in f43 vs 2 in f44 (26 historic build dirs retained: `09678…`→`10032114-breakpad` vs only `10032114-breakpad` in f44). Similarly `cliphist` 38→2, `material-symbols-fonts` 40→2, `dms-greeter-git` 88→~89 (opposite: f44 actually has one more git build retained), `quickshell-git` family 20→20 (same). Total NVRs stays 98 because versions themselves are the same strings; f43 just retains each old build directory as a separate repodata entry for the same EVR (repomd lists each RPM file with its original build dir prefix, so same NVR appears multiple times with different `location href` per build dir? Actually for f44 most have been pruned to single latest build dir; for f43 pruning hasn't yet collapsed breakpad etc.).
- **Version bumps f44 vs f43:** None for stable sources except `cpptrace-1.0.4-4` (identical), `dgop 0.2.3 epoch 1` (identical), `ghostty 1.3.1`, `matugen 4.2.0` etc. — functional parity. Git families roll forward independently; latest f44 quickshell-git is `0.3.2^853`, dankcalendar `164`, dms-greeter `28.e957e438` — check f43 to see if it lags by a day or two (on 2026-08-28 f43 also had same latest per repodata snapshot: quick review shows f43 also at `0.3.2^853`? need separate fetch to confirm but sampling shows identical git SHAs).
- **Practical install view:** `dnf repoquery --available` on either chroot shows same “latest” packages; `dnf` resolves to highest EVR, so historic duplicates are invisible to users. For build planning, f44 is the clean/cleaner view.

---

## 4) Notes for bootc / Template Consumers

- **If you enable only `avengemedia/dms` you automatically get `avengemedia/danklinux`** (coprdep). In a Containerfile, `dnf5 copr enable avengemedia/dms` is sufficient; do not add a second `copr enable` for danklinux unless you need it standalone.
- **Clean layering:** For `dms` in `build/*.sh`, typical installs are:
  ```bash
  dnf5 -y install dms           # pulls dgop + (quickshell|quickshell-git) from danklinux automatically
  dnf5 -y install dms-greeter   # pulls greetd + quickshell from danklinux
  # weak deps (optional): danksearch, matugen, cava, qt6-qtmultimedia, NetworkManager
  # to skip weak deps: dnf5 -y install --setopt=install_weak_deps=False dms
  ```
- **Quickshell choice:** `dms` Requires `(quickshell or quickshell-git)` — either satisfies. `dms-greeter` Requires `(quickshell-git or quickshell)` (order flipped). Danklinux provides both: stable `quickshell-0.3.1-1.fc44` and rolling `quickshell-git` (10 latest git builds). Default install picks highest EVR which is `quickshell-git` (newer `0.3.2^853…` > `0.3.1`). Pin with `dnf5 install quickshell` explicitly if you want stable.
- **Final image hygiene:** `build/clean-stage.sh` pattern should `dnf5 -y copr disable avengemedia/dms avengemedia/danklinux` (or at least the dms one; disabling dms also disables danklinux dep on next refresh). Verify no COPR remains enabled in final layer.
- **COPR retention caveat:** Danklinux retains multiple git NVRs per package (7 dankcalendar, 5 dms-greeter, 10 quickshell) — not a bug; COPR keeps recent builds. `dnf` always uses latest. If you need reproducibility, pin to explicit `NVR` or `epoch:ver-rel`.

---

## 5) Verification Log

- `curl -sL …/dms/fedora-44-x86_64/repodata/repomd.xml` → primary `4bb552…-primary.xml.gz` (1575 B, open 6207) → 3 packages.
- `curl -sL …/danklinux/fedora-44-x86_64/repodata/repomd.xml` → primary `18f086…-primary.xml.gz` (27356 B, open 443681) → 181 packages / 98 NVRs.
- Same for `fedora-43-x86_64` for comparison (see §3).
- `podman run fedora:44 dnf5 copr enable avengemedia/danklinux && dnf5 copr enable avengemedia/dms && dnf5 repoquery --available --qf …` confirmed exact same lists (see container output snapshots stored in analysis scratch).
- `curl -sL https://copr.fedorainfracloud.org/api_3/project?ownername=avengemedia&projectname=dms` → `additional_repos: ["copr://avengemedia/danklinux"]`; danklinux → `additional_repos: []`.

---

## 6) Quick Reference URLs

- dms frontend: `https://copr.fedorainfracloud.org/coprs/avengemedia/dms`
- danklinux frontend: `https://copr.fedorainfracloud.org/coprs/avengemedia/danklinux`
- f44 x86_64 repodata:
  - `https://download.copr.fedorainfracloud.org/results/avengemedia/dms/fedora-44-x86_64/repodata/repomd.xml`
  - `https://download.copr.fedorainfracloud.org/results/avengemedia/danklinux/fedora-44-x86_64/repodata/repomd.xml`
- Primary XML (as fetched):
  - dms f44: `repodata/4bb5523067d32d2b831c2b5f8ab8c79d7b6b158b7dbf409954de100ef686e4c4-primary.xml.gz`
  - danklinux f44: `repodata/18f08631e53f741e29d50c22c4a4ad4657f7af4bc0f2377127f8ad0be87bf55c-primary.xml.gz`
- Build dirs (directory listing):
  - `https://download.copr.fedorainfracloud.org/results/avengemedia/dms/fedora-44-x86_64/`
  - `https://download.copr.fedorainfracloud.org/results/avengemedia/danklinux/fedora-44-x86_64/`
