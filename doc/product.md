# Neptuno: product plan for the ground-up rebuild

Status: **plan, not implemented**. Written 2026-11-11 on branch `rebuild`,
then reviewed once by Fable 5.2. The review's findings are folded into the
sections below. **Revised 2026-11-11:** packages, portals and keyring were
re-researched against live Fedora 45 repos and the running laptop; sections
2, 4, 5, 6.2, 6.4, 7.2, 9, 15 to 18 and 20 changed.
**Revised 2026-11-14:** a new section 17 (power, boot and responsiveness,
with a measured baseline and a Pond comparison) was added before Risks, so
Risks, Spikes, Milestones and Decisions are now 18 to 21. Sections 4, 7.2, 9,
13, 18, 19 and 21 gained matching items.
Evidence for every claim below lives in the research notes that produced
this document (decision tree plus research packages RP-A to RP-I). Anything
marked **SPIKE** is unproven and must pass a VM test before it is built for
real.

## 1. What Neptuno is

A personal Fedora bootc image for one user, running niri and DankMaterialShell,
used daily for general work and software development on an ASUS Zenbook
UM3402YA (Ryzen 5 7530U, Radeon iGPU, MediaTek MT7922 Wi-Fi; bare metal).

Goals, in priority order:

1. **Seamless.** Login, shell, theming, portals, keyring, updates and package
   installs work together without hand-wiring.
2. **Low maintenance.** Few third-party sources, no upstream template to track,
   no release ceremony. Most weeks need zero human action.
3. **Easy daily use.** One obvious way to install each kind of software.
4. **Not bloated.** No second desktop and no unused stacks, but convenience
   beats minimalism.

Non-goals: a community distro, multiple variants, NVIDIA or Intel support,
out-of-tree kernel modules, ARM.

## 2. Decisions at a glance

