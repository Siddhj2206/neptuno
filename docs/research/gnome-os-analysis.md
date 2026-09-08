# GNOME OS — Reference Analysis for the pluto bootc Derivative

**Date**: 2026-08-28
**Audience**: pluto maintainers assembling a niri desktop on top of Fedora Hummingbird `bootc-os:latest`
**Primary source**: `https://gitlab.gnome.org/GNOME/gnome-build-meta` — shallow clone (`--depth 1`) at `/tmp/opencode/gnome-build-meta`, HEAD `963ff4f30cf685320cdd71c570929e269a59a8b0` (2026-08-27).

---

## 0. What could and could not be verified

**Cloned (primary)**:
- `GNOME/gnome-build-meta` — the *current* repo where GNOME manages the GNOME OS image builds (plus the Flatpak runtimes and OCI images). Cloned successfully, 13 MB, `master` branch.

**Could NOT clone — repos do not exist / not public**:
- `GNOME/gnome-os` → HTTP 302 → `sign_in` (no such public project)
- `GNOME/gnomeos` → same (API: `404 Project Not Found`)
- `GNOME/gnome-ostree` → same (the historical OSTree-based manifest repo is gone from gitlab.gnome.org)

**Fetched via curl/API** (anonymous, rate-limited):
- `https://gitlab.gnome.org/api/v4/projects/GNOME%2Fgnome-build-meta` — not needed; clone worked.
- Group project search `GNOME/projects?search=os` — returned no data anonymously; could not enumerate other OS repos. There may be a newer/separate build-system repo (Rust-based `gnomeos` tooling is publicly discussed) that we could not locate; this analysis covers the *publicly verifiable* current source of truth.

**Not fetched**: the referenced wiki (`GNOME/gnome-build-meta/-/wikis/...#technical-conditions-to-enter-gnome-core`, cited in `elements/core*.bst` headers) — GitLab HTML pages reject anonymous fetches (HTTP 406). Its content is summarized from in-repo citations only.

Bottom line: **GNOME OS today = `gnome-build-meta` (BuildStream)**, NOT a plain RPM/OSTree manifest repo like the old `gnome-ostree`. It builds nearly everything from source and exports:
1. Flatpak runtimes (`org.gnome.Platform`/`Sdk`)
2. GNOME OS ISO + sysupdate repository (stable + nightly)
3. **OCI images, `gnomeos*` bootc-compatible** (`quay.io/gnome_infrastructure/gnome-build-meta:gnomeos-nightly`) — README.md, "Published build outputs" table.

---

## 1. Repo layout

