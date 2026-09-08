# Dakota Repository Analysis — Reference for Building Pluto (a bootc Desktop OS)

**Repo:** https://github.com/projectbluefin/dakota
**Ref analyzed:** `main` @ `29aac04` ("fix(ujust): preserve newlines in confirm/report/verify (#1331)")
**Analysis date:** 2026-08-28
**Method:** `git clone --depth 1` succeeded (no 404/rename); all file citations below are from the local clone at `/tmp/opencode/dakota` unless noted as fetched remotely.

---

## 0. TL;DR — what Dakota is

Dakota is **Bluefin rebuilt from source on GNOME OS** using **BuildStream 2** (`.bst` elements). It is *not* an RPM/dnf image:

- Its `Containerfile` (273 bytes) is **lint-only** (`bootc container lint`) and explicitly forbids package installs (`elements/../Containerfile`).
- `AGENTS.md`: *"This is not the RPM-based Bluefin build: do not use `dnf`, `rpm-ostree`, COPRs, Containerfile package overlays, or post-build package installation. Make image changes through BST elements."*
- Everything down to the kernel (`core/linux-fdsdk.bst` — Linux 7.1.8) is built from source.
- The entire GNOME desktop is inherited from the **`gnome-build-meta` junction** (GNOME OS, branch `gnome-50`), which is composed over the **`freedesktop-sdk` junction** (25.08) — a full OS base equivalent to what `bootc-os:latest` is for pluto.
- **No niri anywhere** (grep over the whole tree: only gamescope/Xwayland compositor work exists). The closest analog to "add a compositor" is `elements/gaming/gamescope-session*.bst` (see §4c).

Relevance to pluto: the *composition discipline* (single manifest file, overlay-vs-trim, junction-style base pinning, load-bearing post-install steps for bootc, session packaging) transfers directly to a dnf5-based bootc image, even though the mechanism (BuildStream vs dnf) does not.

---

## 1. Repo layout

```
dakota/
├── Containerfile          # lint-only; image content lives in elements
├── Justfile               # 1398 lines: bst wrapper (podman), validate, patch-drift-check,
│                          #   boot-test/debug-session/inspect (VM), lint, audits
├── project.conf           # BuildStream project: element-path=elements, options
│                          #   (arch, x86_64_v3, gaming), artifact/source caches (gbm.gnome.org,
│                          #   cache.projectbluefin.io), plugin junctions, git_repo config
├── elements/              # THE image definition — everything lives here
│   ├── oci/               # final assembly: oci/bluefin.bst (kind: script → build-oci),
│   │                      #   bluefin-nvidia.bst, os-release.bst, python-micro[image].bst
│   │   └── layers/        # filesystem layers: bluefin.bst (kind: compose), bluefin-stack.bst
│   │                      #   (kind: stack), bluefin-init-scripts.bst, brew-toolchain*.bst
│   ├── bluefin/           # Dakota's own feature elements incl. deps.bst = the package manifest
│   ├── bluefin-nvidia/    # NVIDIA variant elements
│   ├── core/              # local overrides of GNOME OS elements: linux-fdsdk.bst (kernel),
│   │                      #   meta-gnome-core-apps.bst (app trim), sandbox-tools.bst, ntsync
│   ├── gaming/            # optional gaming variant (`-o gaming true`), incl. gamescope sessions
│   ├── plugins/           # buildstream-plugins(+community) junctions
│   ├── gnome-build-meta.bst   # junction → GNOME OS (branch gnome-50)
│   ├── freedesktop-sdk.bst    # junction → freedesktop-sdk 25.08 (base SDK/OS)
│   └── <feature>.bst          # element placed next to its files/ dir of the same name
├── files/                 # payloads, one subdir per element: bindmounts/, bootc-install/,
│   │                      #   countme/, dconf/, distrobox/, fakecap/, firstboot/, hedgehog,
│   │                      #   migrate-var-home-passwd/, nvidia-device-nodes/, oci/gaming-flatpak
│   │                      #   (preinstall.d hooks), plymouth/, service-overrides/, swapfile/,
│   │                      #   sysusers/, udev/, user-avatars/, wallpaper-month/, wireplumber/,
│   │                      #   plus scripts/ (bst-progress, gen-filemap, generate_cargo_sources)
│   └── filemap.json       # generated source-tracking map (Renovate/track-bst-sources.yml)
├── include/               # shared YAML fragments: os-release.yml, aliases.yml
├── patches/               # patch_queue sources + freedesktop-sdk.manifest.json (drift-checked)
├── scripts/               # python helpers (check_publish_workflow.py, gen-filemap.py)
├── docs/                  # build.md, ci.md, oci-assembly.md, patches.md, workflow.md,
│                          #   pr-checklist.md, feedback-loop.md
├── .agents/skills/        # dakota-buildstream, dakota-ci, dakota-image (ref local-ota.md),
│                          #   dakota-packaging, dakota-release, dakota-review, dakota-ujust,
│                          #   dakota-workstation
└── .github/workflows/     # 21 workflows incl. build/aarch64, boot-test, publish, nightlies,
                           #   track-bst-sources.yml, track-next-junctions.yml (dependency tracking)
```

