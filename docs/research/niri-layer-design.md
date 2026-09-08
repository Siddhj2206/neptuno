# Niri + DankMaterialShell (DMS) Desktop Layer — Research & Design

**Date:** 2026-08-28 · **Target:** pluto bootc image (Fedora Hummingbird bootc-os, F43)
**Sources cloned locally (all cites below are file paths + relevant lines):**

| Repo | Local path | Used for |
|---|---|---|
| AvengeMedia/DankMaterialShell | `/tmp/opencode/dms` | DMS install flow, deployed configs, systemd units |
| AvengeMedia/dank-greeter | `/tmp/opencode/niri-refs/dank-greeter` | greetd integration, greeter niri session |
| tunaOS (builder) + zirconium snapshot | `/tmp/opencode/niri-refs/tunaOS` (+ `_upstream-snapshots/zirconium`) | Fedora niri package list, greetd/pam/tmpfiles payload, systemd presets |
| projectbluefin/bluefin + projectbluefin/common | `/tmp/opencode/bluefin`, `/tmp/opencode/common` | Preinstalled flatpak set, gschema/dconf theming pattern, flatpak-override mechanism |
| pluto | `/var/home/sid/Documents/Projects/pluto` | Build layout (`build/20-base.sh`, `packages/base.toml`, `custom/config → /etc/skel`, `custom/flatpaks/default.preinstall`) |

---

## 1. DMS install script — the "normal install" path

### 1.1 What the installer is

The `curl install.danklinux.com | sh` script is only a downloader of a **Go binary `dankinstall`** (`/tmp/opencode/dms/core/install.sh` — fetches `dankinstall-$ARCH.gz` + `.sha256` from GitHub releases, verifies, executes). It refuses to run as root. All real logic lives in `dankinstall`:

- `core/cmd/dankinstall/main.go` — headless mode flags: `--compositor niri|hyprland|mango`, `--term ghostty|kitty|alacritty`, `--include-deps`, `--exclude-deps`, `--replace-configs=niri,ghostty`, `--replace-configs-all`, `-y`, `--danksearch`, `--dankcalendar`. Without flags it runs an interactive TUI.
- The flow (headless): detect OS → detect dependencies → print plan → require `-y` → sudo → install packages → **greeter setup** (if `dms-greeter` was chosen) → **danksearch service setup** → **deploy configs** via `config.NewConfigDeployer`.

### 1.2 What it installs on Fedora (niri choice) — `core/internal/distros/fedora.go`

Detected as **required** (`DetectDependenciesWithTerminal`, lines 69–109 + package map lines 126–160):

| Dep | Package source | Notes |
|---|---|---|
| dms (DankMaterialShell) | COPR `avengemedia/dms` (git variant: `avengemedia/dms-git`) | **detected by `~/.config/quickshell/dms` existing**, not by rpm (`base.go:116`) |
| ghostty | COPR `avengemedia/danklinux` | (pluto already plans `scottames/ghostty` — same outcome, different repo) |
| git | Fedora | |
| niri | COPR `yalter/niri` (git variant `yalter/niri-git`, sets `priority=1`) | **F43 note: niri is in Fedora proper** (packages.fedoraproject.org shows fc43–fc45 builds), but both reference images use the yalter COPR |
| quickshell | COPR `avengemedia/danklinux` (needs ≥ 0.2.0, `base.go:261`) | **not in F43 Fedora repos** — only fc44+ (verified on packages.fedoraproject.org) |
| dms-greeter | COPR `avengemedia/danklinux` | optional (opt-in via include-deps/TUI) |
| xdg-desktop-portal-gtk | Fedora | |
| accountsservice | Fedora | dms provides user avatars etc. |
| xwayland-satellite | Fedora | niri-specific |
| matugen | COPR `avengemedia/danklinux` | optional (auto-theming engine) |
| danksearch | COPR `avengemedia/danklinux` | optional (launcher file search) |
| dankcalendar | COPR `avengemedia/danklinux` (`dankcalendar-git`) | optional |

Prerequisites installed first (`getPrerequisites`, fedora.go:219): `dnf-plugins-core make unzip libwayland-server golang-bin` (golang only if no go binary).

