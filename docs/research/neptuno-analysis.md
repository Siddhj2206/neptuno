# Neptuno → Pluto Port Analysis

**Date:** 2026-08-28
**Analyst:** subagent (read-only audit of the sibling repo, git state `main` @ `9d1414c`)
**Sibling audited:** `/var/home/sid/Documents/Projects/neptuno` (read in place, never cloned)
**Target:** `/var/home/sid/Documents/Projects/pluto` — bootc OS on Fedora Hummingbird bootc-os (F43, minimal base, no desktop)

**Scope restriction honored:** `neptuno-shell` was not read, cloned, or referenced in any way. The neptuno repo itself contains **zero** references to a `neptuno-shell` project (grep over the whole tree found no matches), so nothing more can be said about it.

---

## 0. Executive summary

Neptuno is a **silverblue:44 (GNOME) + niri/DMS** image: the full Fedora GNOME desktop is the base, niri + DMS (DankMaterialShell) are layered on top as an *additional* session, GDM stays as the display manager and defaults to niri. Pluto is a **minimal-base niri/DMS** image with greetd + dms-greeter — no GNOME desktop at all.

The two overlap heavily on the niri/DMS/config/manifest side (both derive from the same finpilot template and DMS embedded template, and pluto already absorbed the multimedia layer). The port value of neptuno is therefore concentrated in: (1) hardware/QoL packages pluto lacks, (2) real-world generated DMS config artifacts, (3) a handful of config files (xdg-terminals.list, env.d vars, sulogin generator, unified-storage unit), (4) a couple of infrastructure hardening ideas (gdk-pixbuf loader cache, reproducible initramfs, brew preinstall content).

The do-NOT-port list is dominated by **GDM/GNOME-session machinery** (accountsservice Session=niri templates, gdm custom.conf, gnome-tweaks, ExtensionManager flatpak, nautilus-gsconnect…) and by **stale rebase-only artifacts** (build-time `flatpak override/mask` that dies on bootc, `rpm-ostreed.conf` staging for a bootc image, README/Brewfile drift, double adw-gtk3-theme install, `gnome-terminal-nautilus` removal entry, gaming step that is deliberately unwired).

---

## 1. neptuno architecture map

### 1.1 Repo layout

```
Containerfile          # multi-stage: common (projectbluefin/common), brew (ublue-os/brew), ctx, silverblue:44 base
build/
  build.sh             # orchestrator: calls steps explicitly (no globbing)
  README.md            # documents step conventions
  steps/
    00-image-info.sh   # image-info.json + os-release branding
    10-build.sh        # overlay rsync (brew → /, common shared+bluefin → /), custom/files → /, custom/config → /etc/skel
    20-base.sh         # removals, CLI/base/multimedia/COPR packages, systemd enables, Flathub
    30-dx.sh           # Docker CE + libvirt/QEMU + perf/dev tools
    40-dms.sh          # DMS + niri + portals from COPR, flatpak theme override/mask
    50-cleanup.sh      # kernel src + orphan modules removal
    50-gaming.sh       # steam/gamescope/mangohud — NOT wired into build.sh (TODO G11)
    60-initramfs.sh    # reproducible dracut regen + live modules, VFIO conf
    70-tests.sh        # in-image smoke tests (packages, vendors, units)
    clean-stage.sh     # disable COPRs/repos, versionlock clear, var/boot/run purge
    validate-repos.sh  # repo file validation
    copr-helpers.sh    # copr_install_isolated (enable → disable → --enablerepo install)
custom/
  brew/default.Brewfile            # REAL content: starship, btop, trash-cli, gh, bun, uv, lazygit, go, rust, lazydocker, podman-tui, topgrade, bluefin-cli, herdr, bbrew, 10 nerd-font casks
  config/                           # → /etc/skel/.config (niri/, ghostty/, environment.d/)
  files/                            # → / (gdm, accountsservice, dracut, systemd units, profile.d, xdg-terminal-exec, ublue hooks)
  flatpaks/default.preinstall      # 41 entries
  ujust/custom-system.just         # install-dms-config, neptuno-cli, changelogs override
iso/                                # disk.toml, iso.toml (Anaconda kickstart bootc-switch), rclone/ mirror templates
.github/workflows/                  # build-image.yml (daily cron, rechunk, keyless signing), pr-validation, validate-{brewfiles,flatpaks,justfiles,renovate}
docs/  — empty dir (zero files)
keys/                               # vendored cosign pubkeys for base/common/brew input verification
```

### 1.2 Containerfile (base image)

```dockerfile
FROM ghcr.io/projectbluefin/common:latest@sha256:c09c83ca… AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:8f952aea… AS brew
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:8788b4aaa8e270b78f036d65ffa230e85dd0b64fc5e289e15164bdb51631217c
ARG IMAGE_NAME="neptuno"  ARG BASE_IMAGE_NAME="silverblue"  ARG FEDORA_MAJOR_VERSION="44"
RUN … /ctx/build/build.sh   (single monolithic RUN, dnf caches + /boot + /tmp mounts)
CMD ["/sbin/init"]  +  RUN bootc container lint --fatal-warnings
```
(`Containerfile:54-83`). Single-RUN monolithic build; the same structure pluto already uses.

### 1.3 What "GNOME + niri/DMS" means concretely (the answer to "both installed?")