```
gnome-build-meta/
├── project.conf                  # BuildStream project config (name, options, plugins, overrides)
├── elements/                     # The whole package/component universe, as .bst YAML
│   ├── core.bst                  # TOP-LEVEL: GNOME Core stack (governed set)
│   ├── core/                     # one .bst per GNOME core component (gnome-shell.bst, mutter.bst, …)
│   ├── core-deps/                # runtime deps: NetworkManager, accountsservice, dconf, portals…
│   ├── sdk.bst / sdk-deps/       # GNOME SDK components (gtk, pango, adwaita fonts/icons…)
│   ├── sdk-platform.bst          # the platform subset used in images (adwaita/cantarell fonts here)
│   ├── freedesktop-sdk.bst       # JUNCTION → freedesktop-sdk repo = the base layer of everything
│   ├── gnomeos/                  # OS-specific assembly: repart, sysupdate, initramfs, live, OS config
│   │   ├── update-images.bst     # aggregates all update image flavors + SHA256SUMS
│   │   ├── repart-config.bst     # systemd-repart partition layout (imports files/secure-repart-config)
│   │   ├── sysupdate-config.bst  # systemd-sysupdate transfer/feature files
│   │   ├── live.bst / live-image.bst
│   │   ├── devel/ debug/ usr/ codecs-extra/ snapd/ nvidia-*/   # layered extension images
│   │   └── bootc-related: import-deployment-pub-key, efi-keys, signed-boot, make-layer, os-release
│   ├── gnomeos-deps/             # runtime additions: bootc, fish, fprintd, zram, flathub-config…
│   │   └── deps.bst              # THE runtime deps stack (portal/pipewire/flatpak config set)
│   ├── oci/                      # OCI/bootc image export
│   │   ├── gnomeos/{stack,manifest,filesystem,image,init-scripts}.bst
│   │   ├── gnomeos-devel/  platform/  sdk/  initramfs/
│   │   └── integration/{bootc-config,os-release,extrafs,cleanup-debug,lvm2-enable-activation}.bst
│   ├── flatpak/                  # Flatpak runtime builds (separate product, same repo)
│   ├── buildsystems/  plugins/  incubator/  void/
├── files/                        # OS config payloads, imported into the image
│   ├── oci/{10-bootc.conf, prepare-root.conf}
│   ├── sysupdate/                # *.transfer, *.feature files → /usr/lib/sysupdate.d
│   ├── secure-repart-config/{main,iso,mini}/   # repart partition defs
│   ├── systemd-presets/{system-preset,user-preset}/
│   ├── gnomeos/  boot-keys/  boarding configs (firewalld, journald, kmscon, snapd, …)
│   └── os-release
├── include/                      # shared YAML: aliases, mirrors, recc, image-version
├── keys/gnome-base.gpg           # verification keys for sources
├── patches/                      # patch queues on top of junctions/sources
├── plugins/                      # custom BuildStream plugins (collect_initial_scripts)
├── docs/{contributing-os.md, install.md, using.md, phones.md, …}
└── .gitlab-ci.yml + .gitlab-ci/scripts/   # CI: track-refs → build → deploy → test → reports
```

## 2. Manifest pattern (the heart of it)

There is **no `manifest.json`-style RPM list**. The package set is expressed as **BuildStream `stack` elements** (YAML): each `<name>.bst` declares `kind: stack` and a `depends:` list of other elements. Stacks compose into larger stacks; leaf elements are per-component build recipes (`kind: meson|autotools|cmake|make|cargo|import|script`).

Key quotes (element headers, repeated in `core.bst`, `meta-gnome-core-*.bst`):

> `# The core set is not expected to change as frequently as core-deps.`
> `# Adding or removing elements from here should be approved by release team.`

**Layering / hierarchy** (the "pyramid"):

```yaml
# elements/core.bst  (top-level manifest for GNOME Core)
kind: stack
depends:
- core/meta-gnome-core-os-services.bst
- core/meta-gnome-core-shell.bst
- core/meta-gnome-core-apps.bst
- core/meta-gnome-core-developer-tools.bst
- core/meta-gnome-core-mobile.bst
```

The **bootc OCI image manifest** — `elements/oci/gnomeos/stack.bst` (`kind: stack`) is the closest analogue to a bootc image "package list":

```yaml
depends:
- oci/integration/os-release.bst
- gnomeos-deps/deps.bst
# OS-related config
- gnomeos/fwupd-efi-signed-maybe.bst
- gnomeos/import-deployment-pub-key.bst
- gnomeos/public-keys.bst
- gnomeos/replace-signed-systemd-boot.bst
- gnomeos/systemd-pcrlock-workaround.bst
# Add the kernel
- freedesktop-sdk.bst:components/linux-firmware.bst
- gnomeos/initramfs/signed-modules.bst
- oci/initramfs/image.bst
# Currently only in -devel
- gnomeos-deps/bootc.bst
- oci/integration/bootc-config.bst
- freedesktop-sdk.bst:vm/config/useradd-ostree.bst
- freedesktop-sdk.bst:vm/config/sudo-nopasswd.bst
- oci/integration/lvm2-enable-activation.bst
```

with `integration-commands` that make the tree a valid bootc image:

```yaml
public:
  bst:
    integration-commands:
    - mkdir /boot
    - mkdir /sysroot
    - mkdir /sysroot/ostree
    - ln -s sysroot/ostree ostree      # "This needs to be a relative symlink"
    - rm --verbose --recursive --force /root
    - mkdir /var/home  /var/roothome  /var/opt  /var/mnt
    - ln -s /var/home /home ; ln -s /var/roothome /root ; ln -s /var/opt /opt ; ln -s /var/mnt /mnt
    - touch /etc/machine-id
```

A **generated, self-documenting manifest**: `oci/gnomeos/manifest.bst` is `kind: collect_manifest`:

```yaml
kind: collect_manifest
build-depends:
- oci/gnomeos/stack.bst
config:
  path: /usr/manifest.json
```

→ every image carries `/usr/manifest.json` auto-generated from the build graph (the `collect_manifest` plugin from `buildstream-plugins-community`). This is directly analogous to `bootc compose` output manifest / `rpm-ostree` pkg lists, but generated rather than curated.

**Flavor/conditional composition** — element-level conditionals, not shell branches:
- `elements/gnomeos-deps/deps.bst` ends with:

```yaml
(?):
- arch == "x86_64":
    depends: (>): [gnomeos-deps/deps-x86_64.bst]
- arch == "aarch64":
    depends: (>): [gnomeos-deps/deps-aarch64.bst]
- channel == "nightly":
    depends: (>): [incubator/meta-gnome-incubator-apps.bst, gnomeos-deps/flathub-beta-config.bst, gnomeos-deps/gnome-nightly-config.bst]
```

(`channel` is a project option: `nightly` default, `stable` — defined in `project.conf`.)

## 3. How the image is assembled

**Builder: BuildStream 2.x** (`project.conf`: `min-version: 2.6`, `element-path: elements`). Each component is built from source in sandboxes; results are cached in artifacts servers (`https://gbm.gnome.org:11003`).

Base layer: **junction** `elements/freedesktop-sdk.bst` → `gitlab:freedesktop-sdk/freedesktop-sdk.git` pinned to `track: freedesktop-sdk-26.08*`, `ref: freedesktop-sdk-26.08rc.1-0-ge076d4978…`, with a **patch queue** (`kind: patch_queue` on `patches/freedesktop-sdk`) and targeted **overrides** replacing upstream elements with GNOME's own (systemd, xdg-desktop-portal, flatpak, gtk3, zenity→void, …).

Downstream of that, three product paths (all from the same element graph):

1. **OCI/bootc image** (`oci/gnomeos/*`):
   - `filesystem.bst` (`kind: compose`) merges the stack into a rootfs, **excluding** `debug`, `devel`, `doc`, `extra`, `static-blocklist` (BuiltStream split-rules).
   - `image.bst` (`kind: script`) runs `prepare-image.sh` (from freedesktop-sdk `vm/prepare-image.bst`), then `systemd-sysusers --root /layer`, then `build-oci` with:

```yaml
mode: oci
gzip: disabled
images:
- os: linux
  architecture: "%{go-arch}"
  parent: {image: /parent}        # parents from oci/platform/image.bst
  layer: {image: /layer}
  config:
    Labels:
      'com.github.containers.toolbox': 'true'
      'org.opencontainers.image.source': 'https://gitlab.gnome.org/GNOME/gnome-build-meta/'
      'containers.bootc': '1'     # ← makes the image bootc-deployable
```

   - bootc runtime config via `oci/integration/bootc-config.bst` installing:

```
files/oci/10-bootc.conf    → /usr/lib/tmpfiles.d/10-bootc.conf
files/oci/prepare-root.conf → /usr/lib/ostree/prepare-root.conf
```

```ini
# prepare-root.conf
[composefs]
enabled = yes
[sysroot]
readonly = true
```

```ini
# 10-bootc.conf (tmpfiles)
d /var/opt 0755 root root -
d /var/usrlocal 0755 root root -
d /var/home 0755 root root -
d /var/srv 0755 root root -
d /var/roothome 0700 root root -
d /var/mnt 0755 root root -
d /run/media 0755 root root -
```

