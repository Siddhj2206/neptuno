# niri + DankMaterialShell (DMS) package research for pluto (Fedora 43 bootc)

**Date:** 2026-08-28 · **Base:** Fedora Hummingbird `bootc-os:latest` (minimal F43 server) · **Target:** usable niri desktop with DMS shell + greetd login, installed via dnf5 at image build time.

**Sources examined (cloned/local):**
- `AvengeMedia/DankMaterialShell` → `/tmp/opencode/dms` (README, AGENTS.md, dms.spec, dms-git.spec, dms.service unit, quickshell/ QML tree, core/)
- `AvengeMedia/dank-greeter` → `/tmp/opencode/niri-refs/dank-greeter` (README.md — contains the greetd config verbatim)
- `tuna-os/tunaOS` → `/tmp/opencode/niri-refs/tunaOS` (manifests/desktops/niri.yaml, build_scripts/desktop/niri.sh, install-desktop.sh, verify-branding-niri.sh, verify-desktop-experience.sh, flatpak scripts)
- `gabeklavans/bazzite-niri` → `/tmp/opencode/niri-refs/bazzite-niri` (bonus)
- Web: niri wiki Getting-Started + Important-Software, danklinux.com docs (installation, compositors), packages.fedoraproject.org (niri, quickshell, cliphist, ghostty)
- **Live measurement:** `dnf5 repoquery --repofrompath` against Fedora 43 release+updates repos and the three AvengeMedia COPR chroots (`fedora-43-x86_64`) — all F43 availability claims below are measured, not assumed.

---

## 1. What DMS actually is