| Area | Decision |
|---|---|
| Base | `quay.io/fedora-ostree-desktops/base-atomic:45`, digest-pinned. bootc stays the update and rollback mechanism. |
| Desktop | niri (Fedora) + DankMaterialShell (duxlabs COPRs). GNOME and GDM are removed. |
| Login | greetd (Fedora) + `dux-greeter` (DMS greeter) |
| Ecosystem | Leave Project Bluefin / Universal Blue entirely. Own the few pieces worth keeping. |
| Repo layout | Monorepo (`neptuno`). No shared "common" repo for now. |
| GUI apps | GNOME apps. Flatpak from Flathub, except Nautilus, Text Editor and Disks, which are RPMs (5.5). Resources replaces System Monitor. Other GUI apps: Flatpak. |
| Keyring | oo7 (`oo7-daemon`, `pam_oo7`) owns the Secret Service, as in Fedora 45. gnome-keyring is not installed. `gcr-ssh-agent` is the SSH agent. See 6.4. |
| Portals | xdg-desktop-portal-gnome + gtk, plus `gnome-control-center` installed now for niri global shortcuts, which turn on by themselves once Fedora ships a niri release with them. See 6.2. |
| CLI tools | Nix (Fedora's RPMs) through a thin imperative wrapper |
| Toolchains | mise (rust, go, python, bun, java, uv), unchanged |
| Host builds | Curated `-devel` libraries in the image. GUI-stack devel goes in a distrobox. |
| Edge cases | distrobox |
| Multimedia | Stock Fedora. negativo17 and its Mesa overrides are dropped. |
| Updates | bootc timer stages only and never reboots by itself. Flatpak and Nix get their own timers. |
| Trust | Keyless cosign (GitHub OIDC), verified in CI before any tag moves. The laptop uses `ostree-unverified-image`, as today. |
| Release | One branch. `main` publishes `:latest` plus dated tags. Daily rebuild. PRs build without publishing. |
| Secure Boot | Works on or off, because only Fedora's signed kernel is used and there are no kmods. Hibernate, as today, needs it off (kernel lockdown). |

## 3. Repository and naming

**Monorepo.** One consumer and one maintainer means a shared repo adds a
version-skew problem without a second user to justify it. The tree stays
split-ready (`system_files/shared` vs `system_files/desktop`), so a shared
layer can be extracted with `git filter-repo` if a second image ever appears.

**Do not use the name "Terra".** Terra is Fyra Labs' well-known Fedora
third-party package repository (`terra.fyralabs.com`). Zirconium, the closest
comparable image, consumes it. The name would collide in `dnf repolist`,
search results and conversation. If a shared layer is ever split out, call it
something unambiguous such as `neptuno-common`. If we ever need our own RPMs
(see risk R1), that is a separate `neptuno-rpms` COPR, not a shared image
layer.

**Flow.** Work happens on `rebuild`. It is pushed to `Siddhj2206/neptuno-testing`
as that repo's `main`, which publishes `ghcr.io/siddhj2206/neptuno-testing`.
Once proven, it is pushed to `Siddhj2206/neptuno` as `next` and merged into
`main` by PR.

Proposed layout:

```
Containerfile
Justfile                     # build, lint, test, vm, iso — no Bluefin recipes
build/
  00-image-info.sh           # os-release, image-info.json
  10-overlay.sh              # system_files/ + unit snapshot
  20-packages.sh             # all manifests, one script
  30-desktop.sh              # greeter, session wiring, schema compile
  40-nix.sh                  # /nix mount, nix units
  90-cleanup.sh              # disable repos, audit units, lint prep
  packages/{base,desktop,devlibs,hardware,removals}.toml
  scripts/{package-lib.sh,read-packages,systemd-units}   # kept from today
system_files/
  shared/ ...                # updates, signing, flatpak, nix, wrapper
  desktop/ ...               # niri/DMS/greeter defaults
flatpaks/default.preinstall
iso/                         # image-builder configs
tests/                       # bats contract + image-content checks
.github/workflows/{build.yml,clean.yml}   # Renovate is the hosted app
doc/product.md               # this file
AGENTS.md, .agents/skills/   # rewritten for the new layout
```

**Keep from today's repo** (it is the good part): the manifest engine
(`package-lib.sh`, `read-packages`, `systemd-units`), the "declare, then
enable" unit audit in `90-cleanup.sh`, the COPR enable, install, disable
discipline, the Flathub `.flatpakrepo` descriptor approach (never a build-time
`remote-add`), `bootc container lint --fatal-warnings`, `/opt -> /var/opt`,
the input `uaccess` udev rule, `coreos-sulogin-force-generator`, and the late
`ARG` metadata ordering that protects layer caching.

**Drop**: the `common` and `brew` OCI context stages, `projectbluefin/actions`,
the promote, execute-release and sync-back workflows, Brewfile validation, the
multimedia manifest, the uupd COPR, and the Bluefin-specific bats suites.

## 4. Base image facts

`base-atomic:45` (version `45.20261110.0`, kernel 7.2.15, bootc 1.17.1,
flatpak 1.18.4, systemd 262) lints clean unmodified.

- **Already in the base:** NetworkManager (+wifi), pipewire, wireplumber, bluez, firewalld,
  fwupd, polkit, xdg-desktop-portal 1.22.1, xdg-desktop-portal-gtk, linux-firmware + amd-gpu-firmware, mesa,
  plymouth, bootupd, cups (+cups-filters, cups-browsed), avahi, upower, udisks2, podman, toolbox, skopeo,
  openssh-server, sudo, ibus (+anthy, chewing, hangul, libpinyin, m17n,
  typing-booster), alsa-sof-firmware, alsa-ucm, libldac, wl-clipboard,
  accountsservice, geoclue2, gnupg2, localsearch, sane-backends + sane-airscan,
  samba-client, gamemode, wireguard-tools, ntfs-3g, exfatprogs, btrfs-progs,
  zram-generator, thermald, `google-noto-sans-cjk-vf-fonts`,
  `google-noto-color-emoji-fonts`, ffmpeg-free and the gstreamer `-free` plugins.
  It has **no** gnome-keyring, oo7, gcr or xdg-desktop-portal-gnome.
- **Missing, and we add it:** libinput, xdg-user-dirs, tuned + tuned-ppd,
  fish, zsh, distrobox, NetworkManager-tui, greetd, gcr, the oo7 packages
  (through the gnome portal), gvfs, switcheroo-control
  (optional), iio-sensor-proxy (optional; no sensors on this laptop).
- **Enabled by base presets but not wanted on a desktop or laptop**, so they
  go in the manifest's `disabled` list: qemu-guest-agent, vmtoolsd, vgauthd,
  vboxservice, ModemManager, mdmonitor, lvm2-monitor, systemd-homed, sssd and its sockets,
  `flatpak-add-fedora-repos.service` (it adds Fedora's OCI Flatpak remote).
  We also drop `fedora-third-party-refresh`. Added 2026-11-14 for boot time and
  idle wakeups (section 17.3): `NetworkManager-wait-online.service`,
  `dnf-makecache.timer`, `raid-check.timer`, `rpm-ostree-countme.timer` and
  `unbound-anchor.timer`. `flatpak-appstream-refresh.service` is not enabled
  at boot either.

## 5. Packages

All RPM, `install_weak_deps=False` kept. Sources are Fedora 45 unless noted.
This section was re-verified on 2026-11-11 against `registry.fedoraproject.org/fedora:45`
(with the `fedora` and `updates` repos, the COPRs `duxlabs/dms` and
`duxlabs/dux-repo`, and Tailscale's stable repo) using `dnf5 repoquery
--available --latest-limit=1`. "Verified" below means that command returned
that version. A dry-run install of the whole desktop set on
`base-atomic:45` resolved cleanly (285 packages, about 1 GiB, no
conflicts). Sections 5.1, 5.2 and 5.5 were rechecked in full (5.3 was not). Several
claims in the first draft were wrong; they are corrected below and listed in
5.7.

Two facts shape the list:

- **Fedora 45 ships GNOME 51**, not 50 (`gnome-control-center` 51.1,
  `nautilus` 51.1, `xdg-desktop-portal-gnome` 51.0).
- **Fedora 45 replaced gnome-keyring with oo7** as the default Secret Service
  (see 6.4). `gnome-keyring` 51.1 is still in the repos, but no comps group
  pulls it in, and GNOME pulls oo7 in through `xdg-desktop-portal-gnome`.

### 5.1 Desktop session (`desktop.toml`)

**Compositor, shell, login**

| Package | Source | Why | Verified F45 |
|---|---|---|---|
| niri | Fedora | Compositor. Ships `niri.service`, `niri-session`, `niri-portals.conf`, `niri validate`. Hard-requires `xwayland-satellite >= 0.7`. It *recommends* gnome-keyring, alacritty, fuzzel, swaylock and waybar; with weak deps off we get none of them. | 26.04-2.fc45 (latest upstream release is also v26.04). See 6.2 for global shortcuts. |
| xwayland-satellite | Fedora (pulled by niri) | X11 apps | 0.8.3-1.fc45 |
| dms, dms-cli | COPR `duxlabs/dms` | The shell. Requires `quickshell` or `quickshell-git`, `accountsservice`, `gzip`, `wget`. | 2.1.2-1.fc45 (current image: 2.1.0) |
| quickshell-git | COPR `duxlabs/dux-repo` | Owner decision (D15): the git build, as today. The current manifest says it's needed for polkit and idle support, and DMS tracks it. Fedora's own `quickshell` (0.2.1^git20260209) is too old for DMS. Never install the stable `quickshell` alongside it. Floats like every COPR package (R1). | 0.3.3^879.git9b0f339 |
| dux-greeter (provides `dms-greeter`) | COPR `duxlabs/dux-repo` | Login screen. Needs `greetd` and a `greeter` user (sysusers). | 2.1.2-1.fc45 |
| greetd, greetd-selinux | Fedora | Display manager. The package already ships `/usr/lib/pam.d/greetd` with optional `pam_gnome_keyring`, `pam_kwallet5`, `pam_kwallet` **and `pam_oo7`** lines, so keyring unlock needs no PAM edit (6.4). | 0.10.3-12.fc45 |
| matugen | COPR `duxlabs/dux-repo` | Fedora has 3.1.0, DMS wants 4.x | 4.2.0-1.fc45 |
| dux-search, dux-gop | COPR `duxlabs/dux-repo` | `dsearch.service` file search and the `dgop` system-stats helper. Both are *Recommends* of dms, so with weak deps off they must be named. Both are installed today. | 2.1.1-1.fc45 each |
| ghostty | COPR `duxlabs/dux-repo` | Default terminal. Not in Fedora. Pulls `gtk4-layer-shell`. | 1.4.0-3.fc45 |
| material-symbols-fonts | COPR `duxlabs/dux-repo` | Icon font for DMS | 1.0-1.fc45 |
| xdg-terminal-exec | Fedora | Default-terminal resolver | 0.14.3-1.fc45 |

The same COPR carries `dux-files` (file manager) and `dux-calendar`. We don't
use them: the owner prefers the GNOME apps (5.5).

**Portals, secrets, polkit**

| Package | Source | Why | Verified F45 |
|---|---|---|---|
| xdg-desktop-portal | base | Already in `base-atomic` | 1.22.1-2.fc45 |
| xdg-desktop-portal-gtk | base | Already in `base-atomic`. Fallback portal, Access and Notification. | 1.15.3-6.fc45 |
| xdg-desktop-portal-gnome | Fedora (updates) | ScreenCast, Screenshot, FileChooser, and the GlobalShortcuts interface (its `gnome.portal` lists it). Requires `xdg-desktop-portal >= 1.21.1` and `oo7-portal`. | 51.0-2.fc45 |
| oo7-daemon, oo7-portal, pam_oo7 | Fedora | The Secret Service, its portal backend, and the PAM unlock module. `oo7-portal` and `pam_oo7` each require `oo7-daemon` of the same build. | 0.7.0~beta^1.e91b98a-1.fc45 (a beta snapshot) |
| oo7-cli | Fedora | Inspect and manage the keyring from a terminal. Optional. | same build |
| gcr | Fedora | Ships `gcr-ssh-agent.socket` (SSH agent that stores passphrases in the Secret Service) and the GCR prompter. Not in `base-atomic`. | 4.4.1-1.fc45 |
| gnome-control-center | Fedora | **For niri global shortcuts** (6.2). Installed now so the feature works with no further change once Fedora's niri has it. 33 packages, 74 MiB on `base-atomic`. Its launcher entry is hidden (6.2). | 51.1-1.fc45 |
| (polkit agent) | DMS | DMS provides it. Nothing to install. `polkit` is in the base. | n/a |

Deliberately **not** installed: `gnome-keyring`, `gnome-keyring-pam` (a second
Secret Service owner, see 6.4), `swaylock`, `waybar`, `mako`, `alacritty`,
`fuzzel`, `xdg-desktop-portal-wlr`, `xdg-desktop-portal-hyprland` (not in F45),
any polkit-gnome or KDE polkit agent. Watch item: the dry-run transaction
includes `kf5-kwallet` and `kf6-kwallet` (6.31.0) along with a large kf5 and
kf6 library set, via `kf6-kio-core`, which `plasma-breeze` brings in
(**unverified** that this is the only path). That is the Qt/KDE theming
trio's real cost. S3 must confirm that kwallet never takes
`org.freedesktop.secrets` (it ships `kwallet.portal` and an
`org.kde.secretservicecompat` D-Bus service).

**Files, storage, thumbnails**

| Package | Source | Why | Verified F45 |
|---|---|---|---|
| nautilus | Fedora | File manager. It must be a host RPM: it browses the real filesystem, mounts devices and runs the gvfs backends. xdg-desktop-portal-gnome uses it as the file chooser (niri wiki, "Important Software"). | 51.1-2.fc45 |
| gvfs, gvfs-fuse, gvfs-mtp, gvfs-smb, gvfs-afc | Fedora | `nautilus` requires `gvfs`. The others are weak deps or comps defaults; mtp is for Android (the owner has `android-tools`), smb for network shares (`samba-client` is in the base), afc for iPhones (see `ifuse`). Drop afc and smb if unused. | 1.62.0-4.fc45 |
| glycin-thumbnailer, gst-thumbnailers, papers-thumbnailer | Fedora | Image, video and PDF thumbnails in Nautilus. Replace `ffmpegthumbnailer` and `totem-video-thumbnailer`. The first two are nautilus weak deps, so they must be named. | 2.2.6-1, 1.1.0-1, 51.1-1 (.fc45) |
| gnome-disk-utility | Fedora | "Disks". Needs udisks2 and root helpers, so it can't run in a sandbox. Not on Flathub (`org.gnome.DiskUtility` returns 404 from the Flathub API). | 46.1-9.fc45 |
| gnome-text-editor | Fedora | Default text handler and editor for system files such as `/etc` (an unprivileged Flatpak is a poor fit for that; **unverified**, the Flatpak's exact permissions weren't checked). 2.6 MiB installed. See 5.5. | 51.0-1.fc45 |
| udiskie | Fedora | User-level automount and unmount, since there is no GNOME Shell. gvfs mounts on click but doesn't automount. | 2.7.0-1.fc45 |

**Input, theming, fonts**

| Package | Source | Why | Verified F45 |
|---|---|---|---|
| libinput, libnotify, xdg-user-dirs | Fedora | Not in `base-atomic` | 1.32.0-1, 0.8.9-1, 0.20-2 |
| wl-clipboard | base | Already in `base-atomic` (the first draft listed it as missing) | n/a |
| kanshi | Fedora | Output profile daemon. Optional; DMS has its own display settings, so drop it unless a profile is actually needed. | 1.9.0-2.fc45 |
| qt6ct, adw-gtk3-theme, kf6-qqc2-desktop-style, plasma-breeze, kf6-kirigami | Fedora | Theming that DMS and matugen drive. Matches the current image. | 0.11-17, 6.4-4, 6.31.0-1, 6.8.2-1, 6.31.0-1 (.fc45) |
| ibus-mozc | Fedora | Japanese input, replacing today's `ibus-anthy`. Mozc's conversion quality and dictionary are clearly better than Anthy's, and `~/.config/mozc` already exists on the laptop. `ibus-anthy` (in the base) is removed (5.4). | 2.29.5111.102-21.fc45 |
| google-noto-sans-fonts, jetbrains-mono-fonts, rsms-inter-fonts | Fedora | UI and monospace fonts. Not in the base. | 20260601-3, 2.304-11, 4.1-4 (.fc45) |
| google-noto-color-emoji-fonts, google-noto-sans-cjk-vf-fonts, default-fonts-cjk-sans | base | Already in `base-atomic` and **kept** (owner decision). Today's image removes the CJK fonts; the new one stops doing that, so Japanese text renders with Noto Sans CJK. | 2.004-12.fc45 |

**DMS optional extras** (all are `Recommends` of dms or were in the old
manifest; with weak deps off each must be named to be present)

| Package | Why | Verified F45 |
|---|---|---|
| cava | Audio visualiser widget. Installed today. | 0.10.2-8.fc45 |
| qt6-qtmultimedia | `Recommends` of dms; what DMS uses it for is **unverified** (media or video widgets). Installed today, not in the base. | 6.11.2-2.fc45 |
| khal (pulls vdirsyncer) | Calendar backend for the DMS calendar. Installed today (added by hand, not a dms Recommends). Kept (owner decision). | 0.14.1-1.fc45 |
| cups-pk-helper | `Recommends` of dms (printer settings). Only with D2 (printing) on. | 0.2.7-13.fc45 |

### 5.2 Base system (`base.toml`)

Versions are the verified F45 builds.

- **Shells and CLI glue:** fish 4.6.0-2 (default login shell), zsh 5.9.2-3, bash-completion 2.18-1, just 1.59.0-1, jq 1.8.2-5, fzf 0.74.5-1, gum 2.0.2-1, tmux 3.8-2, fastfetch 2.68.1-1, git 2.56.0-1, git-credential-libsecret 2.56.0-1 (works with oo7, it only speaks libsecret), 7zip-standalone 26.04-1, distrobox 1.8.2.5-2, NetworkManager-tui 1.58.1-3
- **Power and hardware:** tuned 2.28.0-1, tuned-ppd 2.28.0-1 (provides `ppd-service`, the `org.freedesktop.UPower.PowerProfiles` API DMS calls; power-profiles-daemon is not needed), brightnessctl 0.5.1-17, playerctl 2.4.1-13, ddcutil 3.0.2-1, lm_sensors 3.6.0-25, powertop 2.15-13, smartmontools 7.5-11, libva-utils 2.24.0-2, android-tools 37.0.0p1-1, steam-devices 1.0.0.101^git20260625-2, evtest 1.36-3
- **Security keys:** pam-u2f 1.4.0-8, pamu2fcfg 1.4.0-8, yubikey-manager 5.9.2-2
- **Containers:** podman-docker 6.1.3-1, docker-compose 5.6.0-1 (works against the user `podman.socket`, with `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` set in environment.d). Decision D4.
- **Networking:** tailscale 1.104.6-1 from the official Tailscale repo. **Verified: Fedora 45 does not package it**, so the third-party repo is needed. It is used only at build time and removed after install, as today.
- **Kept from today (owner decision):** input-remapper 2.2.1-2, firewall-config, NetworkManager-openvpn, NetworkManager-openconnect, openvpn, fuse and fuse-libs (FUSE 2, for host AppImages). Their versions weren't re-checked in this revision.
- **Zenbook extras:** zenity 4.2.2-5 and tcpdump 4.99.6-5, moved here from brew. Optional and only on demand: libratbag-ratbagd 0.18-6, ifuse 1.2.1-5, borgbackup 1.4.5-1.
- **Fingerprint (D12, decided: yes):** fprintd 1.94.5-6 + fprintd-pam. `base-atomic`'s authselect profile is `local with-silent-lastlog with-mdns4`, without `with-fingerprint`, so the build runs `authselect enable-feature with-fingerprint`. That puts `pam_fprintd` in `system-auth`, which the DMS lock screen (through its PAM file) and `run0`/sudo include. **Not at the greeter:** `pam_fprintd` sits as `sufficient` ahead of `pam_unix`, so at greetd it swallowed the typed password and a fingerprint login left `pam_oo7` nothing to unlock the keyring with (found on the laptop, 2026-11-16). `/etc/pam.d/greetd` therefore takes auth from `password-auth`, which has no `pam_fprintd` (6.4). **Unverified** how dux-greeter shows the fingerprint prompt.
- **ASUS (D5, decided: keep):** asusctl 6.3.8 from COPR `lukenukem/asus-linux` (the asus-linux project's own repo; Fedora doesn't package it). Runtime requires only glibc, libudev and friends. Ships `asusd.service`, `asus-shutdown.service`, `asusd-user`, a udev rule and a D-Bus system policy, so it must be an image RPM: a Nix profile can't install system units, udev rules or D-Bus policy (nixpkgs has `asusctl`, but only NixOS can wire the daemon). Replaces today's `/opt/ublue-asusctl` build. The COPR is enabled, installed from and disabled like the duxlabs ones. `asusctl-rog-gui` is not installed.
- **Optional hardware:** switcheroo-control 3.0-9, iio-sensor-proxy 3.9-3.

### 5.3 Host development libraries (`devlibs.toml`)

The point is that a plain `cargo build` works and the binaries it produces run.
It also replaces the old `~/.local/share/brew-pkgconfig` workaround. (Names
here were not re-verified in this revision; the 2026-11-11 check covered
sections 5.1, 5.2 and 5.5 only.)

- **Core, in the image** (about 320 MiB installed, mostly the C++ toolchain): gcc, gcc-c++, make,
  pkgconf-pkg-config, openssl-devel, sqlite-devel, zlib-ng-compat-devel,
  fontconfig-devel, freetype-devel, alsa-lib-devel, systemd-devel (it provides
  `libudev.pc`, since `libudev-devel` doesn't exist), dbus-devel, libgit2-devel,
  libssh2-devel, libcurl-devel.
- **Not in the image:** clang-devel/bindgen (about 1 GiB), gtk4-devel, webkit2gtk4.1-devel, tauri
  and bevy stacks. These go in a `fedora-toolbox:45` distrobox. A `neptuno`
  recipe creates a ready-made "devbox" with them.
- **Optional compositor tier** (about 300 MiB; Decision D6): wayland-devel, libxkbcommon-devel,
  libinput-devel, libseat-devel, libdrm-devel, mesa-libgbm-devel.

### 5.4 Removed relative to the base and to today

**Removed from the base image.** `base-atomic` is already minimal. Only the
unused input engines get a `[remove]` entry. The CJK fonts stay. (Services the base
enables but this hardware doesn't want are disabled, not removed; see
section 4.)

| Package | Reason |
|---|---|
| `ibus-anthy`, `ibus-chewing`, `ibus-hangul`, `ibus-libpinyin`, `ibus-m17n`, `ibus-typing-booster` | In `base-atomic`, unused now that Japanese input is mozc. Removing them also keeps the ibus engine list to one entry. |
| `firefox`, `firefox-langpacks` | In `base-atomic`. Zen (Flatpak) is the browser, and the RPM went unused. |
| `nvidia-gpu-firmware` | In `base-atomic`: 100 MB of nouveau GSP firmware, which `base-atomic`'s initramfs also carried (236 MB in all, read by GRUB on every boot). Neptuno has no NVIDIA support. `build/50-initramfs.sh` rebuilds the initramfs with `/usr/lib/dracut/dracut.conf.d/90-neptuno.conf`, which omits nouveau and nova. |

**Removed relative to today's Silverblue-based image.** The GNOME stack, gdm,
ptyxis, gnome-software, firefox RPM, negativo17 ffmpeg and
gstreamer plus the Mesa overrides, `ffmpegthumbnailer`, igt-gpu-tools,
oversteer-udev, solaar-udev, pam_yubico, ykpers, ykclient, uupd, every brew and
ublue unit, and projectbluefin countme.

### 5.5 GNOME apps: RPM or Flatpak

Owner preference: GNOME apps. The rule used here: an app is an RPM only when
it cannot work in a sandbox or the shell depends on it; everything else is a
Flathub Flatpak, because app updates then don't ride on the daily image
rebuild, each app is sandboxed, and the owner already has all of them as
Flatpaks. All Flathub versions below were read from the Flathub API on
2026-11-11.

| App | Where | Reason | Version (F45 RPM / Flathub) |
|---|---|---|---|
| Files (Nautilus) | RPM | Host filesystem, mounts, gvfs, portal file chooser | 51.1-2 / no Flatpak |
| Text Editor | RPM | Edit root-owned files, default text handler | 51.0-1 / 51.0 |
| Disks | RPM | Needs udisks2 and polkit on the host | 46.1-9 / not on Flathub |
| Resources (`net.nokyan.Resources`) | Flatpak | Owner's choice over GNOME System Monitor (an RPM, since it isn't on Flathub). GNOME Circle app, installed today. | n/a / Flathub |
| Image Viewer (Loupe) | Flatpak | Fully portal-friendly | 51.1 / 51.2 |
| Document Viewer (Papers) | Flatpak | Same. Thumbnails come from the RPM `papers-thumbnailer`. | 51.1 / 51.1 |
| Video Player (Showtime) | Flatpak | Codecs come from the Flathub runtime (5.6) | 50.0 / 50.0 |
| Audio Player (Decibels) | Flatpak | | 49.6.1 / 49.6 |
| Calculator | Flatpak | | 51.1 / 51.1 |
| Baobab (Disk Usage) | Flatpak | Scans only what its Flatpak permissions allow (**unverified** which); a Flatpak override may be needed to scan `/` | 50.0 / 50.0 |
| Clocks, Weather | Flatpak | Location through geoclue (in the base) and the portal | 51.0, 50.0 / same |
| Characters, Fonts (Font Viewer) | Flatpak | | 51.0, 50.0 / same |
| Camera (Snapshot) | Flatpak | Camera portal | 51.0-2 / 51.0 |
| File Roller | Flatpak | Nautilus already extracts and compresses through `gnome-autoar`, so File Roller is only the GUI for odd formats | 44.7-3 / 44.7 |
| Sushi (Quick Look) | Flatpak (`org.gnome.NautilusPreviewer`) | Installed today as a Flatpak and Nautilus finds it over D-Bus. The RPM `sushi` 51.2-4 also exists. | 51.2 |
| Calendar, Contacts, Logs, Connections, Boxes, Simple Scan, Firmware, Déjà Dup | Flatpak | Installed today. Firmware is a front end for `fwupd` (in the base). | all on Flathub |

Not in the GNOME set, and why: GNOME Software (removed, Bazaar is the store);
Epiphany (Zen and Floorp are the browsers); the old Silverblue extras
`gnome-remote-desktop`, `gnome-user-share`, `gnome-color-manager` (no GNOME
Shell). `gnome-control-center` is a special case (6.2).

Text Editor stays an RPM (owner decision).

### 5.6 Multimedia

Fedora's radeonsi VA-API already advertises H.264 and HEVC decode and encode
on this iGPU. Fedora 45 has no `mesa-va-drivers-freeworld`. Flatpak apps get
their codecs from the Flathub runtimes (`org.freedesktop.Platform.ffmpeg-full`
or `codecs-extra`, both already installed on the laptop). `base-atomic` has
`ffmpeg-free`, `libavcodec-free` and the gstreamer `-free` plugins. No host
codec work is planned. If a host app ever needs openh264, Fedora's Cisco repo
is already configured. aptX Bluetooth isn't available in Fedora and isn't
needed.

### 5.7 Dropped from today's image

Everything below is installed on the laptop now and has no place in the plan
unless the owner objects. Source: `rpm -qa` on the laptop compared with
`silverblue:45`, plus `build/packages/*.toml`.

| Dropped | Reason |
|---|---|
| autoconf, automake, libtool, m4, bison, flex, patch, binutils, glibc-devel (explicit) | They existed for Homebrew source builds. Brew is gone and Nix does not compile on the host. `gcc`, `make` and `pkgconf` stay (5.3); `glibc-devel` and `binutils` come with gcc. |
| gtk-layer-shell | Library for GTK3 layer-shell panels. Nothing in the plan uses it. `ghostty` pulls `gtk4-layer-shell` itself. |
| libappindicator-gtk3, libayatana-appindicator-gtk3 | Tray support for host GTK3 apps. The plan has no host GTK3 tray app, and Flatpaks bundle their own. DMS shows StatusNotifier items. |
| nautilus-python | Nautilus extension host. Nothing in the plan extends Nautilus. `papers-nautilus` is also left out. |
| waypipe | CLI for remote Wayland apps. Moves to Nix (`nx add waypipe`). |
| libratbag-ratbagd, ifuse, borgbackup, solaar-udev | Hardware helpers. Already "optional on demand" in 5.2; listed here because all are installed today. Owner to confirm each. |
| igt-gpu-tools | Intel GPU tools. The laptop is AMD. |
| oversteer-udev | Racing wheel udev rules, COPR-only (`ublue-os/packages`). Drops the last ublue COPR. |
| pam_yubico, ykpers, ykclient, python3-yubikey-manager | OTP stack. `yubikey-manager` and `pam-u2f` stay, which cover FIDO2. |
| uupd, brew-* and ublue-* units, projectbluefin-countme | Leaving the ecosystem (section 15) |
| `lm_sensors.service` (enabled today) | Only loads sensor modules at boot; `sensors-detect` is manual. `lm_sensors` itself stays. |
| `docker.service`, `asusd-user.service`, `opencode-bin.service`, `pluto-host.service`, `wifilogin.service`, `hex.service` | These are **user units in `~/.config/systemd/user`**, not image content. They survive the switch and stay the owner's. asusctl itself is not installed (D5). |

Kept from the base without comment because they're already there: `gamemode`,
`wireguard-tools`, `ntfs-3g`, `exfatprogs`, `btrfs-progs`, `sane-airscan` and
`cups-filters` (note that D2 says "No sane", but `base-atomic` ships the sane
backends anyway; the Simple Scan Flatpak uses its own).

## 6. Desktop session design

### 6.1 Boot to desktop

`greetd.service` runs `dms-greeter --command niri` as the sysusers-provided
`greeter` user on VT1. This follows the dux-greeter README and Zirconium.
After login, the niri session starts `niri.service`. `dms.service` and
`dsearch.service` are linked into `niri.service.wants`, a mechanism kept from
today, so the shell never starts in any other session.

- **greetd config:** `/etc/greetd/config.toml` is shipped in the image. bootc
  3-way merges `/etc`, so a local edit survives updates.
- **Greeter state:** the greeter's cache lives in `/var/cache/dms-greeter`
  (tmpfiles).
- **Default target and display manager:** set explicitly in the build, with
  `default.target` pointing at `graphical.target` and
  `display-manager.service` aliased to `greetd.service`. A machine migrating
  from GDM must not keep a stale alias.
- **A fresh user's first login:** nothing would otherwise create the thin
  user files, and niri would write its own stock default for DMS to patch.
  So ship thin stubs in `/etc/skel`: `~/.config/niri/config.kdl` (the base
  include plus the DMS includes) and `~/.config/ghostty/config` (the base
  `config-file`). A stub only points at `/usr`, so it never goes stale.
  The DMS files and settings are seeded alongside (section 8).
- **Recovery when the shell or greeter breaks:**
  - VT2 keeps a normal `getty` login.
  - The GRUB menu stays reachable, so an older deployment can be booted.
  - `dms.service` has `Restart=on-failure`.
  - These steps are documented in the troubleshooting skill.
- **SPIKE S2:** full greeter-to-session login on base-atomic, covering:
  - accountsservice avatars and `dms-greeter sync` on a read-only `/usr`
  - an empty home reaching a working desktop with a terminal and keybinds
  - lid close → s2idle → resume showing a locked DMS, with lock-screen PAM
    working
  - a killed `dms.service` restarting
  - VT2 login when the greeter fails
  - Japanese input
  - the keyring (6.4) is covered separately by S3.

### 6.2 Portals and global shortcuts

niri's `niri-portals.conf` routes `default=gnome;gtk;`, so
xdg-desktop-portal-gnome provides screencast, screenshot and the file chooser
(Nautilus, which xdg-desktop-portal-gnome 47 and later uses by default), and
the gtk portal covers Access and Notification.

**The shipped file is stale for secrets.** The file installed by Fedora's
`niri-26.04-2.fc45` (read on the laptop) says
`org.freedesktop.impl.portal.Secret=gnome-keyring`. The first draft quoted
`oo7-portal;gnome-keyring;`, which is the line in xdg-desktop-portal-gnome's
`gnome-portals.conf` and in niri's *main* branch (commit "portals: add oo7 as
secret portal", 2026-09-15, not in any release yet). With gnome-keyring not
installed, the 26.04 file names a backend that doesn't exist. The laptop has no
override and the owner reports no problem, so xdg-desktop-portal may fall back
to any backend that implements Secret, but that is **unverified**. Also, the
`oo7-portal.portal` file says `UseIn=gnome`, which matters only when no
`portals.conf` matches. The plan: ship
`/etc/xdg-desktop-portal/niri-portals.conf` (it overrides the file in
`/usr/share`, per [portals.conf(5)](https://flatpak.github.io/xdg-desktop-portal/docs/portals.conf.html);
precedence **unverified**) with `Secret=oo7-portal;`, and drop it once Fedora's
niri carries the upstream line. S3 checks both the override and the no-override
case. Consider reporting the stale line against Fedora's niri package.

**Global shortcuts (the GlobalShortcuts portal).** State as of 2026-11-11:

- Not in any niri release. v26.04 (2026-04-25) is the latest; Fedora 45 has
  26.04-2 and no newer build.
- Merged to niri `main` on 2026-11-07 as
  [PR #4744](https://github.com/niri-wm/niri/pull/4744) (commit `b4789dd`),
  replacing the closed [#3587](https://github.com/niri-wm/niri/pull/3587) and
  following [#1165](https://github.com/YaLTeR/niri/pull/1165). niri implements
  part of the `org.gnome.Shell` accelerator API (grab and ungrab, tracked
  per D-Bus client); xdg-desktop-portal-gnome implements the portal itself.
  There is no niri config syntax: apps choose shortcut IDs, the user confirms
  the binding in a GNOME dialog, and niri forwards matching keys to the app.
- Requirements: a niri build that contains #4744; an
  xdg-desktop-portal-gnome that exports `GlobalShortcuts` (51.0-2 does, its
  `gnome.portal` lists the interface); xdg-desktop-portal 1.22.1 (needs at least
  1.21.1); and **`gnome-control-center`**. The niri wiki ("Important Software",
  commit 2026-11-07) says it is required, and xdg-desktop-portal-gnome's source
  confirms why: it calls `org.gnome.Settings.GlobalShortcutsProvider` for the
  bind dialog and fails to initialise without it. Fedora's
  `gnome-control-center` ships that D-Bus service. To edit shortcuts later, run
  `XDG_CURRENT_DESKTOP=gnome gnome-control-center`. (#4744's own description says
  the provider interface was dropped; the wiki and the portal source contradict
  that. The wiki and source are newer or more direct, so the plan follows them,
  but this is **unverified on a running system**.)
- Which niri to use is an open question (D14): wait for the next release
  (no date announced; **unverified** whether Fedora will build it for F45), or
  take a snapshot from COPR `yalter/niri-git` (at `0.0.git.3051.7f81a7f7`, a
  commit dated 2026-11-10 that contains #4744; **unverified** that the COPR
  works on the bootc build). The second adds a third-party COPR the plan wanted
  to avoid (R1), so the plan uses Fedora's niri (D14).
- **Everything else ships now** (owner decision: no follow-up work later).
  `gnome-control-center` is installed, xdg-desktop-portal-gnome (which carries
  the portal) is already in, and the `/etc` portals override keeps
  `default=gnome;gtk;` so `GlobalShortcuts` routes to the gnome backend. Fedora's
  niri floats with the daily rebuild, so the first niri update that contains
  #4744 turns global shortcuts on with no change to the repo. A content test
  prints whether the installed niri has the feature, so the moment is visible
  in CI.
- `gnome-control-center` installs a "Settings" launcher entry, and most of its
  panels do nothing outside GNOME Shell. The build marks
  `org.gnome.Settings.desktop` `NoDisplay=true` (a copy in
  `/usr/share/applications` written by the build script) so it doesn't show
  in the DMS launcher. It stays runnable for editing shortcuts.
- Test (S2): Discord (already installed) requests a shortcut, the GNOME
  dialog appears, the binding fires while another window is focused. Shortcuts
  don't fire on the lock screen; niri forwards the keys so a password can
  still be typed.

### 6.3 Polkit, notifications, lock and idle

DMS provides all four, so we install no separate polkit agent, mako or
swaylock. Set `DMS_PRIVESC=sudo`, so DMS privileged actions (the greeter
sync) prompt for sudo in a terminal. Zirconium's `run0` failed on the laptop
(2026-11-16): run0 execs the command directly as `unconfined_t`, and SELinux
denies `usermod` (`useradd_exec_t`) and `restorecon` (`setfiles_exec_t`) as
entrypoints for that domain, so the sync stopped with exit 203/EXEC.

### 6.4 Keyring and secrets (SPIKE S3)

Fedora 45 replaced gnome-keyring with **oo7** as the default Secret Service
([Change: oo7 Secrets Service Provider](https://fedoraproject.org/wiki/Changes/oo7_Secrets_Service_Provider),
accepted for F45; the Workstation ticket is
[workstation#506](https://forge.fedoraproject.org/workstation/tickets/issues/506)).
What F45 actually ships, checked with `dnf5 repoquery` and on the laptop:

- `oo7-daemon`, `oo7-portal` and `pam_oo7` at 0.7.0~beta^1.e91b98a. This is a
  beta snapshot, not a release.
- `xdg-desktop-portal-gnome` hard-requires `oo7-portal`, which requires
  `oo7-daemon`. So any image with the gnome portal has oo7.
- `gnome-keyring` 51.1 is still in the repos, and `gnome-keyring-pam` too, but
  the `gnome-desktop` and `workstation-product` comps groups no longer list
  it. `gdm` requires `pam_oo7`. Nothing on a GNOME-less image needs
  gnome-keyring.
- Fedora's PAM files already include `pam_oo7` next to the old modules, as
  optional lines with a leading `-` (skip if the module is missing). The
  `greetd` package's `/usr/lib/pam.d/greetd` has `-auth optional pam_oo7.so`
  and `-session optional pam_oo7.so auto_start`. The only PAM edit is the
  greetd auth source (5.2, D12): with `system-auth` a fingerprint login
  reaches `pam_oo7` with no password and the keyring stays locked.
  The pam_oo7 README says the auth stack captures the password and the session
  stack hands it to the daemon over `$XDG_RUNTIME_DIR/oo7/pam.sock` to unlock
  the default keyring.
- Existing data migrates automatically, per the Change page. On the laptop,
  `~/.local/share/keyrings` already holds `login.keyring.migrated` next to the
  new `v1` directory, so the migration has run.
- The laptop already runs it: no gnome-keyring installed, `oo7-daemon.service`
  active, `gcr-ssh-agent.socket` active, `SSH_AUTH_SOCK=/run/user/1000/gcr/ssh`.
  The laptop's `oo7-daemon.service` was enabled by hand
  (`~/.config/systemd/user/default.target.wants/`), because the packages ship
  no preset. The unit has `Type=dbus`, `BusName=org.freedesktop.secrets` and
  an alias `dbus-org.freedesktop.secrets.service`, but **no**
  `/usr/share/dbus-1/services/org.freedesktop.secrets.service` file.
  So whether D-Bus can start it on demand is **unverified**.
- SSH: the agent is `gcr-ssh-agent` (package `gcr`, 4.4.1), not oo7 or
  gnome-keyring (gnome-keyring's own SSH agent has been off by default since
  46). `gcr-ssh-agent.socket` has `WantedBy=sockets.target`, is not enabled by
  any preset, and on the laptop is only pulled in by `gvfs-daemon.service`.
  When it starts it runs `systemctl --user set-environment
  SSH_AUTH_SOCK=%t/gcr/ssh`. Whether oo7 stores the key passphrases that
  gcr-ssh-agent hands to the Secret Service is **unverified**; S3 tests
  `ssh-add` with a passphrase-protected key.

**Decision: oo7 owns the Secret Service; gnome-keyring is not installed.**
Installing both would give two claimants of `org.freedesktop.secrets`, which
is the problem the first draft's spike was built around. By not installing
gnome-keyring, that problem doesn't arise and no `/dev/null` mask or D-Bus
override is needed (the repo rules forbid the mask). The first draft preferred
gnome-keyring and said Zirconium ships the same set; the first half is
reversed by the F45 change, and Zirconium's `zirconium.conf` still lists
`gnome-keyring` and `gnome-keyring-pam` with presets enabling
`gnome-keyring-daemon` (found by code search; date of that config
**unverified**). It is no longer the model to follow for this part.

What the image needs:

- Packages: `oo7-daemon`, `oo7-portal`, `pam_oo7`, `gcr`, optional `oo7-cli`.
- User units, declared in a manifest and enabled globally: `gcr-ssh-agent.socket`
  always; `oo7-daemon.service` too unless S3 shows `pam_oo7`'s `auto_start`
  or D-Bus activation starts it reliably.
- The portal override in 6.2.
- `/etc/pam.d/greetd`: the package file with `auth substack password-auth`, so
  fingerprint never stands in for the password at login.

S3 must show, on a fresh user and on the migrated laptop: one process owns
`org.freedesktop.secrets` after a greetd login; the login keyring is unlocked
without a prompt; Zen, Discord, Obsidian, git (libsecret), NetworkManager
(Wi-Fi secrets) and `ssh-add` all work; a Flatpak app's Secret portal call
works with and without the 6.2 override; and kwallet (5.1) doesn't take the
name. Known risk: oo7 is a 0.7 beta. Bugzilla
[2560819](https://bugzilla.redhat.com/show_bug.cgi?id=2560819) reports that
`CreateItem(replace=true)` fails for Online Accounts items migrated from
gnome-keyring after an F44 to F45 upgrade (title only; status not read). Fallback
if S3 fails: install `gnome-keyring` and `gnome-keyring-pam` with
`gcr`, and leave `oo7-daemon` off, which means the user-level
`oo7-daemon.service` enablement must go and a drop-in must stop oo7 from
being activated. The gnome portal still drags `oo7-daemon` in, so that path
brings the dual-owner problem back.

### 6.5 Input method

ibus with mozc (replacing today's anthy; the user re-adds Mozc once in ibus preferences after migrating). niri implements text-input-v3 and input-method-v2. GTK apps
need no `GTK_IM_MODULE`. Qt apps and XWayland get `QT_IM_MODULE` and
`XMODIFIERS` from `/usr/lib/environment.d/`. Japanese input must be tested
in GTK, Qt, Electron and Flatpak apps.

### 6.6 Theming

DMS and matugen generate colours at runtime into user files. The image ships:

- adw-gtk3 as the default theme, set in `/etc/gtk-3.0` and `/etc/gtk-4.0` (GTK
  doesn't read `/usr/share`)
- the gschema override
- `QT_QPA_PLATFORMTHEME=qt6ct` via environment.d
- a qt6ct seed in `/etc/xdg/qt6ct`

qt6ct copies its seed into the user's config only once, so seed changes never
reach existing users. Flatpak theming uses static override files under
`/var/lib/flatpak/overrides`, copied by a tmpfiles `C` rule and never
overwriting user changes. This replaces today's boot-time
`flatpak-theming.service`.

### 6.7 If DMS is replaced later

DMS may be replaced later by a custom shell (owner, 2026-11-14; not soon).
Nothing is restructured for that now: DMS packages stay in the desktop
manifest with niri, as today. One cheap rule keeps a later swap easy: the
`neptuno` command, update notices (section 10), the power profile switch and
the wrapper talk to standard interfaces (`notify-send` /
`org.freedesktop.Notifications`, `org.freedesktop.UPower.PowerProfiles`,
logind), never `dms ipc`.

**What any replacement shell must provide**, because DMS covers it today and
nothing else in the image does:

| Role | Today (DMS) | Interface the image relies on |
|---|---|---|
| Bar, launcher, tray | DMS | StatusNotifierItem, `.desktop` files |
| Notifications | DMS | `org.freedesktop.Notifications` |
| Polkit agent | DMS | polkit agent registration (6.3) |
| Lock screen and idle | DMS | `ext-session-lock-v1`, `ext-idle-notify-v1`, logind lock/suspend signals (6.3, 17) |
| Power profile switch | DMS | `org.freedesktop.UPower.PowerProfiles` (tuned-ppd) |
| OSD, brightness, volume keys | DMS | brightnessctl, PipeWire/WirePlumber |
| Wallpaper and dynamic colours | DMS + matugen | matugen templates for GTK, Qt and ghostty (6.6) |
| Greeter | dux-greeter | greetd (any greetd greeter works) |
| File search | dux-search (`dsearch`) | none; launcher-specific |

A future shell spike would check that table row by row.

## 7. Software model: one obvious place per kind

| Kind of software | Where it comes from | Command |
|---|---|---|
| System, desktop, drivers, dev libs | The image | Edit a manifest, then PR |
| GUI apps | Flathub | `flatpak install`, or Bazaar if wanted |
| CLI tools | Nix | `nx add ripgrep` (name TBD, D8) |
| Language toolchains | mise | `mise use -g rust@latest` |
| Anything needing dnf, GUI dev stacks | distrobox | `neptuno devbox`, then `distrobox-export` |

### 7.1 Nix (SPIKE S1, highest risk)

Fedora 45 packages Nix 2.35.4 as `nix-core`, `nix-system` and `nix-daemon`.
`nix-system` owns `/nix` and the `nixbld` sysusers, and `nix-core` ships a
working `/etc/nix/nix.conf` (flakes and nix-command on, auto-optimise on) and
fish, bash and zsh profile scripts. In a container, the daemon path installed
and ran `nixpkgs#hello` from the binary cache.

The problem is that on bootc `/nix` comes from the image and is immutable at
runtime.

**Plan A, the daemon with a bind mount.**
- The image keeps `nix-system`'s empty `/nix`.
- A shipped `nix.mount` bind-mounts `/var/lib/nix` onto `/nix` before
  `nix-daemon.service`.
- The mount hides the RPM's payload, so tmpfiles must recreate everything
  under the mount:
  - `/nix/store` as `1775 root:nixbld`
  - `/nix/var/nix/{db,gcroots,profiles,temproots,daemon-socket}`
- Ordering: `nix.mount` is in `local-fs.target`, with
  `RequiresMountsFor=/var`. It is ordered before `systemd-tmpfiles-setup` so
  the directories land inside the mount.
- **SELinux labelling** is an explicit S1 deliverable. By default the store
  would be labelled `var_lib_t`. Either that works for an unconfined user
  and an unconfined daemon, or we ship a file-context equivalence
  (`/var/lib/nix` = `/nix`). If S1 needs custom policy beyond that, take
  Plan B immediately rather than maintaining SELinux policy.
- Enable `nix-daemon.service`, not the socket: Red Hat bug 2525943 reports
  the socket fails under SELinux, with no file-context rule yet and a policy
  PR open.
- The Determinate installer's ostree planner uses the same bind-mount idea,
  so the design has precedent, but it is untested on bootc.

**Plan B, rootless `nix-core`.** This needs no `/nix` at all. The store lives
in `~/.local/share/nix/root`. It needs `HOME` to be the resolved
`/var/home/<user>`, because Nix rejects the `/home` symlink. Verified in a
container. It is simpler, but per-user only and slightly slower.

Shared pieces either way:
- `/usr/lib/environment.d/60-nix.conf` adds the profile's `share` dir to
  `XDG_DATA_DIRS` and its `bin` dir to `PATH`. That way Nix-installed
  `.desktop` files show in the DMS launcher, and keybinds or user units can
  run Nix tools. The shell scripts alone don't reach the compositor.
- **One nixpkgs revision for everything.** An unpinned `nixpkgs#` resolves a
  new revision on every `nx add` and duplicates dependency trees, so the
  user registry is pinned. `nx upgrade`, and the weekly timer that calls
  it, runs `nix registry pin nixpkgs` (re-pinned to current
  nixpkgs-unstable) and then `nix profile upgrade --all`. `nx add` uses
  the pinned revision. The timer has `ConditionACPower=true`.
- `nix-shell` isn't in `nix-core`. The wrapper uses `nix shell`. Add
  `nix-legacy` only if `nix-shell -p` turns out to be missed.

The wrapper is a bash script in `/usr/bin` with no state of its own. On a
terminal, `nx upgrade` prints the nixpkgs move and one line per package that
changed (`↑ neovim 0.12.5 → 0.12.6`, `+` added, `-` removed), and `nx list`
prints name and version columns. Colour is off for pipes, the timer's journal
and `NO_COLOR`.

```
nx add <name>...       -> nix profile add nixpkgs#<name>...
nx remove <name>...    -> nix profile remove <name>...
nx list                -> nix profile list (name and version columns)
nx search <term>       -> nix search nixpkgs <term>
nx upgrade             -> nix registry pin nixpkgs && nix profile upgrade --all
nx rollback            -> nix profile rollback
nx try <name> -- cmd   -> nix shell nixpkgs#<name> -c cmd
nx clean               -> nix profile wipe-history --older-than 14d && nix store gc
```

It refuses to run as root and maps common brew-style names to nixpkgs
attributes: `yq` becomes `yq-go`, `ykman` becomes `yubikey-manager`,
`openjdk@17` becomes `openjdk17`, `bats-core` becomes `bats`. Neither existing
"zix" is worth adopting: Zena's is a flake-manifest tool with no search.

**Brew to Nix mapping.** 63 of the 64 formulae installed on request exist in
nixpkgs. Not everything moves there, though:
- **Become RPMs instead:** docker-engine, gcc, openssl, fontconfig,
  smartmontools, squashfs, tcpdump, ykman, zenity.
- **Covered by podman instead of brew:** docker, docker-compose, buildx,
  rootlesskit and slirp4netns (see D4).
- **Stays under mise:** mise itself, which can come from Nix or upstream.

### 7.2 Flatpak

- **Flathub:** shipped as `/etc/flatpak/remotes.d/flathub.flatpakrepo`.
  flatpak imports it the first time the system installation is opened.
- **Preinstall:** `flatpak preinstall -y` (flatpak ≥1.17) reads
  `/usr/share/flatpak/preinstall.d/neptuno.preinstall`. Fedora ships no unit
  for this, so we ship `neptuno-flatpak-preinstall.service`.
  - It runs after `network-online.target`. Wi-Fi often isn't up yet at first
    boot, so it retries (`Restart=on-failure`, plus a timer re-run).
    **Amended 2026-11-14:** it must not be wanted by `multi-user.target`, or it
    delays `graphical.target` (the laptop measures 6.3 s for today's unit). A
    timer (`OnBootSec=2min`) activates it instead (17.3).
  - A stamp keyed on a hash of `preinstall.d` is written only on success, so
    additions to the list still apply on later boots.
  - flatpak tracks its own preinstall state. Before trimming the list (D9),
    verify whether it uninstalls apps that are dropped from the list.
- **App list:** today's 26-app list is re-audited against what is actually
  used. About 90 Flatpaks are installed on the laptop today, 52 of them apps
  (`flatpak list --app`; the rest are runtimes and extensions). The GNOME apps
  listed as Flatpak in 5.5 go in the preinstall list; the four GNOME RPMs do not.

## 8. Configuration model

The rule: image defaults live under `/usr`, the user owns `~/.config`, and
user files include the image defaults where the tool supports it. Improved
defaults then reach the existing account. `/etc/skel` carries only thin
stubs that point at `/usr` (section 6.1), never full copies that go stale.

| Tool | How defaults reach the user |
|---|---|
| niri | `~/.config/niri/config.kdl` starts with `include "/usr/share/neptuno/niri/base.kdl"`, then personal overrides, then DMS's `include optional=true "dms/*.kdl"` lines, always last. The DMS lines stay in the user file because DMS's repair greps it and otherwise appends duplicates. Includes are positional and supported since 25.11. The seeded file also carries a commented-out copy of `base.kdl` (rendered at build time by `build/scripts/render-niri-skel`, so it always matches), which the user uncomments to change a default. |
| ghostty | `config-file = ?/usr/share/neptuno/ghostty/base.conf`, with overrides in a second, later `config-file`. An included file beats the including file's own keys. The matugen theme stays in `~/.config/ghostty/themes`. |
| fish | `/usr/share/fish/vendor_conf.d/zz-neptuno.fish` loads automatically, after `nix.fish` (the name orders it). It sets up starship, zoxide, atuin and eza aliases, each guarded by `command -q`, which replaces "bling". |
| Session env | `/usr/lib/environment.d/90-neptuno.conf`. User files with the same name win. |
| systemd user units | `/usr/lib/systemd/user/` |
| mimeapps | `/usr/share/applications/mimeapps.list` (distro defaults per the XDG spec) |
| Default terminal | `/usr/share/xdg-terminal-exec/xdg-terminals.list` → ghostty |
| git | `/etc/gitconfig` for system defaults (RPM git now that brew is gone) |
| ssh | `/etc/ssh/ssh_config.d/50-neptuno.conf` |
| GTK | `/etc/gtk-{3,4}.0/settings.ini` |
| qt6ct | `/etc/xdg/qt6ct/qt6ct.conf`, seeded once |
| starship, atuin | No layering. Ship `STARSHIP_CONFIG=/usr/share/neptuno/starship.toml` only if the user has no own file. |
| DMS settings, `niri/dms/*.kdl` | User-owned, never in `/usr`. **Seeded once** in `/etc/skel` from the owner's cleaned config (2026-11-14): `dms/settings.json` and every `niri/dms/*.kdl` the niri stub includes. DMS does not reliably create these files itself, and a missing one silently drops its settings, so a test fails if an include has no seeded file. The owner's window rules (DMS windows float and stay opaque; tiled windows open maximized with square corners, floating windows keep DMS's rounding) live at the end of the user's `config.kdl`, after the DMS includes, not in `dms/windowrules.kdl`, which a new DMS install rewrites. They must follow `dms/layout.kdl`, which rounds every window, because in niri the later rule wins. |
| matugen output | User-owned, never shipped |

Never write to `/usr/etc`, which `bootc container lint` treats as fatal. Use
`/etc` only where a tool reads nothing else, and remember a local edit there
pins the file against future image changes.

`neptuno config diff` shows how the user's thin files differ from the image's
reference templates. It replaces `ujust install-config`.

## 9. Services

Enablement stays declarative: every enabled or disabled unit is named in a
manifest, and `90-cleanup.sh` fails the build on anything else.

- **Enable (system):** greetd, NetworkManager, systemd-resolved, firewalld,
  bluetooth, tuned, tuned-ppd, upower, cups.socket + cups.path, avahi-daemon
  (for printer discovery; D2), fstrim.timer, fwupd-refresh.timer, tailscaled,
  nix-daemon (Plan A), nix.mount, bootc-fetch-apply-updates.timer (with the
  drop-in), neptuno-flatpak-preinstall, neptuno-flatpak-update.timer,
  and `bootloader-update.service` (kept from the base preset and declared,
  so the shim on the EFI partition stays current for Secure Boot).
- **Enable (user, global):**
  - podman.socket, which rootless docker-compose needs
  - gcr-ssh-agent.socket (not enabled by any preset)
  - oo7-daemon.service (pending S3; see 6.4)
  - udiskie
  - neptuno-update-notify.path
  - neptuno-nix-upgrade.timer (weekly)
  - neptuno-nix-clean.timer (weekly)
- **Wanted by niri.service:** dms.service, dsearch.service.
- **Disable:** see section 4 and 17.3. sshd stays disabled by default (D2).
- **Timers added by section 17:** `neptuno-flatpak-preinstall.timer` (2 minutes
  after boot) and `neptuno-appstream-refresh.timer` (weekly, AC only). Updates
  and Nix jobs get `Nice=19`, `IOSchedulingClass=idle`, `CPUWeight=20`
  drop-ins.
- **Not shipped, by decision:** TLP, auto-cpufreq, power-profiles-daemon,
  ananicy-cpp, preload, irqbalance. `tuned` with `tuned-ppd` is the only
  power policy daemon. The image is general purpose for Intel and AMD (not
  NVIDIA), so the base's Intel units stay enabled: thermald, intel_lpmd and
  mcelog exit or skip themselves cleanly on AMD (checked on the laptop,
  2026-11-15).

First-boot setup is one small `neptuno-setup` script, about 30 lines and
idempotent, version-stamped in `/var/lib/neptuno`. It replaces
`ublue-system-setup` and `ublue-user-setup`.

Users and groups come from `sysusers.d`. The nss-altfiles trap is narrower
than "everything": `usermod -aG` silently fails only for groups defined in
`/usr/lib/group`, such as `input`. Those groups need the uaccess udev rule or
a sysusers `m` line instead.

## 10. Updates and rollback

| What | Mechanism |
|---|---|
| OS image | `bootc-fetch-apply-updates.timer`, which ships disabled, so we enable it. A drop-in clears `ExecStart=` and runs `bootc upgrade --quiet`. The drop-in is image-owned, in `/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/`, not `/etc`. Upstream's `--apply` reboots; ours only stages. The staged deployment is finalised at the next shutdown, whenever the user chooses. |
| Reboot prompt | A user `.path` unit watches `/run/ostree/staged-deployment`. `bootc status` needs root, so the user session can't poll it. To avoid a daily nag from daily builds, it notifies only when the booted image is more than 7 days older than the staged one, or when the staged build lists a security update. |
| Stale-update warning | If no update has been staged successfully for 14 days, which happens when the daily build has been red, a notification says so. The laptop must never go stale silently. |
| Flatpaks | A system timer runs `flatpak update -y --noninteractive` daily with a randomized delay, only on AC power (`ConditionACPower=true`). |
| Nix | A weekly user timer runs `nx upgrade`. A weekly clean timer drops generations older than 14 days and garbage-collects. |
| mise, firmware | Manual (`mise up`, `fwupdmgr update`), plus `fwupd-refresh.timer` for metadata |
| Everything at once, on demand | `topgrade` (from COPR `lilay/topgrade`), seeded with the owner's config in `/etc/skel/.config/topgrade.toml` (`[linux] bootc = true`). It runs `sudo /usr/bin/bootc upgrade`, which `/etc/sudoers.d/neptuno-bootc` allows for `%wheel` without a password (that exact command only; `switch` and `rollback` still ask). Its built-in `nix` step is disabled: it runs `nix profile upgrade --all` against nx's pinned nixpkgs, so it never moves anything. A `[commands]` entry runs `nx upgrade` instead. Flatpak updates go through polkit. There is no `neptuno update`. |
| Rollback | `bootc rollback`. Dated tags (`:45.YYYYMMDD`) let `bootc switch` reach any of the last 30 builds. `ostree admin pin` keeps a known-good deployment. |

## 11. Signing and trust

The model doesn't change from today: keyless signing, enforced in CI.

- **Signing:** keyless cosign through GitHub OIDC (Fulcio certificate, Rekor
  entry). The job needs `id-token: write`, and there are no keys to generate,
  store, rotate or back up. `build.yml` signs the post-chunkah digest only
  after the content tests and the boot test pass, using plain
  `sigstore/cosign-installer` plus `cosign sign --yes <ref>@<digest>`, with no
  `projectbluefin/actions`. A signing failure fails the run, so `:latest` never
  moves to an unsigned digest. This is stricter than today, where signing is
  `continue-on-error`.
- **The gate:** before `build.yml` moves `:latest` and the dated tag, it runs
  `cosign verify` on the digest with the exact
  `--certificate-identity https://github.com/${GITHUB_REPOSITORY}/.github/workflows/build.yml@refs/heads/main`
  and `--certificate-oidc-issuer https://token.actions.githubusercontent.com`.
  The certificate keeps the owner's capitalisation (`Siddhj2206`), so
  `neptuno verify`, which only has the lowercase image name, matches the same
  identity case-insensitively.
  That pins the exact workflow file and branch, which is tighter than today's
  "any workflow in the repo" regexp. A tag only ever points at a digest that
  passed this.
- **The laptop doesn't verify.** `00-image-info.sh` keeps writing
  `ostree-unverified-image:docker://…`, and the image ships no custom
  `policy.json` or `registries.d` entry. Fedora's defaults stay as they are.
  This is a known limit, not an oversight: containers/image's `fulcio` rule
  (skopeo 1.24, containers-common 0.69 on F45) matches `subjectEmail` only,
  and a GitHub Actions certificate names its workflow in a URI SAN. So the
  trust boundary is "the registry only serves what CI verified", and an
  attacker with GHCR push access could still serve an unsigned image.
- **Manual check:** `neptuno verify` runs the same `cosign verify` against
  the booted or staged digest. It reads the digest from `bootc status --json`
  and runs cosign from its pinned container image, so cosign isn't added to
  the image. The README documents the command.
- **Revisit when** containers/image gains URI or workflow identity matching
  for Fulcio (there's a standing FIXME in `signature/fulcio_cert.go`). Then
  ship a `sigstoreSigned` scope with Fulcio's CA and Rekor's key under `/usr`
  and switch the transport to `ostree-image-signed:`. Key-based signing was
  considered and rejected: the owner prefers zero key management over device
  enforcement.
- **Provenance:** not attached for now. `actions/attest` with
  `push-to-registry` adds a second referrer that Aurora reports confuses
  `cosign verify`; revisit once the cosign v3 flow has run in CI.
- **Third-party repos:** Tailscale and the COPRs are installed with
  `gpgcheck=1`, and nothing anywhere sets `gpgcheck=0`.

## 12. Build, CI and release

**Build:** a single `Containerfile`.
- One `ctx` scratch stage holds `build/` and `system_files/`.
- `FROM base-atomic:45@sha256:…`, then one `RUN` per phase with dnf and
  rpm-ostree cache mounts.
- It ends with `bootc container lint --fatal-warnings`.
- The image is then rechunked with **chunkah** (`quay.io/coreos/chunkah`
  v0.7.1, pinned by digest) by `just rechunk`, locally and in CI alike:
  `podman run --mount=type=image` over the built image, `--max-layers 96
  --prune /sysroot/`, the ostree labels dropped, output as an OCI directory
  and pulled back into the same rootless storage, then `bootc container lint
  --fatal-warnings`. Verified 2026-11-15: 96 layers, largest 270 MB, lint
  clean, no root storage or copy needed. chunkah replaced the earlier
  `rpm-ostree compose build-chunked-oci` recipe (same result, but it needed
  root storage and a 7 GB copy). Rechunking is required in practice: the ISO
  installer stages each layer in RAM, and an un-rechunked 2 GB layer failed
  the install with ENOSPC.
- Rechunking is part of the pipeline from the **first** M1 build. It changes
  layers, xattrs and the digest, so lint, content tests, the boot test and
  signing all run on the post-chunkah digest. Nothing is validated before
  rechunking and then shipped after it.

**Workflows:** plain GitHub Actions on `ubuntu-26.04` (free and unlimited for
public repositories; Podman 5.7, Skopeo and Docker preinstalled), with no
`projectbluefin/actions`. Implemented 2026-11-15; `.agents/skills/ci` is the
working reference.

| Workflow | What it does |
|---|---|
| `build.yml` | Pull requests, pushes to `main`, a daily 05:17 UTC cron and dispatch, in one file. `static` (shellcheck, `just check`, bats, Flathub IDs, hadolint, actionlint, zizmor, the Renovate validator) runs in parallel with `build` (`just build`, `just rechunk`, `just test-image`, `just test-boot`). Docs-only pull requests skip the image build. On `main`, `build` pushes by digest to `:candidate`; `publish` signs keyless, `cosign verify`s against the exact workflow identity (section 11) and copies the digest to `:45.YYYYMMDD` and `:latest`; `release` writes a GitHub release with the package diff since the previous one. A red run, or a failed sign or verify, never moves `:latest`. A single `required` job is the status a ruleset requires. |
| `clean.yml` | Weekly. `dataaxiom/ghcr-cleanup-action` keeps the newest 30 dated tags; deletes untagged digests older than 14 days and orphaned signature artifacts (GHCR has no referrers API, so cosign v3 stores them as `sha256-*` tags). `stable`/`stable-testing` are excluded until cutover. Releases are pruned to 30. Dispatch defaults to a dry run. |
| ISO | Not in CI yet (owner decision, 2026-11-15): `just build-iso` is local. osbuild's mounts failed inside podman on the Ubuntu runner; the attempts are in `.agents/skills/ci`. |
| Renovate | The hosted Mend app, no workflow. `config:best-practices` plus semantic commits, weekly. Non-majors automerge through platform automerge behind `required`, which really builds and boots the image. Base-image digests skip the schedule; Fedora majors are disabled; actions wait 3 days and only `actions/*` and `sigstore/*` automerge. |

The daily cron is not skipped when nothing changed: Fedora updates land almost
daily, so the check would rarely save a build.

**Boot test in CI:** `bcvk ephemeral run-ssh` boots the image's own kernel
over virtiofs with no disk image, and passes when `systemctl
is-system-running --wait` reports `running`. Standard runners on public
repositories expose `/dev/kvm` (enabled with a udev rule, as bcvk's own CI
does); without it the step warns and runs under TCG.

The full VM suite stays local (`just test-vm`).

## 13. Testing

1. **Static:** shellcheck, hadolint, `just --fmt --check`, bats contract tests
   for the manifest engine and unit audit. These are kept and pruned.
2. **Image content (CI, no VM):** run the built image and check that
   - every manifest package is installed (`rpm -q`)
   - the enabled-unit set equals the declared set
   - `systemd-analyze verify` passes on our units
   - `niri validate -c /usr/share/neptuno/niri/base.kdl` passes
   - no custom `policy.json` or `registries.d` scope is shipped (the keyless model needs neither)
   - no repo is left enabled
   - `bootc container lint` passes.
3. **VM boot (local, KVM):** QEMU runs rootless in a podman container (proven
   in the sysext experiment) and boots a qcow2 built with a test user. It
   asserts that
   - `systemctl is-system-running` reports running
   - `systemctl --failed` is empty
   - greetd is active
   - `nx add hello` works (S1)
   - `bootc status` shows the `ostree-unverified-image` reference to `neptuno`.
4. **Upgrade and rollback (local, before cutover and on bootc-touching changes):**
   install build N-1, `bootc upgrade` to N, reboot, `bootc rollback`.
5. **Migration (S0, local, before cutover):** this exercises the real event,
   not a fresh install.
   - Install today's `neptuno:stable` (the Silverblue-based image) in the VM
     and create a user.
   - Add the kind of state the laptop has: an edited `/etc`, a GDM display
     manager, a stale brew unit.
   - `bootc switch` to the new image and run the S2 and S3 checks.
   - `bootc rollback` and confirm the old desktop still works.
6. **Secure Boot:** the same VM with `OVMF_CODE.secboot.fd` and Microsoft keys
   enrolled, including a run after a dbx update, which proves
   `bootloader-update` keeps the shim bootable.
7. **Power and boot (added 2026-11-14):** image-content checks, KVM-only boot
   time assertions and an on-laptop checklist for idle power, s2idle and the
   charge limit. The assertions and thresholds are listed in 17.5, and the
   targets they enforce are in 17.2. Idle power can't be measured in a VM, so
   it lives only on the laptop checklist.

## 14. Installation media

- **Primary path, no ISO needed:** an existing Fedora Atomic or Neptuno
  machine runs `bootc switch ghcr.io/siddhj2206/neptuno:latest`.
- **VM images:** qcow2 via image-builder for testing.
- **ISO, phase 2:** the existing `anaconda-iso` type is legacy and fails on
  Fedora 45 (osbuild/image-builder#2704, open). The maintained replacement is
  `generic-iso`. `just build-iso` builds an offline, installer-only ISO:
  `iso/installer/Containerfile` is a small Anaconda environment from
  `fedora-bootc:45` (not a live Neptuno session), and image-builder's
  `--bootc-installer-payload-ref` embeds Neptuno once, in the installer's
  containers-storage. The kickstart installs from
  `containers-storage:ghcr.io/siddhj2206/neptuno:latest` with the registry
  ref as the update target, so nothing is pulled at install time and the
  image is on the ISO exactly once. Anaconda's own user screen creates the
  first user. We build it locally on demand. It won't be distributed. The image is 3.6 GiB
  compressed, so the ISO exceeds GitHub's 2 GiB release-asset limit, and
  Cloudflare R2 is the option if hosting is ever wanted. **SPIKE S5:** a
  generic-iso install including first-user creation, since there is no
  gnome-initial-setup.
- **Retire** the stale `feat/live-iso` and `wip/live-iso` branches. The first
  has unrelated history and points at a non-existent `:stable-daily` tag; the
  second is a separate tacklebox pipeline.

## 15. What we take from Bluefin and Universal Blue

| Item | Action |
|---|---|
| `ujust` | Rewrite as `/usr/bin/neptuno` (3 lines) plus `/usr/share/neptuno/justfile` with recipes `setup`, `info`, `devbox`, `config-diff`, `refresh-config <app|all>` (puts a seeded `/etc/skel` config back after renaming yours to `.bak-<time>`), `changelog` and `dev-groups` |
| ublue-system-setup, ublue-user-setup, hook runner | Rewrite as `neptuno-setup` (section 9) |
| Flatpak preinstall unit | Keep the idea and rewrite the unit with a stamp |
| Container policy and keys | Drop. Fedora's defaults stay, and signing is keyless and checked in CI (section 11). |
| bling | Rewrite as a fish `vendor_conf.d` file |
| image-info, os-release | Rewrite. Keep `ID=fedora` and `ID_LIKE` for dnf, toolbox and fwupd compatibility. Set `NAME`, `PRETTY_NAME` and `VARIANT_ID=neptuno`, plus `IMAGE_*` fields. |
| fastfetch config | Rewrite as one file |
| changelog recipe | Rewrite as `neptuno changelog`, which diffs `rpm -qa` between deployments |
| countme, bonedigger, motd, Bazaar config, branding art, dconf db, ASUS and Framework hooks, flatpark remote, uupd, brew | Drop |

From Zirconium, which independently arrived at niri + DMS on Fedora with no
ublue runtime dependency, we take:
- the greeter config shape,
- the preinstall unit pattern,
- the idea of shipping the login-screen config in the image.

We no longer take Zirconium's keyring set: its `zirconium.conf` lists
gnome-keyring and gnome-keyring-pam (checked by code search; **unverified**
whether it has moved to oo7). Fedora 45 itself has moved, and 6.4 follows
Fedora. For portals we take only the xdg-desktop-portal-gnome + gtk pairing,
which both images share.

## 16. Migrating the laptop

1. **Before switching:**
   - Back up with Déjà Dup.
   - Run `flatpak list --app > apps.txt`, `brew list --installed-on-request > brew.txt` and `mise ls`.
   - Have the user run `sudo ostree admin config-diff`, then **act on it**.
     Revert local edits to files the new image now owns: anything under `/etc/gdm`, PAM and authselect edits, stale `.wants`
     links for brew and uupd units.
   - Pin the current deployment with `sudo ostree admin pin 0`.
2. **First pass S0** (migration in a VM), from `neptuno-testing`.
3. **Switch:** `sudo bootc switch ghcr.io/siddhj2206/neptuno-testing:latest`,
   then reboot. GDM is replaced by greetd, and the old deployment stays
   pinned for rollback.
4. **Adopt the configs:** make `~/.config/niri/config.kdl` and the ghostty
   config thin (section 8), and keep the DMS files as they are.
5. **Shell cleanup:** remove the brew `shellenv`, the `PKG_CONFIG_PATH` hack,
   the brew fish `vendor_conf.d` loop and the brew starship path from
   `config.fish`.
6. **Replace brew:** reinstall the CLI set with `nx add …` from the mapping
   table. Move docker to podman with a user socket and `DOCKER_HOST`.
   asusctl comes with the image (D5). After a week without regressions, delete
   `/home/linuxbrew` to free 9.1 GB.
7. **Keyring:** nothing to migrate by hand. The laptop already runs oo7 and
   its `~/.local/share/keyrings` already holds the migrated keyring. The
   user-level `oo7-daemon.service` enablement under `~/.config/systemd/user`
   is harmless once the image enables the unit globally; remove the user copy
   after S3 so only one place enables it. If S3 falls back to gnome-keyring,
   the existing keyring files still work (the oo7 migration keeps
   `login.keyring.migrated`, and oo7's `v1` directory is separate).
8. **Move to the main repo:** after about a week on `neptuno-testing`, push
   `rebuild` to `neptuno` as `next`, merge, then run
   `bootc switch ghcr.io/siddhj2206/neptuno:latest`.
   Keep the old `:stable` tag until the new image has been stable for a
   month. Then unpin the old deployment
   (`sudo ostree admin pin --unpin <n>`).
9. **Reinstall path with no ISO** (documented in the troubleshooting skill):
   - Install the stock Fedora Atomic ISO, for example Sway Atomic, or any
     Fedora 45 Atomic image.
   - Run `bootc switch ghcr.io/siddhj2206/neptuno:latest`.
   - Restore the home directory from the Déjà Dup backup.

## 17. Power, boot and responsiveness

Added 2026-11-14. The owner's goal is "a seamless, light(?) friendly desktop
OS", with good power management and fast boots, and Pond by Butterfly is the
reference. This section records what was measured on the laptop, what Pond
does, and the mechanisms Neptuno uses. The rule throughout: **keep Fedora and
upstream defaults, and change a default only where a measurement or a named
failure justifies it.** One power daemon owns policy (tuned, through
`tuned-ppd`). No TLP, no auto-cpufreq, no power-profiles-daemon.

### 17.1 Measured baseline

Taken on 2026-11-14 from the running laptop (read-only commands; the laptop
runs today's Silverblue-based image, `ghcr.io/siddhj2206/neptuno:testing`,
45.20261114, kernel 7.3.3-300.fc45, BIOS `UM3402YAR.306`). It is **one boot**
on a machine that had been up 12 hours, so treat every number as approximate.

**Boot (`systemd-analyze`): 44.1 s total.**

| Phase | Time |
|---|---|
| Firmware | 3.9 s |
| Loader (GRUB) | 4.2 s |
| Kernel | 0.8 s |
| initrd | 5.9 s (`dracut-initqueue` 3.9 s of it) |
| Userspace to `graphical.target` | 29.3 s |

Firmware plus loader is 8.1 s, which Neptuno's image can't change except by
what lands in `/boot` (17.4). Userspace is two thirds of the total, and almost
all of it is avoidable. The critical chain to `graphical.target` is:
`NetworkManager-wait-online` (4.2 s) → `network-online.target` →
`flatpak-appstream-refresh.service` (16.5 s) → `graphical.target`.

`systemd-analyze blame`, excluding `.device` and `.mount` units (device units
show when the device appeared, not a cost):

| Unit | Time | Fate in the new image |
|---|---|---|
| `flatpak-appstream-refresh.service` | 16.5 s | Off the boot path (17.3) |
| `fedora-atomic-desktop-appstream-cache-refresh.service` | 12.7 s | Also enabled in `base-atomic`; disabled in removals.toml (the weekly timer replaces it) |
| `plymouth-quit-wait.service` | 11.2 s | Waited for GDM; see 17.3 on greetd |
| `brew-update`, `brew-upgrade`, `brew-preinstall` (user) | 7.9 + 5.4 s, 12.5 s | Gone with brew |
| `flatpak-preinstall.service` | 6.3 s | Moves to a timer (17.3) |
| `tuned.service` | 5.8 s | Stays; off the critical path. Measure again (S6) |
| `fwupd-refresh.service` | 4.7 s | Stays; timer, off the critical path |
| `NetworkManager-wait-online.service` | 4.2 s | Not enabled (17.3) |
| `dracut-initqueue.service` (initrd) | 3.9 s | See 17.4 |
| `asusd.service` | 3.4 s | Stays (D5). Off the critical chain; S6 checks its 1 s `ExecStartPre` sleep doesn't hold up the greeter. |
| `bootloader-update.service` | 3.3 s | Stays (Secure Boot shim) |
| `uresourced.service` | 3.1 s | Stays (17.3) |
| `dms.service` (user) | 8.9 s | **Unexplained.** Measure on the new image (S6) |

Boot-time warnings (`journalctl -b -p warning`): `systemd-remount-fs.service`
fails three times (`mount` exit 32) and is the only failed unit;
about 60 udev lines of "Failed to resolve group `plugdev` / `nintendo_switch`"
from rule files (`50-zsa.rules`, `70-u2f.rules`, `10-switch.rules`) that are
**not owned by any RPM**, so they come from files the old image shipped by
hand and the rebuild drops them; `input-remapper-control autoload` fails for
12 input devices at boot; `asusd-user` dumped core; the kernel logs
`asus_armoury: No matching power limits found for this system`, `i2c-9
Failed`, and a failed ACPI `USBC000:00` platform device (all cosmetic as far
as seen). The journal on disk is **1.7 GB**.

**Power and sleep.**

| Item | Measured |
|---|---|
| CPU driver | `amd-pstate-epp`, status `active`, governor `powersave` (the only choices are `performance` and `powersave`) |
| EPP | `power`, set by the active tuned profile. Available: `default performance balance_performance balance_power power` |
| Boost | Off (`cpufreq/boost` reads 1 but `scaling_max_freq` is 2.0 GHz), because the active profile is `powersave`, whose `tuned.conf` has `boost=0` |
| tuned | Active profile `powersave`, **manual** mode. `tuned-ppd` is installed; `/etc/tuned/ppd.conf` is stock (default `balanced`, `battery_detection=true`, power-saver=`powersave`, balanced=`balanced` on AC and `balanced-battery` on battery, performance=`throughput-performance`) |
| ACPI platform profile | `quiet` (set by tuned's `powersave`); choices `quiet balanced performance` |
| Sleep | `/sys/power/mem_sleep` is `[s2idle]` only. The kernel says `ACPI: PM: (supports S0 S4 S5)` and `Low-power S0 idle used by default`, so there is no S3 on this machine |
| NVMe | `nvme 0000:03:00.0: platform quirk: setting simple suspend` (kernel). Scheduler `none`. `default_ps_max_latency_us` 100000 (stock). APST state **not read** (`nvme-cli` absent) |
| PCIe ASPM | policy `[default]` (firmware's choice), even under the `powersave` profile |
| Wi-Fi | MT7922, `iw` reports power save on |
| Audio | `snd_hda_intel` `power_save=10` |
| amdgpu | `abmlevel=-1`, `power_dpm_force_performance_level=auto`. The `panel_power_savings` sysfs file that tuned writes does not exist, so that line of the profile has no effect here (**unverified** why; the panel may be OLED, which has no backlight to save) |
| zram | `zram0`, 8 GiB, `lzo-rle`, 948 MiB stored in 386 MiB (2.5:1). Swappiness 60, `page-cluster` 3 (kernel defaults, wrong for zram) |
| Memory now | 15 GiB, 9.6 GiB used, 1.5 GiB swapped, with the Zen browser, Electron apps and the shell open. `qs` (the shell) holds 385 MiB RSS |
| Journal | 1.7 GB on disk, no size limit set |
| Battery | `BATT`, **1024 cycles, 43.8 Wh full vs 75.1 Wh design (58 %)**. Plugged in at 100 % |
| Charge limit | `charge_control_end_threshold` exists (ASUS WMI) and reads **100**, no start threshold file. `upower -d` reports start 75 / end 80 and `charge-threshold-supported: yes`. These disagree, and the reason is **unverified** (asusd or UPower state) |

**Not measurable from this session:** idle power draw (the laptop is on AC,
`energy-rate` 0 W), s2idle drain and hardware sleep residency (`amd_pmc` debugfs
needs root), resume time, and Wi-Fi or NVMe link states under load. Those are
the on-laptop checklist in 17.5.

**`base-atomic:45` defaults** (read by running the image): it enables
`thermald`, `intel_lpmd`, `mcelog`, `mdmonitor`, `ModemManager`, `sssd`,
`systemd-homed`, `flatpak-add-fedora-repos`, `NetworkManager-wait-online`,
`systemd-oomd`, `uresourced`, `auditd`, `chronyd`, `dnf-makecache.timer`,
`raid-check.timer`, `rpm-ostree-countme.timer`, `unbound-anchor.timer`,
`fstrim.timer` and `lvm2-monitor`. Its preset file also enables `tuned`,
`tuned-ppd`, `power-profiles-daemon`, `irqbalance` and `ksmtuned`, but only
the packages that are installed matter, and `base-atomic` installs none of the
four. It ships `zram-generator-defaults` (size `min(ram, 8192)`),
`systemd-oomd-defaults`, plymouth and kernel 7.3.3, and **no**
`/usr/lib/bootc/kargs.d`. Section 4's disable list is extended below.

### 17.2 Targets

Targets are for this hardware and are goals, not guarantees. Anything marked
"to be set" needs a first measurement on the rebuilt image before a number is
fixed.

| Metric | Today | Target | Basis |
|---|---|---|---|
| Userspace to `graphical.target` | 29.3 s | **at most 8 s** on the laptop, at most 12 s in the KVM VM | The measured chain is dominated by two avoidable units (17.1). What remains is stock Fedora plus greetd. **Unverified** until S6. |
| Total power button to greeter | 44.1 s | about 20 s | firmware 3.9 + loader at most 1 + kernel 0.8 + initrd at most 5 + userspace at most 8 |
| Loader time | 4.2 s | at most 1 s | GRUB menu timeout is machine-local (17.4) |
| Login to a usable shell (`dms.service` active, bar drawn) | `dms.service` 8.9 s | at most 3 s | **Unverified.** The cause of 8.9 s is unknown. |
| Idle power on battery (balanced-battery, brightness about 40 %, Wi-Fi up, shell idle) | not measured | **at most 7 W**, to be set after the first measurement | Typical for a 15 W Zen 3 U-series laptop. **Unverified** for this unit. |
| s2idle drain | not measured | **at most 0.7 W (about 1.5 % per hour of this battery)**, and hardware sleep residency above 90 % | **Unverified.** The AMD PMC may not report residency on this APU. |
| Resume | not measured | lid open to a locked screen accepting input in at most 2 s | |
| Suspend reliability | not measured | 20 of 20 lid-close cycles resume with the shell locked | S2 and S6 |
| Failed units and boot warnings from our own units | 1 failed unit, about 80 warnings | `systemctl --failed` empty; no `plugdev` or `remount-fs` lines | |
| Journal size | 1.7 GB | at most 300 MB | 17.3 |
| Battery limit | 100 % | 80 % by default (D17) | 17.3 |

On this aged battery (58 % of design) battery-life targets in hours would be
misleading; judge power in watts.

### 17.3 Mechanisms

Everything is declared in the manifests and shipped under `/usr`, per sections
8 and 9. Nothing here needs a daemon beyond what the plan already has.

**Power policy: stock `tuned` + `tuned-ppd`.** The shipped profile mapping is
already what we would write: power-saver sets EPP `power`, boost off, platform
profile `low-power|quiet`; balanced on AC sets EPP `balance_performance`;
balanced on battery (`balanced-battery`) sets `balance_power` and
`panel_power_savings=1`; performance sets governor `performance`, EPP
`performance`, `min_perf_pct=100` and platform profile `performance`. All of
them keep `audio timeout=10` and `alpm=med_power_with_dipm`. So **ship no
custom tuned profile and no `ppd.conf`**. Two things to watch:

- `throughput-performance` (the PPD "performance" profile) sets
  `vm.swappiness=10` and `dirty_bytes=40%`, which fights zram. Acceptable
  while performance is a rare, deliberate choice. If it isn't, add a
  `/usr/lib/tuned/profiles/neptuno-performance` that includes it and resets
  swappiness, and map it in `/etc/tuned/ppd.conf`.
- The `powersave` profile disables boost. Fine for the power-saver pill, but
  it's why this laptop is capped at 2.0 GHz today. The default after install is
  `balanced` (boost on).

Do not add `amd_pstate=` kernel arguments: `active` is already what the kernel
chose, and `mem_sleep_default=s2idle` is the only option anyway.

**Kernel arguments:** `/usr/lib/bootc/kargs.d/10-neptuno.toml` with
`kargs = ["quiet"]`. It matters only for a fresh install (the laptop already
has `rhgb quiet`); keeping `rhgb` is the installer's business. No other
argument is adopted. Deferred until measured, each with its trigger:

| Argument | Trigger |
|---|---|
| `pcie_aspm.policy=powersupersave` (or a tuned `[sysfs]` drop-in) | S6 shows package C-state or s2idle residency is held back by the NVMe or Wi-Fi link and L1 substates are off. ASPM is firmware-default today. |
| `amdgpu.dcdebugmask=0x10` (disable PSR) | Visible freezes or flicker on the panel after resume. Not applied pre-emptively. |
| `mt7921e` ASPM off | Wi-Fi drops after resume. Not applied pre-emptively. |

**Boot path: take work off the critical path.** These are the changes that
account for most of the 29.3 s.

| Change | Where | Why |
|---|---|---|
| Disable `NetworkManager-wait-online.service` (add to the manifest's `disabled` list) | manifest | 4.2 s on the critical chain. Nothing in the plan needs the network up before the greeter. Units that need it order themselves after `network-online.target`, which then reaches quickly. |
| Run `flatpak preinstall` from a timer, not from `multi-user.target` | `neptuno-flatpak-preinstall.timer` (`OnBootSec=2min`, retry on failure) replaces the `WantedBy=` on the service | A oneshot wanted by `multi-user.target` and ordered after `network-online.target` delays `graphical.target` (6.3 s today). This amends 7.2, which says only "runs after `network-online.target`". |
| Do not enable `flatpak-appstream-refresh.service` at boot | disabled; a weekly timer `neptuno-appstream-refresh.timer` (AC only, `Nice=19`) | 16.5 s on the critical chain. Appstream metadata only matters when the owner opens an app store; Bazaar is optional and refreshes itself. |
| Disable `dnf-makecache.timer`, `raid-check.timer`, `rpm-ostree-countme.timer`, `unbound-anchor.timer`, `mdmonitor`, `lvm2-monitor` (already in 4), `fedora-third-party-refresh` (already in 4) | manifest `disabled` list | No dnf on the host, no RAID, no countme; each is wakeups or work with no benefit on this laptop. |
| Keep `auditd`, `chronyd`, `systemd-oomd`, `uresourced`, `bluetooth`, `rtkit-daemon` | unchanged | Fedora defaults with a purpose. `uresourced` and `systemd-oomd` are the responsiveness mechanism (below). **Unverified:** that `uresourced` earns its 3.1 s; measure with it masked off the path in S6 (as a test only, no mask ships). |
| Background jobs run low priority | drop-ins on `bootc-fetch-apply-updates.service`, `neptuno-flatpak-update.service`, `neptuno-nix-upgrade.service`, `neptuno-backup.service` | `Nice=19`, `IOSchedulingClass=idle`, `CPUWeight=20`. Flatpak, Nix and backup keep `ConditionACPower=true`; bootc's download does not, because a stale laptop is worse (section 10). |

**Plymouth.** Keep it (D18). `base-atomic` ships it, the firmware logo then
carries through to the greeter, and it costs under a second. The risk is
greetd: GDM was a plymouth-aware display manager, and the measured
`plymouth-quit-wait` (11.2 s) is only its wait for GDM. S2 and S6 must show
that plymouth quits cleanly when greetd takes VT1, with no leftover splash or
VT flash. If greetd's unit doesn't order itself after plymouth, ship a
`greetd.service.d/10-plymouth.conf` drop-in with `After=plymouth-quit.service
plymouth-quit-wait.service` (**unverified** that this is needed; read the
packaged unit in S6).

**Memory and swap (zram).** Keep `zram-generator-defaults` (8 GiB, `lzo-rle`,
2.5:1 measured). Adopt two Pond/CachyOS-style sysctl values, in
`/usr/lib/sysctl.d/70-neptuno.conf`: `vm.swappiness=100` and
`vm.page-cluster=0`. With compressed RAM as the only swap, swapping is cheaper
than dropping file cache, and `page-cluster=3` makes the kernel read eight
pages for every swap fault, which is waste on zram. Not adopted from Pond's set:
`dirty_ratio=10` and `dirty_background_ratio=3` (the NVMe doesn't need them),
`vfs_cache_pressure=50`, `sysrq=1`, `nmi_watchdog=0` (already 0 here). Keep
zstd as an option only if swap use climbs; `lzo-rle` is lower CPU.
`systemd-oomd` and `systemd-oomd-defaults` stay as Fedora ships them.

**Journald.** `/usr/lib/systemd/journald.conf.d/50-neptuno.conf`:
`SystemMaxUse=300M`, `SystemMaxFileSize=32M`, `MaxRetentionSec=1month`.
Justification: 1.7 GB on disk today with no cap, and a month of history is
enough for debugging.

**udev and group warnings.** Ship `plugdev` and `nintendo_switch` as groups in
`sysusers.d` only if the new image still ships rules that name them
(the old rule files are not RPM-owned and are not carried over); otherwise the
warnings are gone. A bats test asserts that `systemd-udevd` logs no "Failed to
resolve group" for the shipped rules (17.5).

**Battery charge limit (D17, decided: set in DMS).** The image ships no
charge limit, no udev rule and no helper. The owner sets it in DMS's battery
settings. Two things can write `charge_control_end_threshold`: DMS (through
UPower's `EnableChargeThreshold`, **unverified** which path DMS uses) and
asusd, which stores its own limit and reapplies it at start. S6 checks that
the DMS value survives a reboot with asusd running; if asusd overwrites it,
the limit is set once with `asusctl -c` instead and DMS's toggle is left
alone (R16). Today sysfs reads 100 while UPower reports 80, which is this
same conflict.

**s2idle.** It's the only sleep state, so reliability is the whole job.
Mechanisms: logind and DMS defaults for lid close; DMS locks on
`PrepareForSleep` (S2 verifies); `ConditionACPower` jobs don't run in sleep;
no `mem_sleep_default` argument. Diagnose with AMD's `amd-debug-tools` /
`amd-s2idle` (**unverified** that Fedora 45 packages it; it is also on PyPI)
and `/sys/power/suspend_stats`. Known workaround to hold in reserve, not to
apply: if the NVMe or Wi-Fi blocks deep idle, test `pcie_aspm` and `mt7921e`
settings (table above) one at a time. 

**Hibernate (D19, revised 2026-11-14: leave as is).** Hibernate already works
on today's laptop, so the image ships no swap file, swap unit, `sleep.conf.d`
or `logind.conf.d` change for it. Lid close keeps logind's default. If the new
image ever stops hibernating, compare against the old deployment before adding
anything.

**Wi-Fi, audio, iGPU, disk.** All stock. Wi-Fi power save is already on in
the driver; PipeWire and the HDA driver power-save by default (`power_save=10`,
tuned's `audio timeout=10`). amdgpu has no module options. NVMe gets no udev
scheduler rule (Pond/CachyOS set `kyber`; the kernel default `none` is correct
for NVMe). `fstrim.timer` weekly stays.

**DMS idle, lock and suspend timing (D20, decided: set in DMS).** The image
ships no idle values. DMS keeps all its settings in a file in the user's home
(`~/.config/DankMaterialShell/settings.json`) that DMS itself rewrites, so the
image can't own it without overwriting the owner's changes (section 8). The
owner sets screen-off, lock and suspend times in DMS's settings once; they
carry over from today's laptop. Lid close suspends through logind's default.

**Display.** The panel is a 14-inch 90 Hz display (**unverified** that it is
OLED; `abmlevel` and the missing `panel_power_savings` suggest it may be).
Lowering the refresh rate to 60 Hz on battery is an evaluation item, not a
default: niri has no automatic per-power-state mode switch, and DMS may or may
not expose one (**unverified**).

### 17.4 Outside the image

`bootc` owns `/usr` and `/etc`, not the machine. These affect the 8.1 s of
firmware and loader time and are the owner's to change once:

- **BIOS:** look for "Fast Boot" and disable unused boot devices (**unverified**
  that this BIOS offers them).
- **GRUB menu (D21, decided: Fedora's default).** On Fedora Atomic the menu
  comes from bootupd's static config, which sets `timeout_style=menu` and
  `timeout=1` (read from `base-atomic:45`'s
  `/usr/lib/bootupd/grub2-static/grub-static-pre.cfg`). So the menu shows for
  one second on every boot and older deployments stay one keypress away. The
  plan doesn't change it. Fedora Workstation's hidden menu (`menu_auto_hide`)
  is a non-ostree feature that the static config doesn't use. Today's 4.2 s
  loader time is more than that 1 s; S6 checks whether the laptop's
  `/boot` still has an older config from the original Silverblue install.
- **initrd (5.9 s):** `dracut-initqueue` is 3.9 s. `base-atomic` ships a
  generic initramfs. A trimmed one needs a dracut step in the build (omit
  nfs, iscsi, multipath, mdraid, lvm where unused), which regenerates
  `/usr/lib/modules/*/initramfs.img` and makes the image diverge from the
  base. Don't do it unless S7 shows more than 1.5 s of gain. The 9 s device
  waits in `blame` are not the cause.

### 17.5 Tests

Added to section 13:

- **Image content (CI, no VM):**
  - the enabled-unit set excludes `NetworkManager-wait-online.service`,
    `flatpak-appstream-refresh.service`, and the timers listed in 17.3
  - `/usr/lib/bootc/kargs.d/10-neptuno.toml`, `70-neptuno.conf` and
    `50-neptuno.conf` (journald) parse and pass `systemd-analyze verify` /
    `sysctl --system` in a container
  - no unit in `multi-user.target.wants` orders itself `After=network-online.target`
    (the preinstall service is timer-activated)
  - `tuned-adm`'s profile list contains `balanced-battery` and `/etc/tuned/ppd.conf`
    is not overridden (so we notice if Fedora changes the mapping)
  - `tuned-ppd` is installed and `power-profiles-daemon`, `tlp`, `auto-cpufreq`
    are not
- **VM boot (KVM only; skipped under TCG):**
  - `systemd-analyze` userspace time is at most 12 s
  - `systemd-analyze critical-chain graphical.target` contains none of
    `flatpak-*`, `NetworkManager-wait-online`, `brew-*`, and no unit on it takes
    more than 3 s
  - `systemctl --failed` is empty and `journalctl -b -p warning` has no "Failed
    to resolve group" or `systemd-remount-fs` lines
  - `powerprofilesctl`-compatible API works: `gdbus call` on
    `org.freedesktop.UPower.PowerProfiles` lists `power-saver`, `balanced`,
    `performance`, and setting each one changes `cpufreq/*/energy_performance_preference`
    in the guest where the guest exposes it (**unverified** under QEMU; skip if not)
  - `journalctl --disk-usage` stays below 300 MB after a 2-hour soak
  - idle power cannot be measured in a VM; don't assert it there.
- **On-laptop checklist (before each cutover step and after any `tuned`,
  kernel or DMS update that changes behaviour):**
  1. `systemd-analyze` and `critical-chain` against the 17.2 targets.
  2. On battery, balanced-battery, 40 % brightness, 5 minutes idle: average
     `current_now * voltage_now` from `/sys/class/power_supply/BATT/` (or
     `upower -d` `energy-rate`) is at most 7 W; repeat with `powertop`
     closed. Record the number in this section.
  3. Each of the three profiles in DMS: EPP, boost and platform profile change
     as 17.3 says (`cat` the three sysfs files).
  4. 20 lid-close cycles on battery: the shell is locked on resume every time,
     Wi-Fi reconnects, Bluetooth audio returns, resume to input is at most 2 s.
  5. One overnight suspend on battery: drain at most 1.5 %/h, and `amd-s2idle`
     (or `/sys/power/suspend_stats` plus the PMC debugfs as root) shows the
     system reached the lowest S0ix state.
  6. Charge limit: the chosen threshold holds after a reboot, a suspend and a
     `bootc upgrade`.
  7. Plymouth hands over to the greeter without a flash or a stuck splash.
  8. `journalctl -b -p warning` has no unit failures from Neptuno's own
     services.

### 17.6 Lessons from Pond

Pond is Butterfly Interaction's Arch-based distribution built on niri,
opened to the public on 2026-10-27 as an early preview. This section is from
its public GitHub organisation
([`bflycomputer`](https://github.com/bflycomputer)) and two reviews
([Starry Hope](https://www.starryhope.com/linux/pond-linux-first-look/),
[It's FOSS](https://itsfoss.com/pond-early-preview/)). `butterfly.so` itself
returned only its title when fetched (it renders client-side), so its install
and docs pages were **not read**. The reviews don't cover power, battery or
boot time; the facts below about power come from the package repository.

**What Pond ships.**

- **Shell:** a Quickshell sidebar down the left edge acts as bar, with clock
  and calendar, a minimap (a row per workspace, an icon per window, drag between
  rows), notifications and install progress, media, keyboard and brightness
  cards, network, sound, Settings. The source is
  [`pond-interface`](https://github.com/bflycomputer/pond-interface)
  (`shell/`, `lockscreen/`, `plymouth/`, `grub/`, `wallpaper/`, niri `config/`
  split into `cfg/*.kdl`).
- **Launcher:** a fork of Vicinae
  ([`vicinae`](https://github.com/bflycomputer/vicinae)), opened with Super+Space,
  with an "Install:" prefix and a clipboard history on Super+V.
- **Greeter:** SDDM with a custom greeter that runs in its own niri session.
- **Boot:** GRUB with a themed menu and Plymouth. Secure Boot must be off. No
  disk encryption. Snapper with `snap-pac` (timeline off, `/home`, Flatpak and
  Nix excluded).
- **Kernel:** `linux-pond` and `linux-pond-lts`, a CachyOS-patched kernel
  (sched, `zen4` ISA options, `swappiness=100`, watermark and compaction tweaks).
  In
  [`pond-pkgbuilds`](https://github.com/bflycomputer/pond-pkgbuilds).
- **Power and tuning:** `pond-system-optimizations` is CachyOS-Settings
  repackaged. Its PKGBUILD depends on `zram-generator`, `ananicy-cpp`,
  `ananicy-rules`, `iw` and `wireless-regdb`, and its install script enables
  `ananicy-cpp`, `systemd-resolved` and `systemd-oomd`. The same repo carries
  `power-profiles-daemon` with a patch that switches `sched_ext` (`scx_loader`)
  modes with the profile, and `intel-lpmd`. The shell's Settings has a
  three-profile pill (power-saver, balanced, performance). **Unverified:**
  whether the sysctl values below match the pinned CachyOS-Settings tag Pond
  packages; they were read from that project's main branch.
- **First boot and onboarding:** a five-screen installer (language and
  timezone, drive, disk use, profile, progress). A manual opens once on first
  login and lists the key bindings; it is reachable again from Settings or the
  launcher.
- **Updates:** the shell runs a `pm -a` check at login and every 12 hours.
  Settings then shows an "Update available" button, shown only when more than
  three pacman updates are pending, which runs `pm -u` across pacman, AUR and
  Flatpak. It recommends a restart after kernel or driver updates.
  [`package-manager`](https://github.com/bflycomputer/package-manager) is a
  Rust tool with a catalogue of about 4,100 apps, mostly Flatpak.
- **Does not ship:** a web browser, a text editor, Secure Boot support, manual
  partitioning, a way to remove apps from the manager.

| Pond idea | Verdict | Reason |
|---|---|---|
| Custom CachyOS-style kernel (`linux-pond`) | **Rejected** | Section 1 non-goal and the Secure Boot rule: Fedora's signed kernel only. Its win is scheduler and tuning patches Fedora's 7.3 kernel mostly doesn't need on a 6-core U-series laptop. |
| `zram` swap, with `swappiness=100` and `page-cluster=0` | **Adopted** (17.3) | Zero-cost, measured need: swappiness 60 and page-cluster 3 here. |
| `systemd-oomd` | **Adopted** (already in `base-atomic`) | Same daemon, already enabled. |
| Power-profile pill with three profiles | **Adopted** | DMS already shows it through the UPower PowerProfiles API that `tuned-ppd` provides. |
| `ananicy-cpp` + `ananicy-rules` (process priority daemon) | **Rejected for now** | An extra daemon that rescans processes and adds wakeups; EEVDF, `uresourced` and `systemd-oomd` already cover the interactive case. Revisit only if S6 shows UI jank under a compile (decision D19). **Unverified** that Fedora packages `ananicy-cpp`. |
| `power-profiles-daemon` + `scx_loader` | **Rejected** | Two reasons: `tuned-ppd` is the Fedora choice and the plan's (5.2); `sched_ext` schedulers need a kernel and userspace we would be the only users of. |
| `intel-lpmd` | **Rejected** | Intel hybrid CPUs only. Disabled in 4. |
| Wi-Fi regulatory service (`iw-set-regdomain`) | **Rejected** | Fedora ships `wireless-regdb`, and NetworkManager sets the domain from the Wi-Fi settings (**unverified** on this router). Revisit if 5 GHz channels are missing. |
| Udev I/O scheduler rules (`kyber` for NVMe) | **Rejected** | `none` is the right NVMe choice. |
| Snapper with snap-pac | **Adapted** | `bootc rollback` and ostree deployments already give system rollback; `/var`, which holds home, isn't covered. Home is backed up by hand with Déjà Dup (D13). |
| Greeter in its own niri session | **Adapted** | `dux-greeter` runs on `greetd` and is the same idea with DMS's own greeter. |
| Plymouth theme, GRUB theme | **Adopted only as far as Plymouth** | Keep Plymouth for the firmware-logo continuity (D18). A GRUB theme is machine-local (17.4) and not worth it. |
| First-run manual that lists key bindings | **Adapted** | `neptuno-setup` opens a one-page cheat sheet once (`/usr/share/neptuno/keys.md`, opened in Text Editor or a DMS notification). DMS has its own help panel; check it first (**unverified**). |
| Background update check, one "Update available" button, restart advice | **Adapted** | Section 10 already does this with `bootc` staging plus a notification. Borrow Pond's thresholds: don't nag for fewer than 3 changes; restart advice only for kernel, systemd, DMS or niri changes (a package-set diff, not just a digest change). |
| One app catalogue that hides the source | **Adapted** | Section 7: one obvious place per kind of software. Bazaar (optional) is the store for Flatpaks. No custom manager. |
| Snapshot entries in the boot menu | **Rejected** | The deployments are the entries. |
| Secure Boot off, no disk encryption | **Rejected** | Neptuno works with Secure Boot on (section 2). |
| 12-hour update check at login | **Adapted** | `bootc-fetch-apply-updates.timer`, with `Persistent=true` so a missed run happens at the next boot (a proposed
  addition to section 10). |

What makes Pond feel finished is mostly the shell and first-run, not
power tuning, which is mostly CachyOS defaults. Neptuno gets the same shell
class from DMS. The power half of "seamless" is nearly all in `tuned-ppd`, which
`base-atomic` already provides.

---

## 18. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | DMS, quickshell, ghostty, matugen and the greeter all come from one org's COPRs (`duxlabs`). Upstream was just renamed and packages are split across COPRs. | **Float the versions; don't pin.** COPR prunes superseded builds after about 14 days by default, so pinned versions would break the build after every upstream release. The CI boot test is the gate: a broken COPR build fails the daily run, and `:latest` isn't touched. Every build records the exact package versions in its image labels and changelog. Escape hatch: rebuild the SRPMs in our own `neptuno-rpms` COPR. |
| R2 | Nix on bootc with SELinux enforcing is unproven (S1) | Plan B (rootless) is verified. Decide after the spike. |
| R3 | greetd, dux-greeter and oo7 PAM unlock (S2, S3). `pam_oo7` is already in greetd's PAM file; the open part is whether the daemon starts and unlocks under greetd. | VM spike before building the session |
| R4 | oo7 is a 0.7 beta snapshot and the Secret Service depends on it. No gnome-keyring means no dual-owner conflict, but also no old, proven daemon behind it. | S3 covers the apps that matter. Fallback in 6.4. Never mask with `/dev/null`. |
| R12 | Niri's stock `niri-portals.conf` in F45 still names gnome-keyring for Secret, and global shortcuts are not in any niri release (6.2) | `/etc` override until Fedora's niri catches up. The global-shortcut pieces ship now, so a Fedora niri update enables the feature without repo changes (D14). |
| R5 | The laptop never checks signatures, so a compromised GHCR token or a bad push bypasses the CI gate | `packages: write` only in `build.yml`, with third-party actions pinned by SHA and never automerged. `neptuno verify` is available for a manual check. Revisit device enforcement when containers/image can match a Fulcio URI identity. |
| R6 | cosign changes its signature format or its keyless defaults (bundle format, Rekor v2) and breaks the gate | Pin `cosign-installer` and the cosign version through Renovate, which never automerges them. `cosign verify` in the same run catches a mismatch before tagging. |
| R7 | Daily unattended builds publish a broken `:latest` | Content tests plus the CI boot smoke test gate the tag. Updates only stage, dated tags enable rollback, and the stale-update warning covers a long red streak. |
| R10 | The migrated laptop differs from a fresh VM: years of `/etc` and `/var` state | S0 migration test, and acting on `config-diff` before switching |
| R11 | No way back if the shell or greeter breaks | VT2 getty, the GRUB deployment menu, the pinned old deployment, and the documented reinstall path |
| R8 | The ISO path on Fedora 45 is in flux (S5) | `bootc switch` is the primary install path, so the ISO is optional |
| R9 | Base presets re-enable units in a future base (e.g. new Intel daemons) | The unit audit fails the build on any undeclared enablement |
| R13 | s2idle on this APU is the only suspend state and may drain the battery or fail to resume (no S3 fallback) | S6 measures residency, drain and 20 resume cycles before cutover. Reserve workarounds in 17.3 (ASPM, PSR, Wi-Fi). Decision D19 if drain is above 2 % per hour. |
| R14 | The measured boot and power targets are unproven (one baseline sample, and no battery measurement because the laptop is on AC and the battery is at 58 % of design) | Targets are marked **unverified** in 17.2. S6 sets final numbers after the first rebuilt-image measurement; the VM test uses loose thresholds. |
| R15 | greetd and plymouth hand-over, and removing `NetworkManager-wait-online`, may leave a splash on screen or start a unit before the network is ready | S2 and S6 check the hand-over. Units that need the network order themselves after `network-online.target` (17.3). |
| R16 | DMS (through UPower) and asusd both write the battery charge threshold; sysfs reads 100 while UPower reports 80 today | S6 checks the DMS value survives a reboot with asusd running. If not, set it with `asusctl -c` and leave DMS's toggle alone. |

## 19. Spikes: prove these before building

| Spike | Question | Pass condition |
|---|---|---|
| S0 | Migration from today's Silverblue-based `neptuno:stable` (section 13.5) | After `bootc switch`, S2 and S3 pass on the migrated machine, and `bootc rollback` restores the old desktop |
| S1 | Nix daemon with `/var/lib/nix` bind-mounted on `/nix`, SELinux enforcing. Time-box it to one day. | `nx add ripgrep` works for the user. It survives reboot, `bootc upgrade` and `bootc rollback`. A user systemd service can run a profile binary, and there are no AVC denials. If it needs custom SELinux policy, switch to Plan B. |
| S2 | greetd plus dux-greeter on base-atomic | Everything listed in 6.1: login, fresh-user first boot, suspend and resume to a locked screen, DMS restarting, VT2 recovery, IME. Also: `quickshell-git` gives DMS polkit and idle. The hidden Settings entry stays out of the launcher. Once a niri with #4744 arrives, Discord's global shortcut works (6.2). |
| S3 | oo7 as the Secret Service (no gnome-keyring) | After a greetd login the only owner of `org.freedesktop.secrets` is `oo7-daemon`, started without a manual enable or with the global enable from 6.4. The login keyring is unlocked by `pam_oo7`, with no prompt. `ssh-add` works through `gcr-ssh-agent`, including a passphrase-protected key. Zen, Discord, Obsidian, git (libsecret) and a Flatpak app's Secret portal call work, with and without the `/etc/xdg-desktop-portal/niri-portals.conf` override. kwallet doesn't take the name. Repeat on the migrated laptop data (S0). |
| S4 | Keyless gate in CI (on `neptuno-testing`) | `build.yml` signs, and `cosign verify` with the pinned workflow identity passes. A digest signed by another workflow or branch fails the verify and doesn't get tagged. `neptuno verify` passes on the booted VM. |
| S5 | `generic-iso` install | Installs to a blank VM disk, the first user is created, and the result boots into S2. **2026-11-15, first run:** the ISO is 3.8 GB. The install worked with the VM's network unplugged and reached the DMS greeter. Three problems turned up. (1) An un-rechunked 2 GB layer ran out of space in the installer's RAM `/var/tmp`. Fixed with a tmpfs `/var/tmp` plus rechunking. (2) Anaconda's `bootc` payload created the user but not the home directory. Fixed with `neptuno-ensure-homes.service`. (3) The same payload lost the chosen timezone. The same payload also lost the hostname. `ostreecontainer --transport=containers-storage` was tried in place of `bootc` and failed after deploying: its `systemd-tmpfiles --root` step exits 73 on the composefs root. The ISO therefore keeps the `bootc` kickstart, and the timezone and hostname are set after install. That gap is acceptable because the ISO isn't the primary install path. |
| S6 | Power, boot and sleep on the laptop (section 17). Run on the laptop during the first days on `neptuno-testing`. | Userspace to `graphical.target` at most 8 s and no flatpak, wait-online or brew unit on the critical chain; `dms.service` start time explained and at most 3 s; plymouth hands over to greetd cleanly (and the packaged `greetd.service` ordering is read); the three tuned-ppd profiles change EPP, boost and platform profile as 17.3 says; idle power on battery recorded (target at most 7 W); s2idle drain and PMC residency recorded (target at most 0.7 W) with 20 clean lid cycles; the charge limit has one owner and survives reboot; `amd-s2idle` availability checked; DMS idle keys and whether it reads system defaults answered. Any failed row feeds a decision (D18 to D21). |
| S7 | initrd trim (optional, only after S6) | A dracut omit list saves more than 1.5 s of initrd time on the laptop, and keeps the `resume` module. If not, drop the idea. |

S0 to S3 block the MVP. S6 blocks M4 (they need the laptop on the new image), and S7 blocks nothing. S4 blocks M2, and S5 blocks nothing. Rechunking with chunkah is no longer a
separate spike: it's in the pipeline from the first build (section 12), so
every test runs on the rechunked image. The delta size is measured
informally in M2.

## 20. Milestones

1. **M0, spikes** (VM, local): S1 to S3, each with a short write-up in the
   owning skill.
2. **M1, image MVP on `neptuno-testing`:** Containerfile with chunkah,
   manifests, system_files, wrapper, updates, signing. `just build` and
   `just test-vm` both pass on the rechunked image.
3. **M2, CI and release:** S4, then build (with the boot smoke test and the keyless verify gating
   `:latest`), PR, Renovate and clean workflows. Check whether KVM is
   available on runners. The daily cron is green for 3 days.
4. **M3, cutover:** S0 passes in a VM. Then the laptop switches to
   `neptuno-testing` and runs a week without regressions. S6 (power and boot)
   runs on the laptop in the first days of that week and must pass before M4.
5. **M4, merge home:** `rebuild` becomes `neptuno:next`, then a PR into
   `main`, then the switch to `neptuno:latest`. AGENTS.md, skills
   and README are rewritten in the same PR.
6. **M5, later:** generic-iso (S5), CI boot test on a larger runner, an
   optional `neptuno-rpms` COPR.

## 21. Decisions only the owner can make

| # | Question | Recommendation |
|---|---|---|
| D1 | Monorepo or a shared repo, and its name | **Decided:** monorepo. Not "Terra". |
| D2 | sshd, printing (cups and avahi), scanning | **Decided:** sshd off. cups socket-activated and avahi on, so a printer just works when one shows up; `cups-browsed` off. No extra sane packages beyond the base. |
| D3 | Japanese input and CJK fonts | **Decided:** switch to `ibus-mozc` and remove `ibus-anthy`; keep the Noto Sans CJK fonts (5.1, 5.4). |
| D4 | Docker | **Decided:** rootless podman, `podman-docker` and `docker-compose`. Not moby-engine. |
| D5 | asusctl on the Zenbook | **Decided:** keep, from COPR `lukenukem/asus-linux` as an image RPM (5.2). Nix can't provide the system daemon. |
| D6 | Compositor-tier devel libs in the image (about 300 MiB) | **Decided:** not in the image; use the devbox distrobox. |
| D7 | Nix Plan A (daemon) or B (rootless) | **Decided:** Plan A. Fedora 44 added Nix officially ([Changes/Nix_package_tool](https://fedoraproject.org/wiki/Changes/Nix_package_tool), FESCo-approved): F45 ships `nix`, `nix-core`, `nix-daemon`, `nix-system` and `nix-filesystem` 2.35.4, with `nix-daemon.service`/`.socket`, sysusers and tmpfiles. The change page calls `/nix` incompatible with rpm-ostree and says bootc bind-mount support is still being worked on; no `.mount` unit ships, so our `/var/lib/nix` bind mount (7.x) is still ours to write. S1 still runs; Plan B stays the documented fallback if S1 fails. |
| D8 | Wrapper name | **Decided:** `nx`. |
| D9 | Flatpak app list | Re-audit the 26 listed today against the 52 apps installed, starting from the GNOME set in 5.5. **Decided:** Resources (Flatpak) instead of System Monitor; Text Editor stays an RPM. |
| D10 | ISO at all | **Decided:** phase 2, built locally, not distributed. |
| D11 | Artifact Hub listing, issue templates, CONTRIBUTING | **Decided:** drop. |
| D12 | Fingerprint reader | **Decided:** yes. `fprintd` + `fprintd-pam`, authselect `with-fingerprint` (5.2). |
| D13 | Backups | **Decided:** no default backup job. The owner backs up with Déjà Dup (Flatpak, 5.5) when wanted. No restic timer or package. |
| D14 | Niri global shortcuts | **Decided:** install the supporting pieces now (`gnome-control-center`, portal routing) and keep Fedora's niri. Shortcuts turn on with the first Fedora niri update that has #4744 (6.2). |
| D15 | quickshell: stable 0.3.2 or `quickshell-git` | **Decided:** `quickshell-git`. |
| D16 | Drop the packages listed in 5.7 | **Decided:** drop them, except input-remapper, firewall-config, khal, the VPN plugins and FUSE 2, which stay (5.2). |
| D17 | Battery charge limit | **Decided:** set by the owner in DMS; the image ships none (17.3). |
| D18 | Keep plymouth? | **Decided:** keep. |
| D19 | Hibernate | **Decided (revised):** no image changes; it already works on the laptop (17.3). UI jank: no `ananicy-cpp` unless S6 shows jank; systemd-oomd stays. |
| D20 | DMS idle, lock and suspend timing | **Decided:** set by the owner in DMS; the image ships none (17.3). |
| D21 | GRUB menu timeout | **Decided:** keep Fedora Atomic's default, a 1 s menu (17.4). |