**Convention: one element ↔ one concern ↔ one `files/<name>/` payload dir.** The element name always mirrors the directory that holds its payload.

---

## 2. How packages are declared

**BuildStream YAML `.bst` elements** — no dnf/ostree/RPM sessions, no `.pkgs`, no manifest in the Containerfile.

Three load-bearing kinds:

| kind | role |
|---|---|
| `stack` | pure dependency aggregator, **produces no filesystem output** |
| `compose` | produces layer filesystem content (`oci/layers/bluefin.bst`) |
| `manual` / `script` | inline install commands / final OCI assembly |

**The manifest is a single stack element** — `elements/bluefin/deps.bst`, whose header literally says:

```yaml
# Historical path note: despite the directory name, this is Dakota's package
# manifest. Add or remove image content via `.bst` elements here — never via
# dnf/RPM/Containerfile overlay logic.
kind: stack
depends:
  - gnome-build-meta.bst:gnomeos-deps/deps.bst     # ← the whole GNOME OS desktop
  - bluefin/gnome-shell-extensions.bst
  - bluefin/brew.bst
  - bluefin/tailscale.bst
  - ...
  - freedesktop-sdk.bst:components/podman.bst
  - freedesktop-sdk.bst:components/flatpak-builder.bst
  - freedesktop-sdk.bst:components/skopeo.bst
  - gnome-build-meta.bst:gnomeos-deps/just.bst
  - gnome-build-meta.bst:gnomeos-deps/wl-clipboard.bst
```

**Upstream bases are junctions** (`elements/gnome-build-meta.bst`, `elements/freedesktop-sdk.bst`): pinned git refs (e.g. `ref: 50.4-1-gec28a45a...`) that pull an entire OS project's element tree. Dakota then **overrides individual upstream elements at the junction boundary** — this is the "base layering" mechanism:

```yaml
# gnome-build-meta.bst (junction) — overrides:
# Replace the element so the OCI image doesn't have any apps
core/meta-gnome-core-apps.bst: core/meta-gnome-core-apps.bst   # trim to 3 apps
gnomeos-deps/plymouth-gnome-theme.bst: bluefin/plymouth-bluefin-theme.bst
oci/integration/os-release.bst: oci/os-release.bst             # Bluefin's os-release
# freedesktop-sdk.bst (junction) — kernel selection happens HERE so every consumer
# (initramfs, nvidia, unsigned-modules) resolves the same kernel:
components/linux.bst: core/linux-fdsdk.bst                     # or core/linux-ogc.bst when gaming
```

**Variants via project options** (`project.conf`): `arch`, `x86_64_v3`, `gaming`; elements branch with YAML conditionals:

```yaml
(?):
- gaming == true:
    image-repo: dakota-gaming
```

**Absolute pinning & reproducibility:** every git source pins a `ref`; kernels seed `KBUILD_BUILD_TIMESTAMP`; patches go through `patch_queue` with a sha256 manifest (`patches/freedesktop-sdk.manifest.json`) verified by `just patch-drift-check`; dependency updates are driven by Renovate + `track-bst-sources.yml` / `track-next-junctions.yml`.