**Yes — full GNOME desktop AND niri/DMS are both installed, side-by-side, with niri as the default session.**

- The base `silverblue:44` ships the complete GNOME stack. Evidence: neptuno's own smoke test asserts `mutter` and `gdm` are present (`build/steps/70-tests.sh:42-44`: `IMPORTANT_PACKAGES=(… mutter gdm niri quickshell-git …)`), and `30-dx.sh`/`20-base.sh` rely on GNOME components (e.g. `gnome-tweaks`, `firewall-config`, `nautilus-gsconnect` are installed on top).
- niri comes from the `yalter/niri` **COPR** (`build/steps/40-dms.sh:14`), not from Fedora — even though niri is in Fedora proper (see §5).
- Session selection is **GDM-based**, two mechanisms:
  1. `custom/files/etc/accountsservice/user-templates/{administrator,standard}` → `Session=niri`, `SessionType=wayland` — the load-bearing mechanism for new users (added in commit `d7485fa` "niri default", 2026-08-18).
  2. `custom/files/etc/gdm/custom.conf` → `FallbackSession=niri` (author's own comment admits this is "Forward-compat: GDM >= 51 (Fedora 45+)" — so on F44/GDM ≤50 it is *not* honored yet) + `InitialSetupEnable=false` (no gnome-initial-setup on a niri image).
- DMS autostart: `systemctl --global add-wants niri.service dms` + `systemctl --global enable niri` (`build/steps/40-dms.sh:35-37`); `dsearch` is installed but **not** enabled (`# systemctl --global enable dsearch`).
- `40-dms.sh:47` instructs the user: `echo "After booting, select 'NIRI' session at the login screen"`.
- GNOME's display manager stays: neptuno does **not** use greetd/dms-greeter at all (no greetd config anywhere in `custom/files/`). `dms-greeter` is not installed.

So: GDM login → pick niri (default via user template) → niri session runs `dms` as a user service → quickshell bar/shell. The GNOME Shell session remains available as a fallback choice at GDM, and all GNOME daemons (gsd etc.) run only inside that fallback session — not in niri. There is **no gnome-settings-daemon wiring into the niri session** anywhere in neptuno's config (relevant to §6).

### 1.4 The niri/DMS config (the real-world artifact pluto should study)

- `custom/config/niri/config.kdl` — the DMS embedded template (same family as pluto's), with these notable deltas vs pluto's copy:
  - **Included fragments are NOT `optional=true`** (`config.kdl:268-273`: plain `include "dms/colors.kdl"` …). Pluto uses `optional=true` on all six — niri hard-fails on a missing fragment; pluto's is the safer, newer approach. Keep pluto's.
  - **`input { touchpad { tap; natural-scroll } … }` block is present** (`config.kdl:40-52`) — pluto's copy stripped the touchpad/mouse blocks and only kept a commented trackpoint. This is a real laptop-QoL delta worth porting.
  - Full `window-rule` set (gnome apps 12px corner radius, floating calculators/dialogs, steam toast rule, PiP) — pluto has the same set.
  - `recent-windows { binds { Alt+Tab … } }` to disable Super+Tab — pluto has it.
  - `dms/` fragments are the **real auto-generated output** of a working DMS setup: `dms/binds.kdl` (complete keymap: `dms ipc call spotlight|clipboard|processlist|powermenu|settings|dankdash|notifications|notepad|lock|audio|brightness|window-rules|workspace-rename|outputs`, `allow-when-locked=true` media keys, cooldown-ms wheel binds), `dms/colors.kdl` (matugen Material palette: `#d0bcff` focus ring, tab-indicator, insert-hint), `dms/layout.kdl` (`gaps 4`, `border { width 2 }`, corner-radius 12 rule), `dms/alttab.kdl` (`recent-windows { highlight { corner-radius 12 } }`), `dms/outputs.kdl` + `dms/cursor.kdl` empty. Pluto ships bare stubs — DMS regenerates them, so copying the content is unnecessary, but they are the best executable documentation of DMS's current IPC surface.
- `custom/config/ghostty/config` + `themes/dankcolors` — byte-for-byte the same DMS template pluto already ships (verified by diff; only difference: neptuno `app-notifications = no-clipboard-copy,no-config-reload` vs pluto `false`, and a couple of comments).
- `custom/config/environment.d/90-dms.conf`:
  ```
  ELECTRON_OZONE_PLATFORM_HINT=auto
  TERMINAL=ghostty
  GDK_BACKEND=wayland
  QT_QPA_PLATFORM=wayland;xcb
  SDL_VIDEO_DRIVER=wayland
  XDG_CURRENT_DESKTOP=niri
  GTK_USE_PORTAL=1
  CLUTTER_BACKEND=wayland
  ```
  Deltas vs pluto's `environment.d/90-dms.conf`: neptuno has `GDK_BACKEND=wayland`, `SDL_VIDEO_DRIVER=wayland`, `GTK_USE_PORTAL=1`, `CLUTTER_BACKEND=wayland`; pluto has `QT_QPA_PLATFORMTHEME=gtk3`, `QT_QPA_PLATFORMTHEME_QT6=gtk3`, `MOZ_ENABLE_WAYLAND=1` which neptuno lacks. (Pluto already sets the QT/Electron vars in the niri `environment {}` block too.)

### 1.5 systemd units (custom/files/usr/lib/systemd/system/)

`bluefin-dx-groups.service`, `bootc-unified-storage.service` (onboards `bootc image set-unified`, marked experimental, tracking bootc-dev/bootc#20), `dconf-update.service` (runs `dconf update` on boot), `flatpak-nuke-fedora.service` (deletes fedora/fedora-testing remotes before preinstall), `libvirt-workaround.service` (restorecon relabel), plus the coreos `coreos-sulogin-force-generator` (emergency/rescue sulogin with locked root).

Enabled at build (`20-base.sh:151-170`): podman.socket, brew-setup/update/upgrade, flatpak-appstream-refresh, rechunker-group-fix, flatpak-nuke-fedora, flatpak-preinstall, ublue-system-setup, input-remapper, tailscaled, uupd.timer, dconf-update, bootc-unified-storage, `--global` podman-auto-update.timer, ublue-user-setup, brew-preinstall, xdg-user-dirs, **gnome-keyring-daemon.service** (per-user!). `flatpak-add-fedora-repos.service` masked + file removed.

### 1.6 Flatpaks (custom/flatpaks/default.preinstall — 41 entries)

GNOME set: Calculator, Calendar, Characters, Connections, Contacts, Decibels, DejaDup, FileRoller, Firmware, Logs, Loupe, Maps, NautilusPreviewer, Papers, Showtime, SimpleScan, Snapshot, TextEditor, Weather, baobab, clocks, font-viewer.
App/runtime themes: `org.gtk.Gtk3theme.adw-gtk3` + `-dark` (`IsRuntime=true`).
Utilities: Zen browser (`app.zen_browser.zen`), Bazaar, Pinta, Flatseal, ExtensionManager, DistroShelf, Ignition, Warehouse, Impression, Resources, smile, Refine, PodmanDesktop, devtoolbox, Clapgrep, embellish (nerd-font installer), Gradia, plus `IsRuntime=false`/`CollectionID=org.flathub.Stable` on Bazaar.

### 1.7 Brew (custom/brew/default.Brewfile — preinstall, auto-installed at first login)

Real, tested content: `starship btop trash-cli dysk` (shell/QoL), `gh bun uv lazygit go rust` (dev), `lazydocker podman-tui topgrade` (containers/ops), `bluefin-cli herdr bbrew` (extras), 10 nerd-font casks (0xproto, blex-mono, caskaydia, comic-shanns, droid-sans-mono, fira-code, go-mono, sauce-code-pro, source-code-pro, ubuntu). Note: this is a 2026-era preinstall Brewfile — pluto's `default.Brewfile` is currently an all-commented template.

### 1.8 ujust (custom/ujust/custom-system.just)

- `neptuno-cli` (alias of bluefin-cli),
- **`install-dms-config`** — backup-first restore of `/etc/skel/.config` DMS/niri/ghostty files into `$HOME`, gum-confirmed, timestamped `.backup.<ts>` files, ends with "Run 'systemctl --user enable --now dms'" — a genuinely useful recipe pluto lacks,
- `changelogs` — overrides common's bluefin-pointing recipe to query `siddhj2206/neptuno` releases (`bctl changelogs` if present).

### 1.9 ISO/VM story

`iso/disk.toml` (root minsize 20 GiB), `iso/iso.toml` (Anaconda modules + `%post bootc switch --mutate-in-place --transport registry ghcr.io/siddhj2206/neptuno:stable`), `iso/rclone/*.conf` mirror templates (aws-s3, backblaze-b2, cloudflare-r2, scp, sftp). Justfile has the full BIB pipeline (`build-qcow2/-raw/-iso`, `spawn-vm` via systemd-vmspawn) plus `verify-inputs` cosign key verification of the three pinned input images using vendored `keys/*.pub`. Pluto already has `iso/` (disk.toml, iso.toml, rclone) and a Justfile — this is largely already ported.

---

## 2. TOP port list for pluto

### 2.1 Config/dotfile ports (highest value, lowest risk)

| # | What | Why | Source path (neptuno) |
|---|------|-----|----------------------|
| P1 | **`/usr/share/xdg-terminal-exec/xdg-terminals.list`** = `com.mitchellh.ghostty.desktop` | Pluto installs `xdg-terminal-exec` (base.toml:54) and ghostty, but ships **no** `xdg-terminals.list` — the package-level default keeps winning for apps that query the terminal. One-line file, zero risk. | `custom/files/usr/share/xdg-terminal-exec/xdg-terminals.list` |
| P2 | **env.d additions**: `GDK_BACKEND=wayland`, `SDL_VIDEO_DRIVER=wayland`, `GTK_USE_PORTAL=1`, `CLUTTER_BACKEND=wayland` | `GTK_USE_PORTAL=1` is the big one on niri (GTK file dialogs go through portals — needed for flatpak apps); GDK/SDL backends force Wayland on electron/Qt-game apps. Keep pluto's QT_QPA_PLATFORMTHEME/MOZ vars (neptuno lacks them). | `custom/config/environment.d/90-dms.conf` |
| P3 | **touchpad input block** (`tap`, `natural-scroll`) in niri config.kdl | Real laptop ergonomics neptuno ships; pluto's template copy stripped touchpad/mouse. Do NOT copy the fragment-include style (pluto's `optional=true` is safer). | `custom/config/niri/config.kdl:40-52` |
| P4 | **`coreos-sulogin-force-generator`** (systemd generator) | Rescue/emergency targets work despite Fedora's locked root password — a real footgun for any immutable image; vendored from fedora-coreos-config stable. Zero runtime cost. | `custom/files/usr/lib/systemd/system-generators/coreos-sulogin-force-generator` |
| P5 | **`dconf-update.service`** | Rebuilds dconf db on boot (rpm-ostree issue 1944 link in unit). Relevant because pluto ships gschema overrides + skel; ensures `gsettings set`-style user defaults aren't stale after rebase/upgrade. | `custom/files/usr/lib/systemd/system/dconf-update.service` |
| P6 | **`bootc-unified-storage.service`** | `bootc image set-unified` onboarding (zstd:chunked dedup, shared layer storage). **Verify status first** — may be default in 2026 bootc (unit itself says experimental, issue bootc-dev/bootc#20). | `custom/files/usr/lib/systemd/system/bootc-unified-storage.service` |
| P7 | **`install-dms-config` ujust recipe** | Backup-first re-seed of skel DMS config into `$HOME`; needed on any DMS image the moment a user edits configs and wants defaults back. Port with repo name swapped, drop the `neptuno-cli` alias. | `custom/ujust/custom-system.just` |
| P8 | **`changelogs` ujust override** | Fixes the inherited bluefin-pointing changelog recipe (bctl→repo-specific releases). | `custom/ujust/custom-system.just` |
| P9 | **gdk-pixbuf loader cache rebuild** after multimedia installs (`/usr/bin/gdk-pixbuf-query-loaders-64 --update-cache`) | Without it, freshly installed libheif/libjxl loaders aren't registered in the final image — thumbnails fail silently. Pluto's 25-multimedia.sh does the same installs but not the cache rebuild. | `build/steps/20-base.sh:119-121` |
| P10 | **`70-tests.sh` idea (lightweight)**: assert negativo VENDOR on codecs (`rpm -q --qf "%{NAME} %{VENDOR}"` grep negativo17.org) | Catches the classic silent regression where ffmpeg gets pulled from Fedora (free) instead of negativo. Pluto's per-layer assert gates already exist; add the vendor assert to 25-multimedia.sh. | `build/steps/70-tests.sh:60-71` |
| P11 | **dms/ auto-generated fragments as reference docs** (`binds.kdl`: full `dms ipc call` surface with `allow-when-locked` media keys + cooldown wheel binds; `colors.kdl`: matugen palette) | Don't copy verbatim (DMS regenerates), but keep them in `docs/` as the current IPC contract reference. | `custom/config/niri/dms/{binds,colors,layout,alttab}.kdl` |

### 2.2 Package ports (with target pluto manifest)

**→ `packages/base.toml` [fedora] (wm-agnostic):**

| Package | Why | Caveat |
|---------|-----|--------|
| `fastfetch` | plant fetcher (neptuno ships a themed fastfetch.jsonc); pluto has the concept via image-info | pure QoL |
| `htop` `nvtop` | CPU + **GPU** monitoring; nvtop matters on a gaming/GPU box | — |
| `fzf` `glow` | fuzzy finder + markdown pager (used by changelogs recipe + dev workflows) | — |
| `vim` | editor in base for recovery/emergency scenarios (editors otherwise absent from minimal base) | opinionated; skip if unwanted |
| `ddcutil` | DDC/CI brightness for external monitors (brightnessctl only covers internal panels) | — |
| `input-remapper` (+ enabled `input-remapper.service`) | key remapping daemon with GUI; real-world-tested in neptuno | GUI is GTK — fine on niri |
| `lm_sensors` `powertop` `powerstat` `smartmontools` `evtest` `libva-utils` `igt-gpu-tools` | hardware monitoring + `vainfo` (VA-API verification!) + `intel_gpu_top` | bundle; pick per audience |
| `solaar-udev` `openrgb-udev-rules` | Logitech/RGB **udev rules only** — cheap, no daemons | udev only = light |
| `libratbag-ratbagd` | mouse configuration daemon/configurator stack | daemon always-on; optional |
| `ifuse` `libimobiledevice` `libimobiledevice-utils` `usbmuxd` | iOS device mounting | niche |
| `borbackup`… (actually `borgbackup`) `restic` `rclone` `samba-client` | backup trio + SMB client | samba-client size is small; rclone also powers iso/rclone mirroring |
| `jetbrains-mono-fonts-all` `opendyslexic-fonts` | coding + dyslexia-friendly fonts; pluto already has `adwaita-fonts-all` | — |
| `squashfs-tools` `dracut-live` | ISO/live-boot support; neptuno's initramfs adds `dmsquash-live dmsquash-live-autooverlay` deliberately | only if ISO/live flow is wanted |
| `tailscale` + repo + operator hook (10-tailscale.sh) | VPN client enabled via privileged-setup hook | needs the pkexec hook pair to be useful |
| `zenity` | GTK dialogs for scripts (ujust, hooks) | — |
| `alsa-tools-firmware` | **verify existence on F43 first** — pluto's own base.toml note says it does not exist in F43 (see §5.6) | flag |
| `gvfs-nfs` `samba-client` | NFS/SMB in file pickers | GNOME-leaning; optional |
| `xdg-terminal-exec` — already present in pluto | — | — |

**→ `packages/multimedia.toml`:**
| Package | Why | Caveat |
|---------|-----|--------|
| `pipewire-libs-extra` | extra pipewire codec libs (bluefin pattern) | — |
| `intel-gmmlib` + `libheif` into the `[multimedia_overrides]` distro-sync list | neptuno syncs these alongside mesa from negativo — avoids gmmlib/driver version skew and gets HEIF/AVIF decode | matches negative list exactly |
| **`intel-vaapi-driver` — do NOT port** (see §3) | legacy i965 driver, dead upstream, Gen4–Gen9.5 only | skip |
| `@multimedia` comps group — neptuno uses it, pluto deliberately uses an explicit list (assert-able); **keep pluto's explicit list** | — | — |

**→ `packages/niri.toml`:**
| Package | Why | Caveat |
|---------|-----|--------|
| `khal` (avengemedia/danklinux) | DMS's terminal calendar (neptuno installs it in the DMS transaction) | tiny Python; completes the DMS set |
| `dsearch` vs `danksearch` — **verify package name** | neptuno uses `dsearch`; pluto uses `danksearch`. One of them is outdated; the 70-tests/README in neptuno can't disambiguate. Check the COPR listing before trusting either. | flag |
| `dms-cli` already in pluto; neptuno relies on it as a dep (doesn't install it explicitly) | — | — |
| `material-symbols-fonts` already in pluto (neptuno gets it via dependencies) | — | — |

**→ Brew (port **content**, decide delivery model):**
neptuno's `default.Brewfile` is real and tested: `starship btop trash-cli dysk gh bun uv lazygit go rust lazydocker podman-tui topgrade bluefin-cli herdr bbrew` + 10 nerd-font casks. Pluto's model is opt-in `ujust install-default-apps`; neptuno's is **auto-install at first login** (preinstall.d). If pluto wants first-login parity, port the file into `custom/brew/` (pluto already runs the same `brew-preinstall` machinery via common overlay); otherwise adapt the package list into the opt-in Brewfiles. `starship` also pairs with neptuno's `profile.d/90-starship.sh` (bash init with graceful fallback) — port only if you adopt auto-install.

### 2.3 Flatpak port candidates (append to pluto preinstall)

Pluto currently ships 16 apps; neptuno's list adds these notable ones (all flatpak → work fine on niri):
- **GNOME set additions**: `org.gnome.Calendar`, `org.gnome.Weather`, `org.gnome.Maps`, `org.gnome.Firmware` (firmware updates!), `org.gnome.Showtime` (video player — complements pluto's missing video playback), `org.gnome.Decibels` (audio), `org.gnome.Papers` (already in pluto), `org.gnome.Loupe` (already), `org.gnome.NautilusPreviewer` — pick per audience.
- **Utilities**: `io.podman_desktop.PodmanDesktop` (container GUI), `de.leopoldluley.Clapgrep` (ripgrep GUI), `net.nokyan.Resources` (monitor — pluto already has MissionCenter; pick one), `page.tesk.Refine` (flatpak cleaner), `io.github.flattool.Ignition` (flatpak manager), `com.ranfdev.DistroShelf` (distrobox manager), `io.github.getnf.embellish` (nerd-font installer), `be.alexandervanhee.gradia`, `me.iepure.devtoolbox`, `com.github.PintaProject.Pinta` (paint), `com.github.tchx84.Flatseal` (already in pluto).
- **Browser choice**: neptuno preinstalls **Zen** (`app.zen_browser.zen`), pluto ships Firefox. Not a port, but a deliberate fork in the road to record.

---

## 3. Do-NOT-port list (with reasons)

1. **GDM session machinery** — `custom/files/etc/gdm/custom.conf` (`FallbackSession=niri`, `InitialSetupEnable=false`) and `custom/files/etc/accountsservice/user-templates/{administrator,standard}` (`Session=niri`). Pluto uses greetd + dms-greeter; `FallbackSession` is explicitly forward-compat for GDM ≥ 51 / F45+ and, per the file's own comment, not honored on F44. Both files are dead weight (worse: `InitialSetupEnable=false` means nothing without GDM) on pluto.

2. **Build-time flatpak theming** — `build/steps/40-dms.sh:42-44`:
   ```
   flatpak override --filesystem=xdg-data/themes
   flatpak mask org.gtk.Gtk3theme.adw-gtk3
   flatpak mask org.gtk.Gtk3theme.adw-gtk3-dark
   ```
   **This is a bug that only works on rebased systems.** `/var/lib/flatpak` is wiped/recreated at boot on bootc; build-time overrides/masks write into the build container's `/var/lib/flatpak` and are lost. Pluto already did this right: first-boot `flatpak-theming.service` in `custom/files/usr/lib/systemd/system/` with a `ConditionPathExists` sentinel. Also note neptuno *both* preinstalls `adw-gtk3` runtime themes *and* masks them — contradictory; pluto's "skip preinstall + mask on first boot" is the coherent design.

3. **GDM-default GNOME UI packages** — `gnome-tweaks`, `firewall-config` (GTK firewall GUI), `gnome-extensions-app` removal list entry, `nautilus-gsconnect` (gnome-shell extension), `gnome-terminal-nautilus`-style removals. All GNOME-session-only; pluto has no GNOME shell.

4. **`intel-vaapi-driver`** — legacy i965 VA-API driver (`i965_drv_video.so`) for Gen4–Gen9.5, upstream dead (deprecated in FreeBSD ports 2024 "dead upstream… no longer promises security fixes"); neptuno installs it alongside `libva-intel-media-driver` for legacy-GPU cover. On a fresh modern-hardware image it's two broken-GPU-generations of dead weight. `libva-intel-media-driver` (iHD) already distro-synced by pluto covers Gen8+.

5. **GDM/GNOME test expectations** — `mutter`/`gdm` in `70-tests.sh` IMPORTANT_PACKAGES; those assertions are n/a on pluto.

6. **The **Docker CE + libvirt DX layer** (`30-dx.sh` + bluefin-dx-groups service + `sysctl.d/docker-ce.conf` + `sysusers.d/docker.conf` + `libvirt-workaround.service` + `ensure-libvirt-session-config` + `modules-load.d/ip_tables.conf`)**. Functionally fine, but it's a personality decision for a minimal image: docker-ce from its own repo + qemu-system-x86 set is ~1+ GiB. If pluto wants it, port the whole bundle (it's self-contained and tested); if not, port none of it — cherry-picking breaks the group-membership story (bluefin-dx-groups adds wheel→docker/libvirt).

7. **`50-gaming.sh`** — deliberately **NOT wired into build.sh** (steam/gamescope/mangohud need rpmfusion; TODO.md G11: "intentionally unconnected (no rpmfusion); revisit when wanted"). Copying the file without the repo + wiring = silent no-op or build break.

8. **`/etc/rpm-ostreed.conf` (`AutomaticUpdatePolicy=stage`)** — rpm-ostree-era artifact; on a bootc image updates go through `bootc`, and neptuno's own `just`/bootc flow never reads rpm-ostreed. Stale from the silverblue/bluefin lineage.

9. **Neptuno's niri fragment-include style** (non-optional includes, no input.kdl) — pluto's `optional=true` + input.kdl stub is newer/safer. Copying neptuno's include lines would regress boot resilience.

10. **Neptuno's COPR hygiene** — `40-dms.sh` enables COPRs globally then relies on `clean-stage.sh` to disable them; pluto's `copr_install_isolated`/keep-enabled manifest pattern (§2 neptuno `clean-stage.sh:10-12` vs pluto `20-base.sh` "KEPT enabled … no install-time enable/disable dance") is the newer, better practice. Do not regress.

11. **`50-cleanup.sh` orphan-module sweep** — harmless but redundant with bootc's own module cleanup; adds build time. Skip.

12. **Flatpak list rejects for a niri-only image**: `com.mattjakeman.ExtensionManager` (GNOME Shell extension manager — useless without GNOME Shell), `org.gnome.Connections`/`Contacts`/`Characters`/`clocks`/`font-viewer` (GNOME-personality apps that pluto deliberately trimmed; FYI choice, not a bug).

13. **`che/nerd-fonts` COPR (`nerd-fonts` RPM)** — neptuno installs it *and* 10 font casks via brew: redundant double font delivery (~hundreds of MB). If pluto adopts the brew casks, skip the COPR.

14. **yubikey/U2F block** (`pam-u2f`, `pamu2fcfg`, `yubikey-manager`, `openssh-askpass`, `pam_yubico`) — needs pam.d edits per-user to do anything; pluto's PAM story is greetd-only. Defer.

15. **`gnome-tweaks`**, **`switcheroo-control`**, **`libcamera-gstreamer`/`libcamera-tools`** — GNOME-session or niche-camera plumbing; skip on minimal.

16. **`bootc-unified-storage`** — only if the 2026 bootc status check shows it's still opt-in (see P6; re-list as do-NOT-port if bootc made it default).

---

## 4. (Digest b/c) — captured in §2/§3. Section reserved for digest pointers. See final response.

---

## 5. Outdated / wrong / rebase-only artifacts in neptuno (will-bite-if-copied list)

1. **`flatpak override/mask` at build time** — see §3.2. The canonical "worked only because this machine was rebased, never fresh-installed" bug: their `/var/lib/flatpak` survived rebases so masks/overrides appeared to persist. A fresh bootc install loses all of it (neptuno's README even claims "GNOME app catalog … preinstalled on first boot" while the mask contradicts the preinstall).

2. **`yalter/niri` COPR — redundant on F44.** niri has been in Fedora proper since F42 (2025; confirmed: Fedora Discussions "You do not need to enable a COPR for niri, it is available from the Fedora repositories", plus yalter COPR pages list F42+ releases). Neptuno pulls stable niri from the COPR; pluto already does the sane thing (Fedora F43 niri, no COPR). The COPR only buys "newer than distro" builds.

3. **`dsearch` vs `danksearch` naming** — neptuno installs `dsearch` (and has it commented out for enabling); pluto's manifest records `danksearch`. Exactly one of these is current for the avengemedia/danklinux COPR. Unverifiable offline — check the COPR page before porting either direction. (Neptuno's README §"DMS / Niri desktop stack" also lists `dsearch`.)

4. **README/Brewfile drift (template staleness)** — neptuno README.md:27 claims the Brewfile contains `bat, eza, fd, rg, gh, starship, zoxide, htop, tmux`; the actual `custom/brew/default.Brewfile` contains `starship, btop, trash-cli, dysk, gh, bun, uv, lazygit, go, rust, lazydocker, podman-tui, topgrade, bluefin-cli, herdr, bbrew` + fonts. The README also lists `50-gaming.sh` nowhere and describes `install-default-apps/install-dev-tools/install-fonts` ujust recipes that do not exist (they were replaced by the preinstall model). **Do not copy neptuno's README section; if anything, copy its TODO.md habit of recording decisions.**

5. **Double `adw-gtk3-theme` install** — `20-base.sh:57` and `40-dms.sh:21` both install it; harmless but sloppy; also it's already in pluto's base list — don't double it during the port.

6. **`alsa-tools-firmware` (F43 availability unverified)** — pluto's own `packages/base.toml` research note (2026-08-28) asserts "alsa-tools-firmware does not exist in F43", and `flatpak-spawn` note: "flatpak-spawn is not a package — its binary ships inside flatpak". Neptuno's 20-base.sh installs *both* names. Either they exist on F44 (or build failures are silently tolerated in neptuno's CI — the `|| true`-less install would fail the build, so likely they exist on F44), or neptuno hasn't fresh-built this step. **Fresh-verify both names against F43 before porting anything from that install line.**

7. **`generic-logos`/`fedora-logos` swap** (`20-base.sh:15-16`): `dnf5 swap fedora-logos generic-logos` then `rpm --erase --nodeps --nodb generic-logos` — the erase-with-no-db trick only makes sense on a never-rebased image; and on a minimal base there are no logos to swap at all. n/a for pluto.

8. **Removal list contains GNOME session packages** (`gnome-shell-extension-background-logo`, `gnome-extensions-app`, `gnome-terminal-nautilus`, `totem-video-thumbnailer`, `yelp`…) — correct *for a GNOME image*, wrong to port verbatim (pluto's minimal base has none of them; `totem-video-thumbnailer` is actually a useful thumbnailer niri/GNOME apps can use, and pluto already ships ffmpegthumbnailer instead — fine).

9. **`xdg-user-dirs`/`gnome-keyring` enable style** — neptuno enables `gnome-keyring-daemon.service` per-user via `systemctl --global enable`. Fine and simple; pluto instead wires keyring via `pam.d/greetd` (`auth optional pam_gnome_keyring.so … auto_start`) — pluto's approach is the one that unlocks the keyring at login; neptuno's global-enable *also* works on niri sessions but without PAM the Secret Service is unauthenticated-until-prompt. Keep pluto's PAM wiring; do not adopt the global enable as a replacement.
    - SUPERSEDED 2026-09-05: pluto's hand-rolled `pam.d/greetd` broke session bus access (missing pam_selinux/pam_loginuid) — deleted in favor of the stock file, which carries equivalent keyring lines. Keyring still unlocks at login.

10. **`gdk-pixbuf` cache rebuild** (see P9) — actually neptuno has this right and pluto lacks it; listed as a port, flagged here as the reverse direction of staleness.

11. **`FallbackSession=niri` marketing vs reality** — the gdm custom.conf comment ("GDM >= 51 (Fedora 45+) honours FallbackSession") means neptuno's stated "GDM defaults to the NIRI session" (README) is only true via the accountsservice user-template on F44, and only for *new* users. Rebased systems keep their saved session. Pluto's greetd approach has no such statefulness — grist for the "niri default" design, not a port.

12. **`umotd/config.json`, `bling/env.sh`, fastfetch.jsonc** — branding files referencing `neptuno-cli`; port the *pattern* (umotd tips, fastfetch layout with "Forged on" date) not the content.

13. **`iso.toml` kickstart hardcodes** `ghcr.io/siddhj2206/neptuno:stable` — a copy-paste footgun for any fork. Pluto's iso.toml presumably has its own; just don't port the URL.

14. **`bootc-unified-storage` experimental flag** — unit comments "Feature status in bootc upstream: experimental / Tracking: bootc issue #20". If pluto adopts, verify the 2026 status (may be default by now).

15. **`ssh`-less machines with `99-privileged.sh`** — the pkexec privileged-setup chain (10-tailscale.sh etc.) assumes a polkit agent + pkexec on the image; pluto has polkit-kde (agent) so it could work, but the hook chain is inherited from bluefin's `ublue-privileged-setup` — verify it ships via common overlay before porting the hook.

---

## 6. GNOME-daemons-on-niri verdict

**What neptuno proves by construction (it is a field-tested full-GNOME + niri image):**

- **GDM is not required for niri.** Neptuno pairs niri with GDM purely because the base ships it. Pluto's greetd+dms-greeter is the DMS-upstream-recommended path (`dms-greeter` exists only for greetd; the niri wiki's Fedora quick-start uses GDM only because distro default). No neptuno config has any dependency on GDM daemons inside the niri session.
- **gnome-settings-daemon does NOT run in the niri session** in neptuno — there is no wire-up anywhere (`spawn` list, env.d, or autostart all audited). GNOME Shell runs its own gsd; the niri session gets none of it (power/color/wacom/etc.). Consequently:
  - **Power** on niri is handled by `power-profiles-daemon` (system daemon; present in neptuno via silverblue, *enabled explicitly in pluto's 20-base.sh* — pluto already better than neptuno here).
  - **Brightness** is handled by DMS's own `dms ipc call brightness` binds (neptuno `dms/binds.kdl`: `XF86MonBrightnessUp → dms ipc call brightness increment 5 ""`) — no gsd needed.
  - **Color/ICC** is a real gap on pure niri (no gsd-color); DMS/matugen handles *theme* color, not display ICC profiles. Same gap exists in pluto — inherited, not fixable via neptuno.
- **What a niri desktop still genuinely needs from the GNOME stack** (all already in pluto's base.toml, validated by neptuno's package list):
  1. **gnome-keyring** (+ PAM or global-enable) — for git credential-libsecret, browsers, wifi secrets. Neptuno installs both `gnome-keyring` and `git-credential-libsecret` and enables the daemon.
  2. **xdg-desktop-portal-gnome** — neptuno installs it explicitly in the DMS layer (`40-dms.sh:18`); provides Screenshot/Settings portal backends; pluto already has it (base.toml).
  3. **accountsservice** — neptuno installs it (`40-dms.sh:19`) even though it's a GNOME-adjacent daemon; DMS/greeter/apps query it (pluto: niri.toml).
  4. **NAUTILUS as a fallback file manager** — pluto already ships nautilus; neptuno relies on nautilus on niri for file ops (its preinstall even adds NautilusPreviewer) — consistent.
  5. **GNOME apps (text editor, calculator, disks, file-roller…)** — neptuno treats them as first-class niri apps (window-rules for `org.gnome.*` apps with 12px corner radius, floating calculator rules). Pluto already follows the same model.
  6. **`dconf`** — needed by GTK apps even without GNOME Shell (pluto already has it; neptuno gets it via base).
- **GNOME daemons that are NOT needed on niri** (present in neptuno only because silverblue ships them; skip in pluto): `gnome-shell`, `mutter`, `gnome-session`, `gnome-shell-extension-*`, `gnome-initial-setup` (neptuno explicitly disables it), `gnome-remote-desktop`, `gnome-software` (neptuno removes it!), `gnome-tweaks` etc.
- **Tooltip for pluto that neptuno surfaces**: the silverblue GNOME session is actually the *recovery* desktop for neptuno users (GDM → "GNOME" fallback). Pluto has no such fallback — any GNOME-shell-specific troubleshooting path is unavailable. That's a design tradeoff to accept consciously, not a bug to port.

**Verdict:** pluto's GNOME-daemon posture (keyring-PAM + portal-gnome + accountsservice + nautilus + dconf + power-profiles-daemon) matches exactly what neptuno's niri session actually exercises. Nothing in neptuno's GNOME base needs porting for the niri session; the only deepenings available are (a) an ICC/color-management story and (b) optionally a recovery desktop — both iff desired.

---

## 7. Could not determine (explicit)

1. **F44 vs F43 package availability** — the following neptuno installs could not be verified against Fedora 43 (pluto's base) from the local repos: `alsa-tools-firmware`, `flatpak-spawn`, `intel-vaapi-driver`, `jetbrains-mono-fonts-all`, `opendyslexic-fonts`, `powerstat`, `nicstat`, `tiptop`, `openrgb-udev-rules`, `libratbag-ratbagd`, `cava`, `khal`. Pluto's own research notes contradict `alsa-tools-firmware` and `flatpak-spawn` for F43. Verify each before porting (pluto's assert gates will catch failures at build time).
2. **`dsearch` vs `danksearch`** as the current avengemedia/danklinux package name (see §5.3).
3. **Current bootc status of unified storage** (`bootc image set-unified`) as of 2026-08 — the unit's own comments say experimental (issue bootc-dev/bootc#20); may have become default.
4. **Whether neptuno's CI currently builds green** — the `Containerfile` pins silverblue:44 and yalter/niri COPR; the `70-tests.sh` NEGATIVO vendor assertions reference `x264-libs`/`x265-libs` that the 20-base.sh install transaction does **not** explicitly list (they arrive as ffmpeg deps from negativo — fragile assertion). Could not confirm an actual pass without network access to the repo's Actions.
5. **Whether `flatpak-spawn`/`alsa-tools-firmware` exist on F44** — if they do not, neptuno's `20-base.sh` would fail a fresh build; cannot verify without querying F44 package DB (both are in a single `dnf5 install -y` line, erroring the whole transaction on a missing name).
6. **GDM version on F44** and whether `FallbackSession` is partially honored — the config comment asserts F45+/GDM≥51; local files can't confirm.
7. **Which negative mesa override packages actually rebase cleanly** on F43 (pluto already distro-syncs the set minus `intel-gmmlib`/`libheif`; neptuno includes both — local verification of version consistency not possible).
8. **DMS version differences** between the two images (`quickshell-git`/`dms` built against F44 vs F43 toolchains, `danksearch`/`dsearch` divergence) — behavior parity of the IPC surface (`dms ipc call …`) assumed from file similarity, not proven by running either image.

---

## 8. One-line reference (scope requirement)

The neptuno repository contains no mention of any `neptuno-shell` project; that sibling directory was not read.