**COPR grouping lesson (tunaOS#1009, quoted in `tunaOS/manifests/desktops/niri.yaml:12–29`):** `dms`/`dms-cli` live in `avengemedia/dms-git`; `dms-greeter`, `quickshell(-git)`, `dgop`, `danksearch`, `matugen` live in `avengemedia/danklinux`. One dnf transaction referencing a package from the wrong repo fails the whole transaction. **pluto's `niri.toml` must use one `["copr:"]` section per repo.**

### 1.3 What it configures after install (the parts we care about)

All in `core/internal/distros/base.go` + `core/internal/config/deployer.go`:

1. **`WriteEnvironmentConfig` (base.go:559)** — writes `~/.config/environment.d/90-dms.conf`:
   ```
   ELECTRON_OZONE_PLATFORM_HINT=auto
   TERMINAL=ghostty
   ```
2. **`EnableDMSService` (base.go:595)** — for niri: `systemctl --user add-wants niri.service dms`. **This is the systemd-mode wiring**: the `dms` user unit (shipped by the dms RPM at `%{_userunitdir}/dms.service`) is *wanted by* niri.service. **No `spawn-at-startup "dms" "run"` in systemd mode** — the deployer only adds that when `useSystemd=false` (`deployer.go:884–906`, `transformNiriConfigForNonSystemd`). Mixing both = double start (the unit is `Type=dbus`, `BusName=org.freedesktop.Notifications`; a second instance loses the bus name and the shell starts twice).
3. **Greeter setup (runner.go:224–235)** — if `dms-greeter` was included: runs the standalone binary `dms-greeter install --yes` (via `utils/greeter_setup.go`); the dms-greeter binary **owns greetd configuration** ("greeter setup is delegated to... the dms-greeter binary, which owns greetd configuration since the greeter moved out of DMS"). Non-fatal on failure.
4. **Config deployment (`config/deployer.go`)**:
   - `~/.config/niri/config.kdl` — backed up if present, then **replaced** with the embedded `embedded/niri.kdl` (template; `{{TERMINAL_COMMAND}}` → `ghostty`). Existing `output "..." { }` blocks are *merged* into `~/.config/niri/dms/outputs.kdl`.
   - `~/.config/niri/dms/{colors,layout,alttab,binds,input}.kdl` written; `outputs.kdl`, `cursor.kdl`, `windowrules.kdl` created **empty**; existing non-empty files are preserved.
   - `~/.config/ghostty/config` + `~/.config/ghostty/themes/dankcolors`.
   - Behavior: with no `--replace-configs` flags, configs are deployed **only if the target file doesn't exist** (fresh-install scenario, `deployer.go:95–118`). `--replace-configs-all` backs up + overwrites.
5. **`dms run` does NOT deploy configs.** niri config.kdl, the dms/*.kdl fragments and ghostty config come exclusively from `dankinstall` or `dms setup` (interactive deployer, `commands_setup.go`). Landing a DMS session without ever running either leaves niri at upstream defaults with no DMS. **This is the gap pluto's /etc/skel seeding fills.**

### 1.4 What DMS auto-generates on first run (NOT to bake)

From the QML/Go sources:

- `~/.config/DankMaterialShell/` is created by the shell itself at first start (`quickshell/Common/Paths.qml:21,29` — `config: ${GenericConfigLocation}/DankMaterialShell`, `mkdir(imagecache)` on startup).
- `~/.config/DankMaterialShell/.firstlaunch` marker → first-run "greeter" welcome UI (`quickshell/Services/FirstLaunchService.qml:15–17`). A `settings.json` triggers "existing_user" mode instead.
- Runtime state: `~/.local/share/DankMaterialShell`, `~/.local/state/DankMaterialShell` (session.json), `~/.cache/DankMaterialShell` (imagecache, dms-colors.json), `clsettings.json` (clipboard history — `core/internal/server/clipboard/types.go:43`).
- Theming side-effects (user action driven): `~/.config/qt6ct/qt6ct.conf`, `~/.local/share/color-schemes/DankMatugen.colors`, GTK settings via `scripts/gtk.sh` (adw-gtk3 patching), all generated by matugen when a wallpaper is applied.

**Implication for pluto:** do NOT bake `~/.config/DankMaterialShell/*` into /etc/skel (stock files would suppress the first-run tour; runtime files are cache/state anyway). Bake shell *wallpapers/settings* only through the normal DMS UI, or as an optional tmpfiles L-symlink pattern like zirconium's `99-dms-greeter.conf` (below).

### 1.5 dms-greeter and greetd (the greeter integration)

Researched from `/tmp/opencode/niri-refs/dank-greeter`:

- Binary contract: `dms-greeter --command COMPOSITOR [--cache-dir DIR] [-C CONFIG]` (`core/cmd/dms-greeter/commands.go:28,45`). Requires `--cache-dir` to **already exist** (default `/var/cache/dms-greeter`).
- RPM provides (fedora spec `distro/fedora/dms-greeter.spec:78,77`):
  - tmpfiles `assets/systemd/tmpfiles-dms-greeter.conf`: `d /var/cache/dms-greeter 0750 greeter greeter -` and `d /var/lib/greeter 0755 greeter greeter -`
  - sysusers for the `greeter` user (uid/gid 767 per zirconium's `usr/lib/sysusers.d/dms-greeter.conf`).
- Greeter niri session (`core/internal/launcher/compositor.go:63–92`): builds a temp config = optional `-C` file **+ includes of `/usr/share/greetd/niri_overrides.kdl` and `/etc/greetd/niri_overrides.kdl` (if present) + a spawn-at-startup that runs the greeter QS shell then `niri msg action quit --skip-confirmation`**. With no `-C` file it uses a minimal built-in base (black background, `DMS_RUN_GREETER=1`).
- `dms-greeter install` (installer.go) writes/upserts `/etc/greetd/config.toml`: `default_session.user = "greeter"`, `command = "dms-greeter ..."`; autologin uses `launch-session --from-memory --cache-dir ...` under `initial_session`. Backs up prior config; also handles PAM/group wiring.
- **Zirconium/tunaOS ship the greetd config baked** (not via `dms-greeter install`): `_upstream-snapshots/zirconium/mkosi.extra/usr/share/factory/etc/greetd/config.toml`:
  ```toml
  [general]
  service = "greetd-spawn"

  [terminal]
  vt = 1

  [default_session]
  command = "dms-greeter --command niri --cache-dir /var/cache/dms-greeter -C /etc/greetd/niri/config.kdl"
  user = "greeter"
  ```
  with `/etc/greetd/niri/config.kdl` **intentionally empty** (comment-only; greeter then runs niri's built-in defaults) — tunaOS re-creates this exact file at build time because upstream's factory tmpfiles never survives (`build_scripts/install-zirconium.sh:63–95`), and their verify script asserts it exists (`build_scripts/checks/verify-branding-niri.sh:78–85`).
  TunaOS also installs `usr/lib/pam.d/greetd-spawn` (pam_env with `XDG_SESSION_TYPE DEFAULT=wayland OVERRIDE=wayland` via `usr/share/greetd/greetd-spawn.pam_env.conf`) and fixes `/etc/pam.d/greetd` for gnome-keyring: `sed '/gnome_keyring.so/ s/-auth/auth/ ; /gnome_keyring.so/ s/-session/session/'` (`mkosi.postinst.chroot`, also `manifests/desktops/niri.yaml:264`).

**Conclusion: the user's plan is exactly the zirconium/tunaOS pattern** — bake `/etc/greetd/config.toml` with `dms-greeter --command niri`, plus the pam_env files, plus an empty `/etc/greetd/niri/config.kdl`. greetd itself is already in pluto's base (`greetd`, `greetd-selinux` in base.toml; `systemctl enable greetd.service` in 20-base.sh).

### 1.6 Systemd session wiring (dms.service)

The dms RPM ships `assets/systemd/dms.service` → `%{_userunitdir}/dms.service`:

```ini
[Unit]
Description=Dank Material Shell (DMS)
PartOf=graphical-session.target
After=graphical-session.target
Requisite=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=/usr/bin/dms run --session
...
[Install]
WantedBy=graphical-session.target
```

niri.service (upstream, `resources/niri.service`): `ExecStart=niri --session`, `BindsTo=graphical-session.target`, `Before=graphical-session.target`. So the chain is: greetd → user session → niri.service → graphical-session.target + (via `add-wants niri.service dms` or preset) dms.service.

- Zirconium enables dms.service via **user preset** `usr/lib/systemd/user-preset/01-zirconium.preset` (`enable dms.service`) — the immutable-image-friendly equivalent of the per-user `add-wants`.
- Zirconium also ships a dms override: `usr/lib/systemd/user/dms.service.d/override.conf` → `Environment=DMS_SCREENSHOT_EDITOR=satty`.
- Their user preset also enables `udiskie.service`, `iio-niri.service`, `foot-server.service/.socket`, `gcr-ssh-agent`, `gnome-keyring-daemon(.socket)`, `chezmoi-init.service`, `danksearch.service`, `fcitx5.service` — with **user units shipped in the image** (`usr/lib/systemd/user/udiskie.service`, `iio-niri.service`, `chezmoi-init.service`, `chezmoi-update.timer/.service`; all `WantedBy=graphical-session.target` where applicable).
- tunaOS notes (install-desktop.sh:766ff) that on Fedora `greetd.service` is `WantedBy=graphical.target`, and they force-link it into `/etc/systemd/system/graphical.target.wants/` + take over the `display-manager.service` alias — a useful guard for pluto's 20-base.sh (`systemctl enable greetd.service` should produce the display-manager alias already; verify at build).

### 1.7 Bake vs first-run summary (DMS)

| Item | Decision | Evidence |
|---|---|---|
| niri, quickshell, dms, dms-cli, dms-greeter, dgop, matugen, ghostty, xwayland-satellite, accountsservice | **Bake** (packages/niri.toml, COPR sections per provider repo) | fedora.go mapping; tunaOS niri.sh |
| `~/.config/niri/config.kdl` + `dms/*.kdl` + ghostty config | **Bake via /etc/skel** (`custom/config/`) — DMS ships no defaults; without any deployer they never exist | deployer.go; tunaOS verify-branding-niri.sh:134–142 accepts /etc/skel as "default config ships" |
| `dms.service` enablement | **Bake** a user preset `/usr/lib/systemd/user-preset/01-pluto-niri.preset` (`enable dms.service`) — or run file-based `add-wants` at first boot. Do **not** add `spawn-at-startup "dms" "run"` to config.kdl | zirconium user-preset; base.go EnableDMSService; deployer transform |
| `/etc/greetd/config.toml`, `/etc/greetd/niri/config.kdl` (empty), pam.d/greetd-spawn, greetd-spawn.pam_env.conf, greetd pam gnome-keyring fix | **Bake** (image build) | zirconium mkosi.extra; tunaOS install-zirconium.sh |
| `~/.config/environment.d/90-dms.conf` (ELECTRON_OZONE_PLATFORM_HINT, TERMINAL) | **Bake via /etc/skel** (matches what the installer writes) | base.go:582–584 |
| `~/.config/DankMaterialShell/*` | **First-run only** — DMS creates it itself; do not seed | Paths.qml, FirstLaunchService.qml |
| `dms setup` / `dankinstall` / greeter autoconfig | **Do not run at build** (refuses root; per-user sudo); not needed since everything above is baked | main.go root check; greeter_setup.go |
| Flatpak preinstall | **Bake declarations** in `custom/flatpaks/default.preinstall` + enable `flatpak-preinstall.service` | bluefin/tunaOS pattern (below) |

---

## 2. GUI apps — native vs flatpak

### 2.1 Reference sets

**Zirconium F43 package list** (`_upstream-snapshots/zirconium/mkosi.conf.d/fedora/mkosi.conf.d/zirconium.conf` + niri.conf/dms.conf/terra.conf) — niri-relevant apps/utilities:
`bolt brightnessctl btop cava chezmoi ddcutil default-fonts default-fonts-core-emoji distribution-gpg-keys distrobox fastfetch fcitx5-chinese-addons fcitx5-mozc fcitx5-rime flatpak foot fzf gcr generic-logos git-core glibc-all-langpacks glycin-thumbnailer gnome-disk-utility gnome-keyring gnome-keyring-pam gnupg2-scdaemon google-noto-color-emoji-fonts google-noto-emoji-fonts greetd greetd-selinux gst-thumbnailers gum hyfetch input-remapper just kanshi kf6-kimageformats kf6-kirigami kf6-qqc2-desktop-style khal librime-lua lshw nano-default-editor nautilus nautilus-python ncurses nm-connection-editor nmtui openrgb-udev-rules openssh-askpass orca pam-u2f pamu2fcfg plasma-breeze playerctl qt6-qtimageformats qt6-qtmultimedia steam-devices tailscale tesseract udiskie webp-pixbuf-loader wev wl-clipboard wl-mirror wtype xdg-desktop-portal-gnome xdg-desktop-portal-gtk xdg-terminal-exec xdg-user-dirs xorg-x11-server-Xwayland xwayland-satellite ykman` (+ terra: `iio-niri maple-fonts satty valent xdg-terminal-exec-nautilus`; + needs `xdg-desktop-portal-gnome` and DMS suite `dms dms-cli dms-greeter dgop dsearch quickshell`).

**tunaOS niri.sh Fedora section** (`build_scripts/desktop/niri.sh:114–254`) adds over zirconium: `fcitx5-mozc`(conditional), `zram-generator`, plus the Qt theming trio `kf6-kirigami qt6ct plasma-breeze kf6-qqc2-desktop-style` and fonts `default-fonts-core-emoji google-noto-color-emoji-fonts google-noto-emoji-fonts glibc-all-langpacks default-fonts`. Their COPR usage: `yalter/niri-git` (priority=1), `avengemedia/danklinux` + `avengemedia/dms-git` (enable→install→disable), `zirconium/packages` for iio-niri/valent-git.

**Bluefin preinstalled flatpaks** (`/tmp/opencode/common/system_files/bluefin/usr/share/ublue-os/homebrew/system-flatpaks.Brewfile`) — the "good stuff" set, 37 apps:
`be.alexandervanhee.gradia com.github.PintaProject.Pinta com.github.tchx84.Flatseal com.mattjakeman.ExtensionManager com.ranfdev.DistroShelf io.github.flattool.Ignition io.github.flattool.Warehouse io.github.kolunmi.Bazaar io.gitlab.adhami3310.Impression io.missioncenter.MissionCenter it.mijorus.smile org.gnome.Calculator org.gnome.Calendar org.gnome.Characters org.gnome.Connections org.gnome.Contacts org.gnome.DejaDup org.gnome.FileRoller org.gnome.Firmware org.gnome.Logs org.gnome.Loupe org.gnome.Maps org.gnome.NautilusPreviewer org.gnome.Papers org.gnome.Showtime org.gnome.SimpleScan org.gnome.Snapshot org.gnome.Decibels org.gnome.TextEditor org.gnome.Weather org.gnome.baobab org.gnome.clocks org.gnome.font-viewer org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark org.mozilla.thunderbird org.mozilla.firefox page.tesk.Refine` (DX extras: `de.leopoldluley.Clapgrep io.github.getnf.embellish io.podman_desktop.PodmanDesktop me.iepure.devtoolbox org.gnome.Builder com.github.tuna_os.Tavern`). Note: these install on demand (`ujust install-system-flatpaks`, `bctl`); the *only* flatpak preinstalled at first boot is Bazaar via `preinstall.d` (bluefin + tunaOS), plus tunaOS adds Firefox.

**Bluefin native RPM GUI-relevant set** (`build_files/packages/base.toml`, GNOME base from silverblue): firefox (rpm), gnome-tweaks, nautilus, gnome-ponytail-daemon, zenity, ddcutil, plus GNOME stack inherited from the base image. Bluefin ships the GNOME core GUI mostly as **flatpaks** (list above), file managers/disk tools **native**.

### 2.2 Decision table

Flathub verification method: `GET https://flathub.org/api/v2/appstream/<id>` → 200 = on Flathub (first batch via webfetch, remainder via curl; all on 2026-08-28). 404 = not on Flathub.

**Native (into `packages/niri.toml`, matching zirconium/tunaOS Fedora set):**

| App | Why native | Verification |
|---|---|---|
| nautilus | NOT on Flathub (files manager, gvfs/udiskie integration; tunaOS+zirconium both ship native) | flathub `org.gnome.Nautilus` → 404 |
| gnome-disk-utility (GNOME Disks) | NOT on Flathub | `org.gnome.DiskUtility` → 404 |
| gnome-keyring + gnome-keyring-pam | system service, PAM | — (base.toml already has both) |
| udiskie | automount daemon for niri (zirconium ships a user unit `usr/lib/systemd/user/udiskie.service`) | in Fedora (fc43+) ✓ |
| kanshi | display profile daemon (zirconium) | in Fedora |
| wl-clipboard + wtype + wl-mirror | Wayland clipboard/type/mirror tools (zirconium/tunaOS) | in Fedora |
| grim/slurp/swappy/satty | **niri has built-in screenshot (`niri msg action screenshot`)** and DMS has `dms screenshot` (+ `DMS_SCREENSHOT_EDITOR`); satty as the editor is zirconium's choice (terra repo) | satty not in Fedora, not flatpak (flathub id check "satty" → invalid/422) → terra COPR or skip |
| xwayland-satellite | X11 app support under niri (required by DMS installer) | in Fedora |
| xdg-terminal-exec + xdg-terminal-exec-nautilus | terminal launch plumbing; nautilus integration (zirconium terra) | in Fedora (nautilus variant needs terra) |
| iio-niri (autorotation), valent (KDE Connect), maple-fonts | zirconium extras from terra COPR — optional | — |
| qt6ct, plasma-breeze, kf6-kirigami, kf6-qqc2-desktop-style | Qt theming (zirconium/tunaOS) — see §3 | in Fedora (zirconium ships them; tunaOS niri.sh installs explicitly) |
| papirus-icon-theme, adw-gtk3-theme | theming (tunaOS manifest, base.toml already has adw-gtk3-theme) | in Fedora |
| fonts (default-fonts, noto-emoji, etc.) | base.toml already covers | — |
| nm-connection-editor / NetworkManager-tui, pavucontrol, blueman | settings-ish tools (tunaOS/zirconium); blueman already? tbd | in Fedora |
| cava, playerctl, brightnessctl, bolt, btop | zirconium utility set; base.toml already has cava/playerctl/brightnessctl | — |
| gnome-keyring / pam-u2f? | skip unless needed | — |

**Flatpak (into `custom/flatpaks/default.preinstall` — all verified on Flathub 200):**

| App ID | App | Verified | Notes |
|---|---|---|---|
| io.github.kolunmi.Bazaar | app store (bluefin/zirconium preinstall) | ✓ (0.9.4) | keep; replaces gnome-software |
| org.mozilla.firefox | browser (tunaOS preinstalls it too) | ✓ (154.0.1) | bluefin's choice; flatpak even in GNOME images |
| org.gnome.TextEditor | text editor | ✓ (50.1) | zirconium preinstall.d has it |
| org.gnome.Calculator | calculator | ✓ (50.0) | |
| org.gnome.FileRoller | archive manager | ✓ (44.7) | |
| org.gnome.Loupe | image viewer | ✓ (50.0) | |
| org.gnome.Papers | PDF viewer | ✓ (50.2) | |
| io.missioncenter.MissionCenter | system monitor | ✓ (1.2.0) | bluefin native-helper uses `missioncenter-helper`; flatpak fine |
| org.gnome.baobab | disk usage | ✓ (50.0) | |
| org.gnome.Logs | log viewer | ✓ (50.0) | |
| org.gnome.SimpleScan / org.gnome.Snapshot | scanner / camera | ✓ / ✓ (50.0) | optional |
| it.mijorus.smile | emoji picker | ✓ (2.12.2) | |
| io.github.flattool.Warehouse | flatpak management | ✓ (2.2.0) | |
| com.github.tchx84.Flatseal | flatpak permissions | ✓ (2.4.1) | |
| org.gtk.Gtk3theme.adw-gtk3 / -dark | GTK3 theme flatpaks | ✓ (6.5) | needed so *flatpak* GTK3 apps match theme |
| org.gnome.clocks / org.gnome.Weather / org.gnome.Calendar | GNOME apps | ✓ (50.0) | optional |

Not flatpak-able: nautilus, gnome-disk-utility (both 404 on Flathub) → native. `org.gnome.Screenshot` → 404 (niri/DMS screenshot instead).

---

## 3. Theming — GTK, Qt, overrides, env

### 3.1 GTK

Reference pattern (bluefin, `/tmp/opencode/common/system_files/bluefin/`):

- **gschema.override** for non-relocatable schemas: `usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override` — sections like `[org.gnome.desktop.interface]` `font-name="Adwaita Sans 11"`, `accent-color="slate"`; file must end up compiled (`glib-compile-schemas /usr/share/glib-2.0/schemas` — both tunaOS niri.sh and manifests add this).
- **dconf db** for relocatable schemas (folders, media-keys custom keybindings): `etc/dconf/db/distro.d/*` + `dconf-update.service` (`/usr/bin/dconf update`, WantedBy=multi-user.target) + optional `locks/` dir.
- Zirconium also runs `glib-compile-schemas` (niri.sh:239).

For a niri/DMS desktop the GTK color-scheme itself is **owned by DMS at runtime** (matugen → `~/.config/gtk-4.0/settings.ini`, `gtk-3.0/`, adw-gtk3 patching via `quickshell/scripts/gtk.sh`). Ship defaults only: `adw-gtk3-theme` package + a minimal gschema.override for font/icon defaults (e.g. `[org.gnome.desktop.interface] gtk-theme='Adwaita' color-scheme='prefer-dark' icon-theme='Papirus'`), letting DMS override once a wallpaper is applied.

### 3.2 Qt

- Packages (tunaOS niri.sh Fedora + EL10 sections, lines 223–228 / 373–378): `kf6-kirigami`, `qt6ct`, `plasma-breeze`, `kf6-qqc2-desktop-style`. (pluto niri.toml: same four.)
- Env: `QT_QPA_PLATFORMTHEME=qt6ct` (+ `QT_QPA_PLATFORM=wayland`). DMS's own non-systemd niri config sets `QT_QPA_PLATFORMTHEME "gtk3"` + `QT_QPA_PLATFORMTHEME_QT6 "gtk3"` (`deployer.go:884–892`) — the DMS settings UI accepts either gtk3 or qt6ct (`quickshell/Modules/Settings/ThemeColorsTab.qml:279`); with qt6ct installed, qt6ct is the recommended value. DMS writes `~/.config/qt6ct/qt6ct.conf` + `~/.local/share/color-schemes/DankMatugen.colors` when matugen-ing (`scripts/qt.sh`).
- Where to set it: **niri config `environment { }` block** (niri exports env to itself, spawned processes and autostart) — this is the mechanism DMS uses in non-systemd mode; in pluto's systemd mode put the same vars in the niri env block (config.kdl) *and/or* `~/.config/environment.d/` (systemd user manager applies it to niri.service — DMS's installer writes `90-dms.conf` there for TERMINAL/ELECTRON). Recommended: keep installer-compatible `environment.d/90-dms.conf` (TERMINAL, ELECTRON_OZONE_PLATFORM_HINT) in /etc/skel and add `QT_QPA_PLATFORM`, `QT_QPA_PLATFORMTHEME=qt6ct`, `XDG_CURRENT_DESKTOP=niri` in the niri config env block. Plasma-breeze provides the KDE color scheme target; kf6-kirigami/qqc2-desktop-style are libraries pulled by Qt apps.

### 3.3 Icons / cursor / fonts

- Icon theme: **papirus-icon-theme** (tunaOS niri manifest Fedora + EL10 both list it). Cursor: Fedora default (Adwaita); set `XCURSOR_SIZE`/`XCURSOR_THEME` in the env block if desired.
- Fonts: base.toml already ships `default-fonts adwaita-fonts-all noto-emoji* cjk`; zirconium adds `maple-fonts` (terra) — optional.

### 3.4 Flatpak system overrides — mechanism (verified, corrected)

**Important correction to the plan:** flatpak does **not** read `/etc/flatpak/overrides/`. Verified in flatpak source (`common/flatpak-dir.c`): overrides are text files at `<basedir>/overrides/<appid>` (and `global`) where the system basedir is `/var/lib/flatpak` — i.e. `/var/lib/flatpak/overrides/<appid>` (`flatpak_dir_load_override`, `flatpak_dir_get_system_default_base_dir_location`; user overrides at `~/.local/share/flatpak/overrides/`). `/etc/flatpak` is used only for `remotes.d`, `installations.d`, `config`.

The proven immutability-safe mechanisms (both from projectbluefin/common, `/tmp/opencode/common/system_files/bluefin/`):

1. **System-level:** ship payload at `/usr/share/ublue-os/flatpak-overrides/<appid>` + tmpfiles symlink into the flatpak location:
   `usr/lib/tmpfiles.d/bazaar-flatpak.conf`:
   ```
   L /var/lib/flatpak/overrides/io.github.kolunmi.Bazaar - - - - /usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar
   ```
   (documented in common/README.md "Flatpak Overrides" section).
2. **User-level:** ship the file directly in `etc/skel/.local/share/flatpak/overrides/<appid>` (bluefin ships `com.visualstudio.code` = `[Context] sockets=wayland; filesystems=xdg-run/podman;` and `com.google.Chrome`).

Overrides worth shipping for a niri layer (per-app `[Context]`/`[Environment]`, format = keyfile with `;`-separated values):
- `[Context] sockets=wayland;` for any X11-only flatpak (e.g. Chrome).
- `[Environment] MOZ_ENABLE_WAYLAND=1` for Firefox (Firefox flatpak defaults to XWayland on non-GNOME desktop unless XDG_CURRENT_DESKTOP hints; on niri set it explicitly), `QT_QPA_PLATFORM=wayland`, `GTK_THEME=adw-gtk3`/`-dark` for GTK3 flatpaks.

### 3.5 Env plumbing summary

| Var | Where shipped | Who reads it |
|---|---|---|
| `TERMINAL=ghostty`, `ELECTRON_OZONE_PLATFORM_HINT=auto` | `/etc/skel/.config/environment.d/90-dms.conf` (matches DMS installer) | systemd user session → niri |
| `XDG_CURRENT_DESKTOP=niri`, `QT_QPA_PLATFORM=wayland`, `QT_QPA_PLATFORMTHEME=qt6ct`, `XCURSOR_*` | niri config `environment { }` block | niri + spawned apps |
| Greeter session: `XDG_SESSION_TYPE=wayland` | pam_env `greetd-spawn.pam_env.conf` (baked) | greetd-spawn PAM |
| DMS internals | `DMS_PRIVESC=run0` (zirconium profile.d), `DMS_SCREENSHOT_EDITOR=satty` (dms.service.d override) | optional |

Reference images do **not** use /etc/environment or profile.d for session env (only display/IM/font vars); the niri `environment {}` block + systemd `environment.d` are the mechanisms.

---

## 4. Configs

### 4.1 niri config.kdl — layout of a pluto default

Structure = DMS's deployed config (`/tmp/opencode/dms/core/internal/config/embedded/niri.kdl`), which tunaOS/zirconium end up with after `dms setup`:

```
config-notification { disable-failed }
gestures { hot-corners { off } }
input { keyboard { xkb { } numlock } ... }
layout { border{...} shadow{...} struts{} }
layer-rule { match namespace="^quickshell$"  place-within-backdrop true }   ← DMS layer rule (niri.kdl:118–121)
overview { workspace-shadow { off } }
environment { XDG_CURRENT_DESKTOP "niri"      ← extend per §3.5 }
hotkey-overlay { skip-at-startup }
prefer-no-csd
screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"
animations { ... }
window-rule { match app-id=r#"^org\.gnome\."#  draw-border-with-background false  geometry-corner-radius 12  clip-to-geometry true }
window-rule { ... org.gnome.Calculator/gnome-calculator/org.gnome.Nautilus ... open-floating true }
window-rule { ... com.mitchellh.ghostty ... draw-border-with-background false }
recent-windows { binds { Alt+Tab / Alt+Shift+Tab / Alt+grave ... } }
include optional=true "dms/colors.kdl"
include optional=true "dms/layout.kdl"
include optional=true "dms/alttab.kdl"
include optional=true "dms/binds.kdl"       ← {{TERMINAL_COMMAND}} → ghostty (Mod+T)
include optional=true "dms/outputs.kdl"
include optional=true "dms/cursor.kdl"
include optional=true "dms/input.kdl"
```

Keybindings come from `embedded/niri-binds.kdl` (included above): Mod+T terminal, Mod+Space spotlight, Print screenshots via `dms screenshot`, Mod+O/Mod+Tab overview, media keys via `dms ipc call audio ...`, Mod+Q close etc. **No `spawn-at-startup "dms"`** — systemd mode (see §1.6). Keep `spawn-at-startup` free for light utilities only (e.g. `swaybg` — though DMS draws its own wallpaper, skip swaybg; tunaOS's *non-DMS* default config uses swaybg/waybar/swaync but that's their other flavor).

For pluto: copy the DMS embedded fragments verbatim into `custom/config/.config/niri/` (config.kdl + dms/*.kdl with `{{TERMINAL_COMMAND}}`→`ghostty`), or ship only config.kdl + dms/binds.kdl + empty dms/*.kdl (deployer semantics: non-empty fragments are user-owned; empty ones are created at `dms setup`). Note the /etc/skel seeding means a later `dankinstall`/`dms setup` run sees an existing config → it backs it up and replaces (with `--replace-configs` semantics) — acceptable, but document it.

### 4.2 ghostty config

DMS's deployed default (`embedded/ghostty.conf` + `ghostty-colors.conf`):
- `font-size = 12`, `window-decoration = false`, `window-padding-x/y = 12`, `background-blur-radius = 32` (needs niri blur), cursor block blink, `scrollback-limit = 3023`, `shell-integration = detect`, `gtk-single-instance = true`, keybinds (ctrl+shift+n new window, ctrl+t new tab, font-size binds), `theme = dankcolors` → `~/.config/ghostty/themes/dankcolors` (DankMaterial palette, `background = #101418` etc.).
- Zirconium/bluefin do **not** ship ghostty (zirconium default terminals list = `footclient.desktop`; bluefin = `org.gnome.Ptyxis.desktop`); DMS's ghostty config is therefore the only reference and the right one, since pluto's terminal is ghostty.
- Also set `/etc/skel/.config/ghostty/config` + `themes/dankcolors`; **do not** put the DMS theme file in `/usr/share` — ghostty theme resolution also includes `/usr/share/ghostty/themes` (valid option), but matching DMS's layout keeps `dms setup` idempotent.

### 4.3 Greeter cache/state symlinks (optional)

Zirconium ships `usr/lib/tmpfiles.d/99-dms-greeter.conf` symlinking themed settings/state into `/var/cache/dms-greeter/`:
```
L /var/cache/dms-greeter/settings.json - greeter greeter - /usr/share/zirconium/zdots/.../settings.json
```
(with an intentionally empty zdots dir at build — tunaOS notes the symlinks dangle and greeter falls back to defaults). **Recommendation: skip on pluto** — the dms-greeter RPM's own tmpfiles already creates `/var/cache/dms-greeter`, and defaults are fine.

---

## 5. Implementation map (pluto files)

- `build/packages/niri.toml` (new) — `[fedora]` native set (§2.2), `["copr:avengemedia/danklinux"]` = quickshell + dms-greeter + dgop + matugen (+ danksearch), `["copr:avengemedia/dms"]` = dms + dms-cli, optionally `["copr:yalter/niri"]` (only if skipping Fedora's niri) with priority=1 handling, optional terra for satty/valent/iio-niri. *Decision note:* 20-base.sh keeps COPRs enabled for runtime updates; AGENTS.md rule 3 prefers `copr_install_isolated`. Pick one per layer and document.
- `build/40-niri.sh` (new) — bake `/etc/greetd/config.toml`, `/etc/greetd/niri/config.kdl` (empty), `/usr/lib/pam.d/greetd-spawn`, `/usr/share/greetd/greetd-spawn.pam_env.conf`, greetd pam gnome-keyring fix, `/usr/lib/systemd/user-preset/01-pluto-niri.preset` (`enable dms.service`), optional dms.service.d override, `glib-compile-schemas`.
- `custom/config/` — /etc/skel: `.config/niri/config.kdl` + `dms/*.kdl`, `.config/ghostty/config` + `themes/dankcolors`, `.config/environment.d/90-dms.conf`.
- `custom/flatpaks/default.preinstall` — enable §2.2 table (uncomment), plus ensure `flatpak-preinstall.service` enabled (20-base.sh or 40-niri.sh).
- `custom/config/.local/share/flatpak/overrides/` + `usr/lib/tmpfiles.d/*.conf` L-lines / `/usr/share/ublue-os/flatpak-overrides/` — §3.4 overrides.
- Greeter user: comes from dms-greeter RPM (sysusers + tmpfiles) — no manual sysusers needed.

---

## 6. Could not verify

1. **Zirconium's actual user niri config / dotfiles** — the greeter settings + niri fragments ship from the separate `zdots` repo; the mkosi snapshot contains only an *intentionally empty* `/usr/share/zirconium/zdots/` (`install-zirconium.sh` comment). tunaOS's `/usr/share/niri/config.kdl` (their shipped default) is the non-DMS flavor (waybar/swaync/cliphist) and is NOT what the DMS variants use; DMS's embedded fragments are the only authoritative DMS config source.
2. **`/etc/flatpak/overrides`** — verified NOT read by flatpak (source-cited above); anyone recommending it is wrong unless they also ship the tmpfiles/L mechanism.
3. **Ghostty availability in Fedora F43** — packages.fedoraproject.org returns no fc4x builds (only F41+ effort); base.toml already routes `scottames/ghostty` COPR which is correct; unchanged.
4. **exact niri version shipped in Fedora F43 vs yalter/niri** — the fc43 build exists (page lists fc43–fc45) but the version number wasn't retrievable from the static page; if freshness matters use the yalter COPR (`priority=1`) as both reference images do.
5. **`dms-greeter install` end-to-end on Fedora** — the installer code path was read, but no Fedora run output exists in the clones; baking the greetd config per the zirconium pattern (instead of running `dms-greeter install` at first boot) sidesteps it entirely.
6. **Bazaar's `/usr/share/ublue-os/flatpak-overrides` consumer** — the bluefin tmpfiles L-line creates the symlink; whether Bazaar also *writes* its own override is not verifiable from the clones (the application may re-apply it via its extension; harmless either way).
7. **quickshell stable vs -git on F43** — DMS requires ≥0.2.0; the danklinux COPR's stable `quickshell` build for F43 was not inspected. tunaOS ships `quickshell-git`; zirconium ships stable. If the shell fails to start on first boot, switch to `quickshell-git`.