**Final OCI assembly** — `elements/oci/bluefin.bst` (kind: script) runs, in order:
`prepare-image.sh --sysroot /layer` → `systemd-sysusers --root /layer` → `glib-compile-schemas` → `/usr/etc → /etc` merge (bootc must not ship both) → `dconf update` → **`ldconfig -r /layer`** → `build-oci` emitting a `containers.bootc: '1'` image labeled `org.opencontainers.image.ref.name: ghcr.io/projectbluefin/dakota:latest` (the bootc upgrade origin).

---

## 3. Base/core package set

### 3a. Inherited from GNOME OS (`gnome-build-meta.bst:gnomeos-deps/deps.bst`)

The **entire desktop core** is inherited, not re-declared. Fetched from the GitHub mirror of gnome-build-meta (branch `gnome-50`) — GitLab.gnome.org returned 406 to direct fetches:

- **Shell (core/meta-gnome-core-shell.bst):** gdm, gnome-shell, **mutter**, gnome-session, gnome-settings-daemon, gnome-control-center, gnome-keyring, gnome-bluetooth, gnome-color-manager, gnome-remote-desktop, gnome-initial-setup, gnome-tour, gnome-user-docs, gnome-user-share, gnome-backgrounds, gnome-desktop, gnome-menus, gvfs-daemon, rygel, sushi, orca, tecla, adwaita-icon-theme, glib-networking, gsettings-desktop-schemas
- **OS services (core/meta-gnome-core-os-services.bst):** NetworkManager, accountsservice, upower, geoclue, gst-thumbnailers
- **Portals:** xdg-desktop-portal, xdg-desktop-portal-gnome, xdg-desktop-portal-gtk
- **Audio:** pipewire-daemon, wireplumber, noise-suppression-for-voice, alsa-ucm-conf, sof-firmware
- **Input/IME:** ibus-anthy, ibus-hangul, ibus-libpinyin, ibus-typing-booster, fprintd, opensc, pam-pkcs11, switcheroo-control, uresourced
- **Fonts:** noto-cjk, words
- **Networking add-ons:** NetworkManager-openconnect/-openvpn/-vpnc, nss-mdns, wsdd
- **Firmware/hw:** linux-firmware, sofa-firmware equivalent (sof-firmware), wireless-regdb-bin, steam-devices, iio-sensor-proxy, android-udev-rules
- **System:** firewalld, nftables, zram-generator (Dakota disables: `bluefin-stack.bst` integration command overwrites `/usr/lib/systemd/zram-generator.conf`), podman, skopeo, distrobox, toolbox, git, openssh-systemd, bash-completion, man-db, btrfs-progs, ccid, iproute2/iputils/usbutils, jq, less, nano, vim, mokutil, systemd-hwdb, debuginfod-config, ld-config, modprobe-config, flathub-config
- **Platform:** freedesktop-sdk `vm/mesa-default.bst`, `vm/config/sudo.bst`, `vm/config/useradd-default.bst`; bootc (`gnomeos-deps/bootc.bst` + `oci/integration/bootc-config.bst`, Dakota overrides bootc to track ≥ v1.15.1)

### 3b. Dakota's own additions (`elements/bluefin/deps.bst` + peers)

- **Runtime package layer:** Homebrew (`bluefin/brew.bst`, `brew-tarball.bst`) — user-land packages as brew formulae; plus distrobox
- **Terminal:** ghostty (with vendored wayland deps), xdg-terminal-exec
- **CLI/utils:** fastfetch, gum, tealdeer, ydotool, uutils-coreutils (memory-safe), sudo-rs (memory-safe), just, wl-clipboard, git-lfs, bpf/bpftop/vmlinuxh, sysprof-app, debuginfod, dmidecode
- **Networking/services:** tailscale, uupd (updater), countme, NetworkManager tweaks
- **App stack:** snapd, flatpak-builder, containers-common
- **Hardware/audio extra:** alsa-utils, brlaser, wireplumber-pcsp (disables PC speaker), fwupd, libgtop (system-monitor extension), udev-groups (sysusers.d)
- **OS plumbing:** swapfile+zswap-config (kargs `zswap.compressor=zstd` → kernel `CRYPTO_ZSTD=y`), firstboot-date (writes `/run/ublue-os/booted-image`), bindmounts (`files/bindmounts/{home,root,snap}.mount`), migrate-var-home-passwd, efibootmgr, bootc-install-config
- **Desktop extras:** gnome-shell-extensions (dash-to-dock, blur-my-shell, app-indicators, gsconnect, caffeine, gradia-capture, custom-command-menu, bazaar-companion), gnome-ponytail-daemon, nautilus-python, gnome-epub-thumbnailer, papers-thumbnailer, wallpapers, wallpaper-month service, user-avatars, dconf keybindings