2. **Disk image / installer** — `systemd-repart` + `systemd-sysupdate`:
   - `repart-config.bst` imports `files/secure-repart-config/main` → `/usr/lib/repart.d`:

```
10-efi.conf           # ESP
20-usr-verity-A.conf  # usr-verity, sha256, fixed 275M
21-usr-A.conf         # usr, fixed 4G, SplitName=usr
30-usr-verity-B.conf / 31-usr-B.conf   # A/B update slots
50-root.conf          # Type=root, Encrypt=key-file+tpm2, Format=btrfs
```

   - `sysupdate-config.bst` imports `files/sysupdate` → `/usr/lib/sysupdate.d` (`40-gnomeos-*.transfer`, `80-gnomeos-usr-verity.transfer`, `90-gnomeos-kernel.transfer` + `.feature` files: devel, debug, codecs-extra, snapd).
   - `update-images.bst` pulls together the per-flavor images (user-only, devel, debug, snapd, codecs-extra, nvidia) and emits `SHA256SUMS`.
   - `live.bst` / `live-image.bst` → ISO (`docs/contributing-os.md`: `bst build gnomeos/live-image.bst; bst artifact checkout … → ./iso/disk.iso`).
   - Dev iteration: systemd-sysext for quick changes, sysupdate repo for kernel (`utils/run-sysupdate-repo.sh --devel`, `utils/run-secure-vm.sh --gtk --local-updates`).

3. **Flatpak runtimes** (`flatpak/`, `oci/platform|sdk`) — same graph, different composition (irrelevant for pluto, but note it: one repo, three products).

## 4. Versioning / pinning

- Every source is **pinned in the element file** via `ref:`. Git sources use the `ref-format: git-describe` scheme (project.conf):

```yaml
# elements/core/gnome-shell.bst
sources:
- kind: git_repo
  url: gnome:gnome-shell.git
  track: main
  ref: 51.beta-57-g8f78208660d617182d3ea854f10c5ec9d20248e2
```

- Non-git tarballs pin content-addressed `ref` too (e.g. `flathub-config.bst`: `kind: remote`, `url: flathub:repo/flathub.flatpakrepo`, `ref: 3371dd250e61d9e1633630073fefda153cd4426f72f4afa0c3373ae2e8fea03a`).
- **Junctions pin whole base systems**: `freedesktop-sdk.bst` pins release-track branch + commit; `plugins/*.bst` junctions pin plugin toolchains.
- **Automated dep updates**: a scheduled `track-refs` CI stage runs `.gitlab-ci/scripts/ci-bot-track-refs.sh` → `update-refs.py` bumps refs per `track:` globs (e.g. `track: v*` for bootc → `ref: v1.16.6-0-gcf828dc1ec9e…`) and opens a single bot MR (`gnome-build-meta-bot`, assigned to marge-bot). This is their Renovate — note: `track:` glob per element, refs all recorded in-repo, fully reproducible.
- Rust: `kind: cargo2` with locked registry/git sources is embedded in the .bst (see `gnomeos-deps/bootc.bst`, which also pins composefs-rs 0.7.0 exactly).
- Version metadata: `include/image-version.yml` (`image-version: 'l.1'`, `commit: 'unknown'` replaced by CI via `git rev-parse --long HEAD`).
- **No version in the manifest lines themselves** — versions live one level down in each component element. Changing a component = editing its `.bst` ref.

## 5. Package composition (what actually goes into the OS image)

Layers, bottom-up:

1. **Base**: freedesktop-sdk junction 26.08 (melange-style source-built base: libc, systemd (overridden), dbus, udev, composefs, ostree, skopeo, podman, util-linux…). Included explicitly from the junction in `deps.bst` and `oci/gnomeos/stack.bst` — e.g. `freedesktop-sdk.bst:components/linux-firmware.bst`, `…/pipewire-daemon.bst`, `…/wireplumber.bst`, `…/xdg-desktop-portal.bst`, `…/systemd-hwdb-maybe.bst`.
2. **GNOME SDK subset** (`sdk-platform.bst`): gtk3/gdk-pixbuf/glib-networking etc., **adwaita-fonts + cantarell-fonts** (the font policy: `sdk-platform.bst` lines 8/13), adwaita-icon-theme, gsettings-desktop-schemas.
3. **GNOME Core** (`core.bst` → meta-stacks):
   - `meta-gnome-core-shell.bst` — gdm, gnome-shell, mutter, gnome-session, gnome-settings-daemon, gnome-control-center, gnome-initial-setup, gvfs-daemon, orca, tecla, adwaita-icon-theme…
   - `meta-gnome-core-os-services.bst` — NetworkManager, accountsservice, oo7-daemon/pam/portal, upower, geoclue, gst-thumbnailers.
   - `meta-gnome-core-apps.bst` — nautilus, epiphany, gnome-software, GNOME circle apps (decibels, loupe, papers, showtime, snapshot…) — "Additional design team approval is required before adding or removing desktop applications from core."
   - developer-tools + mobile stacks exist for other products; core.bst includes them, `gnomeos-deps/deps.bst` deliberately does NOT ("This is core.bst without the mobile and dev-tools categories").
4. **GNOME OS runtime set** (`gnomeos-deps/deps.bst`) — the relevant "extra" list for a minimal desktop:
   - **Portals**: `freedesktop-sdk.bst:components/xdg-desktop-portal.bst` + `core-deps/xdg-desktop-portal-gnome.bst` + `core-deps/xdg-desktop-portal-gtk.bst`
   - **Audio**: `freedesktop-sdk.bst:components/pipewire-daemon.bst` + `…/wireplumber.bst` + `gnomeos-deps/noise-suppression-for-voice.bst` (+ user presets enable `pipewire.socket`, `wireplumber.service`, `pipewire-pulse.socket`)
   - **Flatpak policy**: `gnomeos-deps/flathub-config.bst` (preinstalled Flathub repo at `/usr/share/flatpak/remotes.d/flathub.flatpakrepo`, pinned by sha256), `flathub-beta-config.bst` + `gnome-nightly-config.bst` only on nightly channel. `flatpak` itself comes from freedesktop-sdk overridden by `core-deps/flatpak.bst`.
   - **Bootc/containers**: podman, skopeo (base) + distrobox, toolbox; `bootc.bst` is in the OCI stack but "Currently only in -devel" for other products.
   - **HW/enablement**: alsa-ucm-conf, iio-sensor-proxy, thermald, fprintd, switcheroo-control, zram-generator, uresourced, sof-firmware.
   - **Networking extras**: NetworkManager-openconnect/openvpn/vpnc, nss-mdns, wsdd.
   - **Input methods**: ibus-anthy/hangul/libpinyin/typing-booster; fonts: **noto-cjk** + cantarell/adwaita (SDK).
   - **CLI/shell**: fish, vim, nano (+ `nano-default-editor.bst`), less, jq, git, git-lfs, iproute2, iputils, usbutils, man-db, bash-completion.
   - **Security/pinning**: mokutil, pam-pkcs11, opensc, systemd presets etc.
5. **OS-layer extras** (`gnomeos/`): kernel+firmware, initramfs (signed-modules, ukify/pcrlock), sysupdate/repart config, os-release, ldconfig-always, kmscon fallback console, `preset-all`, systemd-presets import.

**Non-GNOME / compositor notes**: GNOME OS is GNOME-only; the base is compositor-agnostic (Wayland stack: mesa-default, xdg-desktop-portal, pipewire, iio-sensor-proxy — all compositor-neutral). Their `xwayland-satellite.bst` even exists in `elements/sdk/` (experimental Xwayland). Nothing prevents substituting a `niri.bst` in place of `mutter.bst`/`gnome-shell.bst` in a fork — the OCI stack is just a dependency list.