**DankMaterialShell is a complete desktop shell for Wayland compositors built with Quickshell (Qt6/QML) + a Go backend daemon/CLI (`dms`).** It is **NOT** GTK4/Libadwaita — it is a Qt6/Quickshell application (this contradicts the "GTK4/Libadwaita? Rust?" hypothesis in the task; it's neither).

From the README: *"It replaces waybar, swaylock, swayidle, mako, fuzzel, polkit, and everything else you'd normally stitch together to make a desktop."* — i.e. DMS provides its own: bars (DankBar/TopBar/Dock), launcher (Spotlight), notifications, lock screen, idle detection, control center (network/bluetooth/audio/display), clipboard history, screenshot, settings UI, and a polkit-style authentication surface.

**Supported compositors:** niri (first-class), Hyprland, Sway, MangoWC, labwc, Scroll, Miracle WM.

### Runtime dependencies — authoritative, from `distro/fedora/dms.spec` (verified verbatim):

```spec
Requires:       (quickshell or quickshell-git)
Requires:       accountsservice
Requires:       dms-cli = %{version}-%{release}
Requires:       dgop
Recommends:     cava
Recommends:     danksearch
Recommends:     matugen
Recommends:     NetworkManager
Recommends:     qt6-qtmultimedia
Suggests:       cups-pk-helper
Suggests:       qt6ct
```

Docs (danklinux.com/docs/dankmaterialshell/installation) list the same: **quickshell required**; cava, dankcalendar, dgop, dsearch, matugen, qt6-multimedia, niri optional. Manual-source-build deps: cmake, qt6base, qt6declarative, qtshadertools, qt6wayland, wayland(-protocols), pam.

**Verified from the F43 COPR RPM metadata** (dnf5 repoquery --requires, 2026-08-28):
- `dms-1.5.3` (avengemedia/dms): `(quickshell or quickshell-git)`, `accountsservice`, `dgop`, `dms-cli = 1.5.3-1.fc43`
- `dms-greeter-1.5.3` (avengemedia/danklinux): `(quickshell-git or quickshell)`, **`greetd`** (pulls greetd automatically), creates the `greeter` user via `useradd`/sysusers

### Config locations (all user-level; DMS ships no /etc files)

| Path | Content |
|---|---|
| `~/.config/DankMaterialShell/` | settings.json, plugins.lock.json |
| `~/.local/state/DankMaterialShell/` | session.json |
| `~/.cache/DankMaterialShell/` | dms-colors.json (matugen palette) |
| `~/.config/niri/config.kdl` | compositor config; `include "dms/{colors,layout,alttab,binds}.kdl"` generated/synced by DMS |
| `~/.config/niri/dms/` | the four DMS-managed kdl fragments |
| `dms.service` | **user** systemd unit, `WantedBy=graphical-session.target`, `Type=dbus`, `BusName=org.freedesktop.Notifications`, `ExecStart=/usr/bin/dms run --session` — installed by the RPM at `%{_userunitdir}/dms.service` |

Startup wiring (from install docs): `systemctl --user enable dms` (all sessions) or **`systemctl --user add-wants niri.service dms`** (niri only — niri ships native systemd session integration; this is the official recommended command, repeated in the niri wiki quick start). Do NOT also put `spawn-at-startup "dms" "run"` in niri config or DMS runs twice (docs warning).

## 2. greetd integration — dms-greeter (DankGreeter)

DMS does **not** ship a static greetd config file in its repo. The greetd integration lives in the companion repo **`AvengeMedia/dank-greeter`** (package `dms-greeter`), which the DMS settings Greeter tab controls. The user's recollection "DMS ships greetd configs" is correct in substance: the `dms-greeter` package manages/writes the greetd configuration (`dms-greeter enable` / `dms-greeter install`), and tunaOS ships the resulting config in their images.

dank-greeter README, verbatim — the greetd config it expects:

```toml
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "/usr/bin/dms-greeter --command niri"
```

Key facts (README):
- `dms-greeter` is a **greetd greeter** (needs greetd) that *launches the compositor itself*: `dms-greeter --command niri` runs niri as the greeter's compositor, generating the compositor config on the fly.
- niri-only special case: `dms-greeter sync` writes the generated greeter config to **`/etc/greetd/niri/config.kdl`**; local manual tweaks go in `/etc/greetd/niri_overrides.kdl`.
- Post-install: `dms-greeter enable` (point greetd at dms-greeter) and `dms-greeter sync` (copy DMS theme/wallpaper/settings into the greeter cache). `dms-greeter install` does interactive full setup incl. writing `/etc/greetd/config.toml`.
- Package creates: `greeter` user, `/var/lib/greeter`, `/var/cache/dms-greeter` (owned greeter:greeter, 2770) — via systemd-sysusers on atomic/immutable distros.
- Requires: greetd, Quickshell (`qs`), one supported compositor.
- Fedora install: `sudo dnf copr enable avengemedia/danklinux && sudo dnf install dms-greeter`.
- Optional: `fprintd fprintd-pam` for fingerprint login (managed PAM in /etc/pam.d/greetd), pam_u2f for security keys.

**tunaOS's actual shipped greetd config** (asserted in build_scripts/checks/verify-branding-niri.sh, measured on published yellowfin:niri 2026-08-01):

```
/etc/greetd/config.toml  launches:
    dms-greeter --command niri -C /etc/greetd/niri/config.kdl
```

tunaOS additionally: `systemctl enable greetd.service` + force-link into `graphical.target.wants` + claim `display-manager.service` alias + `systemctl set-default graphical.target` (install-desktop.sh), and a PAM fix so gnome-keyring unlocks at login:

```bash
sed -i -e '/gnome_keyring.so/ s/-auth/auth/ ; /gnome_keyring.so/ s/-session/session/' /etc/pam.d/greetd
```

## 3. Reference images

### 3a. tuna-os/tunaOS — the primary reference (ships niri + DMS exactly like pluto wants)

`manifests/desktops/niri.yaml` (fedora section), display_manager: **greetd**:

```yaml
copr:
  - repo: yalter/niri-git        # packages: niri        (git builds; Fedora repo also has niri)
  - repo: avengemedia/danklinux  # packages: quickshell-git, dms-greeter
  - repo: avengemedia/dms-git    # packages: dms, dms-cli
packages:
  - greetd, greetd-selinux, swaylock, SwayNotificationCenter, waybar, fuzzel,
    swayidle, swaybg, wl-clipboard, xdg-desktop-portal-gnome, xdg-desktop-portal-gtk,
    xdg-user-dirs, pipewire, wireplumber, NetworkManager-tui, brightnessctl, playerctl,
    blueman, pavucontrol, gnome-keyring, gnome-keyring-pam, nautilus, adw-gtk3-theme,
    papirus-icon-theme
optional:
  - polkit-gnome
post_install_inline:
  - glib-compile-schemas /usr/share/glib-2.0/schemas
  - PAM gnome_keyring fix in /etc/pam.d/greetd
post_install: tuna-flatpak-remote.sh, greetd-gtkgreet.sh (no-op), flatpak-preinstall.sh
versionlock: glib2
```

Their older per-desktop script `build_scripts/desktop/niri.sh` (Fedora branch) adds the fat layer the manifest omits: **fonts** (`default-fonts`, `default-fonts-core-emoji`, `google-noto-color-emoji-fonts`, `google-noto-emoji-fonts`, `glibc-all-langpacks`), **Qt/KDE theming** (`kf6-kirigami`, `qt6ct`, `plasma-breeze`, `kf6-qqc2-desktop-style`), **xwayland** (`xorg-x11-server-Xwayland`, `xwayland-satellite`), terminal **ptyxis** + **foot**, `xdg-terminal-exec`, `gnome-keyring`, `gcr`, `openssh-askpass`, `webp-pixbuf-loader`, `qt6-qtmultimedia`, `dconf` schema compile, plus the same greetd PAM fix. DMS suite there is: `quickshell-git dms dms-cli dms-greeter dgop dsearch matugen` (+ skippable `iio-niri valent-git` from `zirconium/packages` COPR).

**Config placement in tunaOS niri images (their own acceptance contract, verify-branding-niri.sh):**
- `/etc/greetd/config.toml` present, default_session command set, greeter binary executable, `-C` target file exists
- `/usr/share/wayland-sessions/niri.desktop` — **ships inside the `niri` package itself**
- default niri config in **either** `/etc/niri/config.kdl`, `/usr/share/niri/config.kdl`, **or** `/etc/skel/.config/niri/config.kdl`
- wallpaper: swaybg or DMS drawing its own background (DMS does — so no wallpaper daemon strictly needed)

### 3b. Bonus: gabeklavans/bazzite-niri (build_files/build.sh) — conventional wlroots stack under Bazzite

```
niri alacritty gdm xdg-desktop-portal-gtk xdg-desktop-portal-gnome gnome-keyring
nautilus mako fuzzel waybar swayidle swaylock polkit-kde xwayland-satellite swaybg
systemctl --global add-wants niri.service mako.service # + swayidle, swaybg, plasma-polkit-agent
```
Pattern: keep the base DM (GDM), `systemctl --global add-wants niri.service <unit>` baked at build time.

### 3c. niri wiki (niri-wm/niri Getting-Started) — official quick start, DMS-first

```
sudo dnf copr enable avengemedia/dms
sudo dnf install niri dms
systemctl --user add-wants niri.service dms
```
(niri from Fedora repos; greeter-agnostic; notes default niri config spawns waybar → delete that line when using DMS.)

## 4. Fedora 43 availability — measured with dnf5 repoquery (2026-08-28)

**In F43 release+updates repos:** niri (26.04-1.fc43 — ships `/usr/bin/niri`, `/usr/bin/niri-session`, `/usr/share/wayland-sessions/niri.desktop`, `/usr/lib/systemd/user/niri.service`), greetd, greetd-selinux, swaylock, swayidle, swaybg, fuzzel, waybar, SwayNotificationCenter, mako, wl-clipboard, wayland-utils, xwayland-satellite, xorg-x11-server-Xwayland, xdg-desktop-portal, xdg-desktop-portal-gnome, xdg-desktop-portal-gtk, xdg-desktop-portal-wlr, xdg-user-dirs, pipewire, pipewire-pulseaudio, wireplumber, NetworkManager-tui, brightnessctl, playerctl, blueman, pavucontrol, gnome-keyring, gnome-keyring-pam, polkit-kde, nautilus, adw-gtk3-theme, papirus-icon-theme, alacritty, foot, ptyxis, gnome-console, default-fonts, default-fonts-core-emoji, google-noto-emoji-fonts, google-noto-color-emoji-fonts, cava, qt6ct, kf6-kirigami, plasma-breeze, kf6-qqc2-desktop-style, gtkgreet, cage, accountsservice, flatpak, dconf, glib2, mesa-dri-drivers, mesa-vulkan-drivers, mesa-va-drivers, libinput, seatd, fprintd, fprintd-pam, chezmoi, ddcutil, fastfetch, qt6-qtimageformats, qt6-qtmultimedia, tesseract, udiskie, wl-mirror, wtype, xkbcomp.

**NOT in F43 base repos (must come from elsewhere):**
| package | status |
|---|---|
| quickshell / quickshell-git | Fedora 44/45/Rawhide only → **avengemedia/danklinux COPR** (ships both quickshell 0.3.1 and quickshell-git) |
| dms, dms-cli | **avengemedia/dms** COPR (stable 1.5.3) or **avengemedia/dms-git** (git builds; tunaOS uses this) |
| dms-greeter | **avengemedia/danklinux** COPR (1.5.3) |
| matugen, danksearch, dgop | Fedora dgop/danksearch = COPR; matugen COPR (dgop/danksearch also in danklinux; dgop stable also in avengemedia/dms) |
| material-symbols-fonts | danklinux COPR (DMS icon font) |
| cliphist | Fedora 44+ only → danklinux COPR (or skip: DMS has built-in clipboard history) |
| ghostty | **not a Fedora package at all** (packages.fedoraproject.org 404) → danklinux COPR, else ptyxis/foot/alacritty/kitty |
| polkit-gnome | **retired Fedora-wide** → use `polkit-kde` (runs fine under niri; tunaOS's own note) |

## 5. Candidate dnf5 package manifest for pluto (F43)

Install order: COPRs first (`dnf copr enable`, or write repo files), then one strict Fedora-repo transaction. Keep each COPR's packages in its own dnf transaction (tunaOS#1009/#637: dnf fails the whole transaction on one unmatched name — e.g. dms-greeter is ONLY in danklinux).

| Package | Purpose | Source ref | Confidence |
|---|---|---|---|
| **niri** | scrollable-tiling Wayland compositor; ships niri-session, wayland-sessions/niri.desktop, user niri.service | F43 repo (26.04-1.fc43); tunaOS uses yalter/niri-git COPR | verified |
| **greetd** | login manager daemon (pulled automatically by dms-greeter, but list it explicitly + greetd-selinux) | tunaOS niri.yaml; dms-greeter Requires | verified |
| **greetd-selinux** | SELinux policy for greetd | tunaOS niri.yaml | verified |
| **dms** | DMS shell: daemon + CLI (`dms run`, `dms setup`, `dms ipc`) | avengemedia/dms (1.5.3) or dms-git COPR; tunaOS | verified (F43 chroot exists) |
| **dms-cli** | required by dms (Requires: dms-cli = version) | avengemedia/dms COPR | verified |
| **quickshell-git** | QML shell framework (Qt ≥6.10 private APIs — F43 Qt 6.10 OK) | avengemedia/danklinux COPR; tunaOS; not in F43 base | verified |
| **dms-greeter** | Quickshell greetd login screen; launches niri for the greeter; writes /etc/greetd config | avengemedia/danklinux COPR (1.5.3); tunaOS | verified |
| **dgop** | system telemetry for DMS widgets/process list (dms Requires) | avengemedia/dms OR danklinux COPR | verified |
| **accountsservice** | user profiles for DMS (dms Requires) | F43 base; dms RPM Requires | verified |
| **matugen** | Material-3 palette generation for DMS dynamic theming | danklinux COPR; DMS Recommends | verified |
| **danksearch** | filesystem search powering launcher file results | danklinux COPR; DMS Recommends | verified |
| **material-symbols-fonts** | DMS icon font | danklinux COPR (F43 has none) | verified (repo listing) |
| **xdg-desktop-portal-gnome** | screencast/file-chooser portals under niri (niri implements xdp-gnome screencast protocol) | tunaOS (fedora+el10); niri wiki | verified |
| **xdg-desktop-portal-gtk** | GTK file-chooser portal backend | tunaOS; bazzite-niri | verified |
| **xdg-desktop-portal, xdg-user-dirs** | portal core; user dirs | tunaOS (zypper sec.) / base | verified |
| **pipewire, wireplumber, pipewire-pulseaudio** | audio graph; DMS AudioService (PipeWire/Pulse volume control) | tunaOS fedora (pw+wp); pulse bridge for X apps | verified |
| **pavucontrol** | PulseAudio mixer UI (gtk) | tunaOS | verified |
| **swaylock** | fallback lock screen (DMS has own lock; tunaOS ships anyway; niri default binding Super+Alt+L) | tunaOS; bazzite-niri | verified-ish (optional) |
| **swayidle** | fallback idle daemon (DMS has own IdleService) | tunaOS; bazzite-niri | optional |
| **swaybg** | wallpaper daemon (unneeded if DMS draws background — tunaOS accepts either) | tunaOS | optional |
| **fuzzel, waybar, SwayNotificationCenter, mako** | conventional replacements — **redundant under DMS**; keep only as fallback/debug (tunaOS ships them anyway) | tunaOS | optional |
| **wl-clipboard** | wl-paste/wl-copy; cliphist integration (`wl-paste --watch cliphist store`) | tunaOS; DMS docs | verified |
| **gnome-keyring, gnome-keyring-pam** | secret store + PAM unlock (requires greetd PAM fix) | tunaOS (all sections); bazzite-niri | verified |
| **polkit-kde** | GUI polkit authentication agent (polkit-gnome retired; DMS patches out polkit-agent need but GUI apps still ask) | tunaOS el10 note; bazzite-niri | verified choice |
| **networkmanager-tui (or nm-connection-editor)** | connection editing UI for DMS Control Center (DMS talks NM directly) | tunaOS | verified |
| **blueman** | Bluetooth applet (DMS has BluetoothService too) | tunaOS | optional |
| **brightnessctl, playerctl** | backlight/media-key fallbacks (DMS daemon has built-in brightness/MPRIS) | tunaOS | optional |
| **adw-gtk3-theme, papirus-icon-theme** | GTK3 libadwaita theme + icon theme for GTK apps under niri | tunaOS | verified |
| **qt6ct, kf6-kirigami, plasma-breeze, kf6-qqc2-desktop-style** | Qt6 theming (DMS Suggests qt6ct; tunaOS niri.sh) | tunaOS niri.sh | verified |
| **default-fonts, google-noto-color-emoji-fonts, google-noto-emoji-fonts** | base + emoji fonts (server base has essentially none) | tunaOS niri.sh | verified |
| **foot** (or ptyxis/alacritty; ghostty via COPR) | terminal; niri default binding spawns `alacritty` — ship what you bind | tunaOS niri.sh (ptyxis+foot); wiki (alacritty) | choice |
| **nautilus** (+ gvfs if mounting needed) | file manager | tunaOS; bazzite-niri | verified |
| **xwayland-satellite** (and/or xorg-x11-server-Xwayland) | X11 apps under niri (niri is Wayland-only; xwayland-satellite is the tunaOS choice) | tunaOS zypper note + niri.sh | verified |
| **mesa-dri-drivers, mesa-vulkan-drivers, mesa-va-drivers** | GL/Vulkan/VAAPI — server base lacks these; quickshell-git requires libEGL | quickshell-git Requires (measured); F43 base | verified |
| **flatpak** + `/etc/flatpak/remotes.d/flathub.flatpakrepo` | flatpak + Flathub remote (server base has NO flatpak — tunaOS hummingbird note) | tunaOS flatpak scripts; F43 base | verified |
| **cava** | audio visualizer widget (DMS Recommends) | F43 base | verified |
| **qt6-qtmultimedia, qt6-qtimageformats** | DMS sound feedback; image format support | DMS Recommends; tunaOS niri.sh | verified |
| **dconf / glib2** | gsettings; run `glib-compile-schemas` post-install (tunaOS versionlocks glib2) | tunaOS | verified |
| **xdg-terminal-exec** | default-terminal protocol (many apps open links via it) | tunaOS niri.sh (fedora+el10) | inferred-optional |
| **fprintd, fprintd-pam** | fingerprint login via dms-greeter PAM | dank-greeter README | optional |
| **cups-pk-helper** (DMS Suggests), **wtype, wl-mirror, udiskie, ddcutil, fastfetch, zram-generator** | tunaOS convenience extras | tunaOS niri.sh | optional |

### Explicitly NOT needed under a DMS stack
- **waybar / mako / fuzzel / swaylock / swayidle / polkit-agent**: DMS replaces all of them (README). Keep as fallbacks only.
- **gtkgreet + cage**: only needed as the non-DMS greeter (openSUSE path in tunaOS). dms-greeter handles the greeter side itself.
- **plymouth**: tunaOS base installs it for boot splash; not required for a working niri desktop.

### Build-time wiring that must accompany the package install (all from tunaOS, verbsatim patterns)
1. `systemctl enable greetd.service`; force-link `graphical.target.wants/greetd.service`; `systemctl set-default graphical.target`; point `display-manager.service` alias at greetd.
2. Write `/etc/greetd/config.toml`:
   ```toml
   [terminal]
   vt = 1

   [default_session]
   user = "greeter"
   command = "/usr/bin/dms-greeter --command niri -C /etc/greetd/niri/config.kdl"
   ```
3. `sed -i -e '/gnome_keyring.so/ s/-auth/auth/ ; /gnome_keyring.so/ s/-session/session/' /etc/pam.d/greetd`
4. `glib-compile-schemas /usr/share/glib-2.0/schemas`
5. Seed first-user config (see §6); optionally bake `systemctl --global add-wants niri.service dms` (bazzite-niri pattern) or `/usr/lib/systemd/user/` preset.
6. `dms-greeter sync` cannot run at image build (needs a synced user theme) — ships fine with just the greetd config above; user runs `dms-greeter sync` once after login, or it is no-op until then (verify-branding-niri.sh only requires the greeter binary + config present).

## 6. Config placement recommendation for pluto

| File | Placement | Why |
|---|---|---|
| greetd config | **`/etc/greetd/config.toml`** (system, in-image) | greetd reads this at boot; dms-greeter expects it |
| greeter compositor config | `/etc/greetd/niri/config.kdl` (written by `dms-greeter sync`; optional `-C` in config.toml then resolves) | dms-greeter docs; tunaOS ships/asserts it |
| session file | `/usr/share/wayland-sessions/niri.desktop` — **comes with the niri RPM** | verify-desktop-experience.sh require_glob; pass |
| default niri config | **`/etc/skel/.config/niri/config.kdl`** (+ `dms/` fragments: colors/layout/alttab/binds.kdl) | tunaOS accepts /etc/skel, /etc/niri, /usr/share/niri; skel gives every new user a working DMS-ified config; created via `dms setup` output, hand-shipped at build |
| DMS config | user-level `~/.config/DankMaterialShell/` — **do not force into image**; first-run default is fine; plugins.lock.json is user-synced | DMS docs; AGENTS.md |
| DMS autostart | bake `systemctl --global add-wants niri.service dms` at build (writes /etc/systemd/user/niri.service.wants/dms.service into the image) | niri wiki quick start; bazzite-niri build.sh |
| flatpak | `flatpak` pkg + `/etc/flatpak/remotes.d/flathub.flatpakrepo` (curl from dl.flathub.org) | tunaOS tuna-flatpak-remote.sh |

niri config must include the DMS fragments and env block (DMS compositor docs, quoted):
```
include "dms/colors.kdl"    include "dms/layout.kdl"
include "dms/alttab.kdl"    include "dms/binds.kdl"
environment {
  XDG_CURRENT_DESKTOP "niri"
  QT_QPA_PLATFORM "wayland"
  ELECTRON_OZONE_PLATFORM_HINT "auto"
  QT_QPA_PLATFORMTHEME "gtk3"
  QT_QPA_PLATFORMTHEME_QT6 "gtk3"
}
layer-rule { match namespace="^quickshell$"  place-within-backdrop true }
layout { gaps 5  background-color "transparent" }
```
plus `binds` for `dms ipc call spotlights etc. (docs provide the full block) and no `spawn-at-startup "dms" "run"` if the systemd unit is enabled.

## 7. What could NOT be verified

- **avengemedia/dms vs avengemedia/dms-git freshness/equivalence** — both exist with F43 chroots (measured: dms stable 1.5.3 + dms-cli in `dms`; git builds in `dms-git`). tunaOS uses `dms-git`; niri wiki's quick start names `avengemedia/dms`. Recommend stable `avengemedia/dms` for a production OS image; both satisfy the rpm Requires.
- **yalter/niri-git COPR contents for F43** — COPR web UI is behind the Anubis anti-bot wall and the API 404'd; use is inferred from tunaOS manifests. Unnecessary for F43 anyway (Fedora niri 26.04 exists).
- **DMS does not ship a static greetd config file in-repo** — the "greetd configs" are generated by `dms-greeter enable/install/sync`; the exact expected content is quoted from the README and tunaOS contract above.
- **cava in danklinux COPR** — not present in the F43 danklinux listing (it's in Fedora base; fine).
- **DMS lock-screen PAM/polkit interplay on bootc** — DMS lock uses the session-lock protocol; auth via PAM handled by dms daemon (docs: Lock Screen Authentication page) — exact PAM file not inspected.
- **greetd user-unit `dms.service` graphical-session ordering under dms-greeter-launched niri** — niri's own systemd integration starts the graphical session target; assumed per niri wiki (quick start works this way in the field).
- **Whether the Hummingbird base repo resolves the same package set as F43 stable repos** — tunaOS documents Hummingbird as a Fedora-Rawhide-adjacent rebuild whose repo carries ~1 desktop package; plan a `dnf repoquery` smoke-check of the manifest names against the actual base before first build.

## Reference links
- DMS repo: https://github.com/AvengeMedia/DankMaterialShell
- DMS docs: https://danklinux.com/docs/dankmaterialshell/installation · compositors: https://danklinux.com/docs/dankmaterialshell/compositors
- dank-greeter: https://github.com/AvengeMedia/dank-greeter
- tunaOS main builder: https://github.com/tuna-os/tunaOS (`manifests/desktops/niri.yaml`, `build_scripts/desktop/niri.sh`, `build_scripts/checks/verify-branding-niri.sh`)
- bazzite-niri (bonus): https://github.com/gabeklavans/bazzite-niri
- niri wiki Getting-Started: https://github.com/niri-wm/niri/wiki/Getting-Started
- COPRs: avengemedia/dms (stable), avengemedia/dms-git (git), avengemedia/danklinux (greeter+quickshell+companions), yalter/niri-git (optional)