### 3c. Niri/compositor-specific work — honest finding

**Zero niri content.** Dakota is a GNOME/mutter desktop. Verified by full-tree grep for `niri|compositor|mutter|kwin` — hits are only: NVIDIA EGL JSON notes (compositors 64-bit), mutter test-dep note in freedesktop-sdk.bst, and the **gamescope gaming session** stack. The reusable patterns for a compositor session:

- `elements/gaming/gamescope-session.bst` (manual): installs the OGC session scaffolding — launcher, **systemd user target/service**, GPU selector, into `/usr` verbatim (`cp -a usr/. %{install-root}/usr/`)
- `elements/gaming/gamescope-session-steam.bst`: ships the session definition and **adds a `TryExec=` guard** to `/usr/share/wayland-sessions/gamescope-session-steam.desktop` so a broken session disappears from the greeter:

```bash
desktop="%{install-root}/usr/share/wayland-sessions/gamescope-session-steam.desktop"
if ! grep -q '^TryExec=' "$desktop"; then
  sed -i '/^Exec=/a TryExec=/usr/bin/gamescope' "$desktop"
fi
```

This `wayland-sessions/*.desktop` + TryExec + systemd-user-target pattern is exactly how a **niri session** should be shipped in pluto.

---

## 4. File-organization conventions worth copying into a bootc derivative

1. **Single manifest of record.** `elements/bluefin/deps.bst` is the authoritative package list, flat and commented, organized by concern (shell → extras → CLI → system). Corresponding Containerfile/dnf analogue for pluto: one `build/*.sh` or dnf5 manifest file instead of scattered `dnf5 install` lines.
2. **Element ↔ payload dir 1:1.** `elements/bluefin/firstboot-services.bst` ↔ `files/firstboot/`; `swapfile.bst` ↔ `files/swapfile/` (+ `.service` + `.swap` unit + init script). Copying into pluto: `config/<feature>/` holding systemd units, tmpfiles, sysusers, dconf.
3. **Systemd install idiom.** Units go to `%{install-root}/usr/lib/systemd/system/` with explicit enablement via `ln -sf ../<unit> .../multi-user.target.wants/<unit>` (never `systemctl enable`, no preset) — see `firstboot-services.bst`, `firstboot-date.bst`. Includes **self-removing first-boot units** (`bluefin-remove-installer.service`) and drop-ins dirs (`files/service-overrides/flatpak-preinstall.service.d/`).
4. **The bootc FHS/layer rules** (all in `oci/layers/bluefin-stack.bst` + `oci-assembly.md`):
   - only `/etc` ships, never `/usr/etc` (merge at build)
   - recreate `/boot /run /sysroot` + `ln -s sysroot/ostree ostree` — "Required for bootc to create the image"
   - FHS symlinks into `/var`: `var/home→/home`, `var/roothome→/root`, `var/opt→/opt`, `var/mnt→/mnt`, `var/srv→/srv`, `usr/local→var/usrlocal`
   - `touch /etc/machine-id`