**Service enablement** — `files/systemd-presets/` (installed to `/usr/lib/systemd/{system,user}`):
- `system-preset/80-gnome.preset`: `enable gdm.service`, `colord.service`, `accounts-daemon.service`
- `system-preset/80-network.preset`: `enable avahi-daemon.*`, `enable NetworkManager.service`; **`disable systemd-networkd.*`**
- `user-preset/80-pipewire.preset`: `enable pipewire.socket`, `wireplumber.service`, `pipewire-pulse.socket`
- `user-preset/99-default-disable.preset`: `disable *` — default-off, then opt-in per preset group.

## 6. Conventions worth adapting for pluto (a bootc derivative with its own package set)

1. **Declarative stack-of-stacks instead of scripted `dnf install`**: one "image manifest" element whose `depends:` is the entire package set; category sub-stacks (`base`, `compositor`, `apps`, `hw`, `network`…). For pluto this maps to a single `niri-base-packages.yaml` / `packages.lst` consumed by `dnf5 install $(< packages.lst)` with grouped sections — one source of truth, easy diffing and review.
2. **Split "core" (governed, slowly changing) from "deps" (fast-moving)** with written admission criteria in the header comment of each set — GNOME literally documents "The core set is not expected to change as frequently as core-deps" + release-team approval + design-team approval for apps.
3. **Arch/channel conditionals in the manifest**, not in shell scripts (`(?): arch == "x86_64"` / `channel == "nightly"`). For pluto: arch-specific sub-lists (e.g. nvidia vs nouveau, intel-microcode) selected declaratively.
4. **Flatpak + portals policy as manifest entries**: preinstall FlatHub repo pin (sha256-pinned `flathub.flatpakrepo` into `/usr/share/flatpak/remotes.d/`), explicit portal trio (xdg-desktop-portal + gtk + gnome→ for pluto: `xdg-desktop-portal-gtk` + `xdg-desktop-portal-niri`? — GNOME OS pattern: portals are first-class manifest entries).
5. **systemd presets shipped as files**, named `NN-category.preset`, with a `99-default-disable.preset` for user units; enable only what the desktop needs. `80-network.preset` disproving systemd-networkd in favor of NetworkManager is a model for pluto's networking choice.
6. **bootc image prerequisites as explicit integration steps**: /boot, /sysroot+ostree symlink, /var->/home|/root|/opt|/mnt symlinks, `/etc/machine-id` touch, `10-bootc.conf` tmpfiles, `prepare-root.conf` with `[composefs] enabled = yes` + `[sysroot] readonly = true` — copy these verbatim into pluto's image build.
7. **`/usr/manifest.json` generated artifact**: emit a machine-readable bill of materials into the image at build time (GNOME: `collect_manifest` plugin). For pluto: `rpm -qa`-style JSON or `dnf5` transaction metadata saved to `/usr/share/pluto/manifest.json` for easy `--version`/support debugging.
8. **Pinning**: refs recorded in-repo (git-describe style), automatic bump via scheduled bot MR (their `track-refs` stage — the analogue of pluto's Renovate, but refs live in the manifest itself, so history is a clean changelog of "what changed").
9. **Configuration as imported files, not inline scripts**: `files/` tree of raw config payloads (`files/sysupdate/*.transfer`, `files/systemd-presets/`, `files/oci/*.conf`) imported into well-defined `/usr/lib/...` targets — keeps image "tuning" greppable and diffable.
10. **Layered flavor images** (`devel`, `debug`, `codecs-extra`, `snapd` as separate layers/sysexts/updates) — pluto could ship a `pluto-devel` variant by adding one stack, not forking the build.

## 7. Top 5 ideas for pluto (priority order)

1. **Single declarative package manifest with grouped sub-stacks, consumed by one build step** — replace scattered `dnf install` lines with e.g. `packages/{base,compositor,apps,utils}.lst` + a `manifest` that concatenates them into one `dnf5 install -y` transaction; arch/channel conditionals as separate lst files. This is the direct port of `oci/gnomeos/stack.bst` + `gnomeos-deps/deps.bst`.
2. **Ship bootc graph prerequisites as explicit, documented image steps** — /boot, /sysroot/ostree relative symlink, /var→/home|/root|/opt|/mnt symlinks, `/etc/machine-id`, `10-bootc.conf` tmpfiles for /var dirs, `prepare-root.conf` (composefs yes, sysroot readonly), from `oci/integration/bootc-config.bst` / `oci/gnomeos/stack.bst` integration-commands.
3. **systemd-presets-as-files with `99-default-disable`** — one dir of `NN-category.preset` files (e.g. `80-niri.preset`: enable `niri.service`/`seatd`-equivalent; `80-network.preset`: NetworkManager on, systemd-networkd off; user preset enabling `pipewire.socket`, `wireplumber.service`, `pipewire-pulse.socket`) — instantiating `files/systemd-presets/` verbatim in spirit.
4. **Portal/audio/flatpak as first-class manifest sections** — explicit xdg-desktop-portal{,-gtk,-niri} entries, pipewire-daemon+wireplumber in the manifest (not post-install), and a sha256-pinned Flathub repo import to `/usr/share/flatpak/remotes.d/` (pattern: `gnomeos-deps/flathub-config.bst`).
5. **Emit a generated `/usr/manifest.json` (or dnf transaction record) into the image** for support/diffing, mirroring `oci/gnomeos/manifest.bst`'s `collect_manifest` → `/usr/manifest.json`; pair with git-describe-style version stamping (`include/image-version.yml` + CI `git rev-parse --long HEAD`).

## Appendix — raw facts & citations

| Fact | Source (path in clone) |
|---|---|
| "OCI images (nightly) … `gnomeos*` is `bootc`-compatible" | `README.md` Published build outputs table |
| Pipeline targets: `TARGETS_GNOMEOS=(core.bst gnomeos/devel/manifest.bst gnomeos/build-non-images.bst oci/gnomeos/stack.bst)` | `.gitlab-ci/scripts/build_elements.sh` |
| compose excludes `debug/devel/doc/extra/static-blocklist` | `elements/oci/gnomeos/filesystem.bst` |
| `containers.bootc: '1'` label + `build-oci` + `prepare-image.sh --noroot --noboot` | `elements/oci/gnomeos/image.bst` |
| `NN-category.preset` enablement incl. pipewire socket + wireplumber | `files/systemd-presets/{system,user}-preset/*` |
| repart: verity 275M, usr 4G, root btrfs TPM2-encrypted, A/B slots | `files/secure-repart-config/main/*.conf` |
| sysupdate transfer/feature files (devel/debug/codecs-extra/snapd) | `files/sysupdate/` |
| ref pinning `51.beta-57-g8f78208…` with `track: main` | `elements/core/gnome-shell.bst` |
| junction pin `freedesktop-sdk-26.08rc.1-0-ge076d497…` + patch_queue + overrides | `elements/freedesktop-sdk.bst` |
| bootc pinned `v1.16.6-0-gcf828dc1ec9e…`, `track: v*` | `elements/gnomeos-deps/bootc.bst` |
| fonts: adwaita-fonts + cantarell-fonts in `sdk-platform.bst`; noto-cjk in `gnomeos-deps/deps.bst` | `elements/sdk-platform.bst`, `elements/gnomeos-deps/deps.bst` |
| `prepare-root.conf`: composefs enabled, sysroot readonly | `files/oci/prepare-root.conf` |
| tmpfiles /var layout | `files/oci/10-bootc.conf` |
| image build docs: `bst build gnomeos/live-image.bst` → `./iso/disk.iso`; sysext/sysupdate iteration | `docs/contributing-os.md` |