5. **Load-bearing post-install steps** (`docs/oci-assembly.md`, in order): `systemd-sysusers --root` (greeter accounts), `glib-compile-schemas`, `dconf update`, and **`ldconfig -r /layer`** — a stale `/etc/ld.so.cache` after `bootc switch` caused a real GNOME Shell "No GPUs found" boot loop when Mesa bumped SO versions (PR #497). For pluto: run `ldconfig` (+ `glib-compile-schemas`/`gdk-pixbuf-query-loaders` style caches) inside the image build, and document the ordering.
6. **bootc install defaults** shipped as `files/bootc-install/00-defaults.toml` → `/usr/lib/bootc/install/00-defaults.toml`, with the root FS type **explicitly set** (`[install.filesystem.root] type = "xfs"`) because *"bootc no longer defaults the root filesystem type"* — `bootc install to-disk` exits 1 without it.
7. **os-release / image-info generated at build** (`include/os-release.yml`): `ID=bluefin-dakota`, `PLATFORM_ID=platform:f42` (mirrors the Fedora base, read by their countme scripts), `IMAGE_REF=ostree-image-signed:docker://ghcr.io/...`, plus `/usr/share/ublue-os/image-info.json`.
8. **Config payloads by mechanism:** dconf overrides (`files/dconf/06-dakota-keybindings` with `dconf update` at assembly), tmpfiles.d for `/etc/resolv.conf → systemd-resolved stub` (`network.bst`), sysusers.d (`files/sysusers/bluefin-udev-groups.conf`), udev rules, wireplumber conf — each in its own `files/<domain>/` dir.
9. **Variants by options, not forks.** `-o gaming true` + YAML conditionals; NVIDIA shares `bluefin-stack.bst` and only swaps deps + os-release. Pluto analogue: `-o nvidia`-style build flag selecting a `nvidia` overlay script.
10. **Validation gate is graph validation, not a build:** `just validate` = `bst show --deps all oci/bluefin.bst` (both variants) + workflow check. Boot verification is separate (`boot-test/debug-session/inspect`, VM via bst2).

---

## 5. Translation: Dakota composition → dnf5-friendly list for a niri pluto

Dakota's desktop = full GNOME shell. For pluto (niri on `bootc-os:latest`), the *composition categories* map to this dnf5 set. **Package names are translations, not verified against F43 repos — verify each name with `dnf5 repoquery` before use.** Niri, greeters, and Wayland satellite tools are not in Fedora repos (COPR/external RPMs — see the COPR policy in the pluto repo).

**Desktop infra (replaces mutter/gnome-shell):**
- `niri` (RPM/RPM-repo — Sokolov's COPR or a vendored repo)
- `xwayland-satellite` OR `xwayland` (niri needs XWayland)
- Greeter: `greetd` + `greetd-tuigreet` (or `greetd` + a GTK greeter); `seatd` not needed on systemd (logind)
- `polkit`, `polkit-gnome` (agent) or `polkit-kde-agent`
- `accountsservice` (greeter/session metadata)

**Core runtime/services:**
- `pipewire`, `pipewire-utils`, `wireplumber`, `alsa-ucm-conf`, `sof-firmware`, `alsa-utils`
- `xdg-desktop-portal`, `xdg-desktop-portal-gtk` (+ `xdg-desktop-portal-gnome` if GNOME settings portal wanted)
- `mesa-dri-drivers`, `mesa-vulkan-drivers`, `mesa-libGL`, `libinput`, `libdisplay-info`
- `NetworkManager` (in base), `bluez` (+ `blueman` for UI), `upower`, `power-profiles-daemon`
- `gvfs`, `gvfs-smb`, `gvfs-mtp` (file abstractions; Dakota ships gvfs-daemon)

**niri session UI/utilities (Dakota ships wl-clipboard; rest are the standard niri stack):**
- `wl-clipboard` (+ `cliphist` optional)
- `notifications`: `mako` or `fnott`; `swaybg` (or niri built-in background); `swaylock`
- launcher: `fuzzel` or `rofi-wayland`; bar: `waybar` (or niri's 1.0+ built-in)
- `grim`, `slurp`, `swappy` (screenshots); `kanshi` (output layout); `swayidle`; `brightnessctl`
- `fontconfig`, `dejavu-sans-fonts` / chosen nerd font, `noto-cjk` optional
- `adwaita-icon-theme`, `adwaita-cursor-theme`(or custom), `gsettings-desktop-schemas`, optionally `gtk3`/`gtk4` theme bits
- file manager: `nautilus` + `nautilus-python` or `thunar`; `xdg-terminal-exec` + chosen terminal (`ghostty` — Dakota builds it; Fedora carries `ghostty` since F41)

**App/packaging layer (mirrors Dakota's additions):**
- `flatpak`, `flatpak-builder`, `flatpak-session-helper`; add Flathub remote config at install
- `distrobox` (Dakota + GNOME OS both ship it), `podman` (in base), `skopeo`
- `just` (ujust-style recipes), `fastfetch`, `gum`, `tealdeer`
- `swapfile`/`zswap`: configure zswap kargs (`zswap.enabled=1 zswap.compressor=zstd`) rather than zram

**bootc hygiene (from §4, mechanism-agnostic):**
- `/usr/lib/bootc/install/00-defaults.toml` with explicit `[install.filesystem.root] type` (`bcachefs`/`btrfs`/`xfs` per pluto policy)
- post-install: `ldconfig`; `glib-compile-schemas`; `gdk-pixbuf-query-loaders`; `systemd-sysusers` merged via tmpfiles; `dconf update` if shipping dconf overrides
- os-release with `IMAGE_REF=ostree-image-signed:docker://ghcr.io/...`, `PLATFORM_ID=platform:f43`

---

## 6. Top 5 ideas reusable for pluto

1. **One "manifest of record" for the package set.** Dakota's entire image is defined by `elements/bluefin/deps.bst` — a single, commented, category-grouped list with an explicit README-style header. Pluto should mirror this in `build/`: one dnf5 install script (or dnf5 `install` vars file) per layer (base → desktop → niri stack → extras), not dnf5 lines sprinkled across a Containerfile.
2. **Junction-override thinking = base-layering thinking.** Dakota overlays/trims upstream elements at the junction boundary (e.g. `meta-gnome-core-apps` trimmed to 3 apps; kernel picked in one place; zram-generator config annihilated by an integration command). Pluto: treat `bootc-os:latest` as the "junction", list explicit **removals** (`dnf5 remove`/`--exclude`) and **overrides** (drop-in configs, unit overrides) in the same manifest so the delta from the base is auditable in one file.
3. **The bootc post-install protocol.** `systemd-sysusers` → schema/cache regen (`glib-compile-schemas`, `gdk-pixbuf-query-loaders`, `ldconfig`) → `/usr/etc` merge → `dconf update`, in that documented order, with the *reason* (Dakota's PR #497 Mesa boot-loop from a stale `/etc/ld.so.cache` after `bootc switch`) written into the docs. Also ship `/usr/lib/bootc/install/00-defaults.toml` with an explicit root-FS type — without it `bootc install to-disk` fails.
4. **Session packaging pattern from `gamescope-session`.** Dakota's only compositor work ships an alternative Wayland session: contents under `/usr`, a `wayland-sessions/<name>.desktop` entry with a **`TryExec=` guard**, a systemd user target for the session, and greeter integration. This is the pattern for shipping niri: package `niri.desktop` + session scripts + user units, and let the session plumbing live in systemd user land.
5. **FHS/bootc skeleton + first-boot hygiene.** Recreate `/boot /run /sysroot` + `ostree` symlink, `/var`-relative FHS symlinks (`/home → var/home` etc.), `touch /etc/machine-id`, self-removing first-boot units, tmpfiles for resolv.conf — all small, all necessary, all previously the source of real boot bugs (Dakota documents each with the bug that motivated it).

---

## 7. What could NOT be cloned/verified

- **Full `gnome-build-meta` / `freedesktop-sdk` trees:** junctions are not vendored; I fetched only 3 files (`gnomeos-deps/deps.bst`, `core/meta-gnome-core-shell.bst`, `core/meta-gnome-core-os-services.bst`) from the **GitHub mirror** (`github.com/GNOME/gnome-build-meta`, branch `gnome-50`). `gitlab.gnome.org` returned HTTP 406 to both webfetch and curl with a browser UA, so anything interior to GNOME OS (exact gdm/mutter element configs) is unverified.
- **dnf5 package names for the niri stack** (e.g. exact Fedora names for greetd/fuzzel/kanshi COPRs) — translations only; verify with `dnf5 repoquery`.
- **The `:next`/nightly branch** (`testing`/`next`): clone was `--depth 1` of `main` only.
- **Pre-commit/pre-merge CI behavior** in workflows was not executed; only file contents read.
