# projectbluefin/common — Comprehensive Map

> Generated: 2026-08-29
> Source: `ghcr.io/projectbluefin/common` — `726e853 fix(report): read the boot-time booted-image snapshot when bootc status fails (#1030)`
> Clone: `/tmp/opencode/common` (depth 1, 2026-08-29)
> Purpose: inventory every file common ships, split by **shared** vs **bluefin** vs **nvidia**, and answer 4 consumption questions for pluto.

---

## 1. Top-level directory tree

```
common/
├── Containerfile                      # 4-stage: umotd-build, uwelcome-build, build, scratch ctx
├── Justfile                           # check/fix/test/bazaar-preview/build/overlay helpers
├── README.md                          # "bluefin-common" layout + flatpak/brew usage
├── system_files/README.md             # canonical layer semantics (shared/bluefin/nvidia)
├── system_files/shared/               # → /system_files/shared/ in OCI (ANY downstream fork)
├── system_files/bluefin/              # → /system_files/bluefin/ in OCI (GNOME only)
├── system_files/nvidia/               # → /system_files/nvidia/ in OCI (NVIDIA variant only)
├── bluefin-branding/                  # git submodule — Bazaar banner JXL sources
├── scripts/                           # check-doc-links.sh, check-oci-refs.py, check-skill-*.sh
├── docs/                              # skills + contributing docs
├── specs/                             # product specs
└── tests/                             # bats + pytest suites
```

Containerfile build stages (all verified in `common/Containerfile`):

| Stage | Base | What it does |
|-------|------|--------------|
| `umotd-build` | `golang:alpine` | builds `umotd` from `projectbluefin/umotd@c9df8ec` → `/umotd` |
| `uwelcome-build` | `golang:alpine` | builds `uwelcome` from `projectbluefin/uwelcome@5280521` → `/uwelcome` |
| `build` | `alpine:latest` | fetches wallpapers, just completions, game-devices-udev rules, YubiKey 70-u2f.rules, converts Bazaar JXL→PNG |
| `scratch ctx` | `scratch` | final OCI layout: `COPY /system_files/shared /system_files/shared/`, `COPY /bluefin-branding/system_files /system_files/bluefin`, etc + `COPY --from=build /out/...` |

The final image has **no** `/` root — only `/system_files/{shared,bluefin,nvidia}/` subtrees. Downstreams `COPY --from=common /system_files /oci/common`.

---

## 2. Shared side — `/system_files/shared/` (rsynced to `/` on any fork)

> Files shared with **Aurora** — Aurora cherry-picks commits touching `shared/`. Rule: any file whose absence would degrade *any* variant.

### 2a. Just recipes — `usr/share/ublue-os/just/`

| File | Imported via | Contents |
|------|--------------|----------|
| `apps.just` | `00-entry.just` → shared | `install-jetbrains-toolbox`, `install-opentabletdriver` (udev + modprobe + flatpak), `cncf`, `install-asus` |
| `default.just` | `00-entry.just` | `bios`, `bios-info`, `clean-system` (podman/docker + flatpak + rpm-ostree + brew), `logs-this-boot/last-boot`, `enroll-secure-boot-key`, `toggle-user-motd` (uwelcome shim), `check-local-overrides`, `device-info`, `check-idle-power-draw`, `benchmark` |
| `shared.just` | `00-entry.just` | `toggle-tpm2` (luks-tpm2-autounlock), `powerwash` (bootc reset) |
| `update.just` | `00-entry.just` | `update`/`upgrade` (uupd vs rpm-ostree auto, bctl delegate, bootc+flatpak+brew), `toggle-updates`/`auto-update` |
| _(entry)_ | `bluefin/usr/share/ublue-os/just/00-entry.just` **not** in shared — see §3a | Entry point lives in bluefin layer |

> Pluto currently rsyncs all of shared but only cherry-picks `00-entry.just` from bluefin — so `apps.just`/`default.just`/etc **are** available after pluto's `10-build.sh`.

### 2b. Binaries & libexec — `usr/bin/` + `usr/libexec/`

| Path | What it is | Notes |
|------|------------|-------|
| `usr/bin/ujust` | wrapper: `exec just --justfile /usr/share/ublue-os/just/00-entry.just` + auto-installs fzf via brew if `--choose` needed | **Requires** `00-entry.just` at that path |
| `usr/bin/brew-preinstall` | shim → `/usr/libexec/brew-preinstall` | user unit entrypoint |
| `usr/bin/luks-tpm2-autounlock` | TPM2 LUKS helper (toggled by `shared.just:toggle-tpm2`) | Sources `gum` prompt, uses `CMDLINE_FILE`/`DISK_BY_UUID_DIR` overrides for testing |
| `usr/bin/rechunker-group-fix` | fixes `/etc/gshadow` after legacy rechunker | called by `rechunker-group-fix.service` |
| `usr/bin/ublue-bling` | toggles `bling.sh`/`bling.fish` in `~/.bashrc`/`.zshrc`/`fish/config.fish` | uses `ublue-bling-fastfetch` for color |
| `usr/bin/ublue-bling-fastfetch` | prints `38;2;…` color from dconf accent | called by `ublue-fastfetch` |
| `usr/bin/ublue-fastfetch` | `exec fastfetch` with logo/config from `/etc/ublue-os/fastfetch.json` + `/usr/share/ublue-os/fastfetch.jsonc` | honors `FASTFETCH_FORCE_THEME`, `shuffle-logo` |
| `usr/bin/ublue-image-info.sh` | prints `name:tag 🔐/🔓` from `image-info.json` + `bootc status` | used by PS1? |
| `usr/bin/ublue-privileged-setup`, `ublue-system-setup`, `ublue-user-setup` | hook runners: iterate `*.hooks.d` dirs | config from `/etc/ublue-os/setup.json` or fallback paths |
| `usr/libexec/bootc-update-stage` | pkexec-locked helper for ChairLift: `exec bootc upgrade` (no flags) | polkit `exec.path` pinned to this absolute path |
| `usr/libexec/brew-preinstall` | content-hash-driven brew bundler: reads `preinstall.d/*.Brewfile`, compares sha256 to `~/.local/share/ublue-os/brew-preinstall-state.json`, installs/removes delta | state = `{hash,packages,casks}` |

Built binaries copied from build stages:

| Path | Source |
|------|--------|
| `usr/bin/umotd` | `umotd-build:/umotd` |
| `usr/bin/uwelcome` | `uwelcome-build:/uwelcome` |
| `usr/share/bash-completion/completions/ujust`, `…/zsh/site-functions/_ujust`, `…/fish/vendor_completions.d/ujust.fish` | `build` stage runs `just --completions … | sed s/just/ujust/` |

### 2c. systemd — `usr/lib/systemd/{system,user}/`

**System units** (`system/`):

| Unit | Type | Purpose | Preset? |
|------|------|---------|---------|
| `flatpak-preinstall.service` | `oneshot` | `flatpak preinstall -y` (consumes `/usr/share/flatpak/preinstall.d/*.preinstall`) | **NO preset** — consumer must `systemctl enable` it |
| `flatpak-appstream-refresh.service` | `oneshot` | `flatpak update --appstream` (metered-aware, Restart=on-failure) | `02-flatpak-appstream-refresh.preset` → `enable` |
| `rechunker-group-fix.service` | `oneshot` | `/etc/gshadow` fix + `systemd-sysusers` + `rechunker-group-fix` + `systemd-tmpfiles` | `00-rechunker-group-fix.preset` |
| `ublue-system-setup.service` | `simple` | `ExecStart=/usr/bin/ublue-system-setup` | — |
| `uupd.timer` + `uupd.service.d/10-bluefin.conf` + `uupd-on-ac.service` | timer+service | auto-update every 6h (00,06,12,18 + 10m jitter), AC-trigger | `01-uupd.preset` → `enable uupd.timer` |
| `dconf-update.service` | — | **NOT here** — lives in bluefin (see §3c) | — |

**User units** (`user/`):

| Unit | Purpose | Preset |
|------|---------|--------|
| `brew-preinstall.service` | `brew-preinstall` at `graphical-session.target`, `ConditionUser=!@system`, `IOWeight=10` | `01-brew-preinstall.preset` → `enable` |
| `ublue-user-setup.service` | `ExecStart=/usr/bin/ublue-user-setup` | (wanted by `graphical-session.target`, no preset — enabled via? relies on preset-all + WantedBy) |

**Presets shipped:**

```
system-preset/00-rechunker-group-fix.preset     → enable rechunker-group-fix.service
system-preset/01-uupd.preset                    → enable uupd.timer
system-preset/02-flatpak-appstream-refresh.preset → enable flatpak-appstream-refresh.service
user-preset/01-brew-preinstall.preset           → enable brew-preinstall.service
```

> `flatpak-preinstall.service` intentionally has no preset; `10-build.sh` does `systemctl enable` explicitly.

**Other systemd-adjacent:**

- `usr/lib/systemd/system/uupd.service.d/10-bluefin.conf` — `ConditionACPower=true` drop-in for uupd
- `usr/lib/systemd/system-preset/` + `usr/lib/systemd/user-preset/` — as above

### 2d. udev rules — `usr/lib/udev/rules.d/`

| File | Hardware |
|------|----------|
| `10-switch.rules` | NVIDIA APX (Switch RCM) → group `nintendo_switch` |
| `50-framework16.rules` | Framework 16 |
| `50-steam-horipad-controller.rules` | HoriPad |
| `50-usb-realtek-net.rules` | Realtek USB NIC |
| `50-zsa.rules` | ZSA keyboards |
| `60-amd-s2idle-fixes.rules` | AMD s2idle |
| `60-arduino-mbed.rules` | Arduino Mbed |
| `70-titan-key.rules` | Titan Security Key |
| `70-wooting.rules` | Wooting keyboards |
| `71-*-gdu.rules` (27 files) | game-devices-udev (per-file SHA256-pinned curl from Codeberg) |
| `70-u2f.rules` | YubiKey libfido2 (SHA256-pinned raw fetch) |
| `88-neutron_hifi_dac.rules` | Neutron HiFi DAC |
| `90-apple-superdrive.rules` | Apple SuperDrive |
| `92-viia.rules` | VIIA |
| `99-uupd-on-ac.rules` | `ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1" → systemctl start uupd-on-ac.service` |

### 2e. OEM / hooks — `usr/share/ublue-os/`

| Path | Contents |
|------|----------|
| `oem/ASUS/` | `logo`, `packages.Brewfile` (`asusctl`, `rog-control-center`) |
| `oem/Framework/` | `logo`, `packages.Brewfile` (`framework_tool`, `framework-wallpapers`), `51-framework-desktop.conf` (wireplumber) |
| `system-setup.hooks.d/10-framework.sh` | DMI-gated (Framework): hid_sensor_hub karg cleanup, Framework 13 audio/suspend fixes |
| `system-setup.hooks.d/11-asus.sh` | DMI `sys_vendor ~ ASUS`, enables `asusd.service` |
| `user-setup.hooks.d/10-theming.sh` | sets `natural-scroll`, font scaling, Ampere logo via `dconf`/`version-script` |
| `user-setup.hooks.d/20-oem-brew.sh` | brew bundle from `oem/<Vendor>/packages.Brewfile` + logo + `asusd-user.service` |
| `lib/ublue/setup-services/libsetup.sh` | `version-script <name> <user|system|privileged> <ver>` — flock-protected JSON at `~/.local/share/ublue/setup_versioning.json` |

### 2f. Brewfiles — `usr/share/ublue-os/homebrew/`

Curated bundles via `bbrew`/`brew bundle`:

| Brewfile | Kind | Highlights |
|----------|------|------------|
| `preinstall.d/bluefinctl.Brewfile` | preinstall | `bluefinctl` (projectbluefin tap) |
| `preinstall.d/chairlift.Brewfile` | preinstall | `chairlift` (frostyard tap) — UI for system maintenance |
| `preinstall.d/system-cli.Brewfile` | preinstall | fzf, glow, htop, starship, tmux, restic, rclone, ykman, squashfs, tcpdump |
| `ai-tools.Brewfile` | opt-in | opencode, goose, llm, ramalama, lm-studio, jan |
| `artwork.Brewfile` | opt-in | wallpaper casks |
| `cli.Brewfile` | opt-in | atuin, bat, eza, fd, ripgrep, yq, zoxide, mise |
| `cncf.Brewfile` | opt-in | ~89 formulas (argo, helm, linkerd, etc) + Headlamp/OpenLens/Podman Desktop flatpaks |
| `experimental-ide.Brewfile` | opt-in | cursor, JB IDEs via experimental tap |
| `fonts.Brewfile` | opt-in | Opendyslexic, MS fonts, ubuntu, roboto |
| `fonts-dev.Brewfile` | opt-in | nerd-fonts |
| `ide.Brewfile` | opt-in | vscode, vscodium, neovim, micro, helix, devcontainer |
| `k8s-tools.Brewfile` | opt-in | k9s, helm, kind, kubectl, rancher |
| `swift.Brewfile` | opt-in | swiftly |

`brew-preinstall.service` auto-applies only the `preinstall.d/` subset at first login (hash-tracked).

### 2g. Flatpak & container plumbing

| Path | Purpose |
|------|---------|
| `etc/containers/policy.json` | sigstore for `ghcr.io/ublue-os` + `quay.io/toolbx-images`, otherwise `insecureAcceptAnything` |
| `etc/containers/registries.d/*.yaml` | toolbx + ublue registry configs |
| `usr/lib/pki/containers/*.pub` | signing keys for the above |
| _(no shared flatpak overrides)_ | overrides live in bluefin |

### 2h. Shell / terminal integration

| Path | Purpose |
|------|---------|
| `etc/profile.d/caffeinate.sh` | `caffeinate()` — `systemd-inhibit` helper |
| `etc/profile.d/ublue-fastfetch.sh` | `alias fastfetch/neofetch/neowofetch=ublue-fastfetch` |
| `etc/profile.d/uwelcome.sh` | migrates `~/.config/no-show-user-motd` → `uwelcome/disabled` + runs `uwelcome` |
| `usr/share/ublue-os/bling/bling.sh` | bash `ls`/`grep`/`cat` aliases (eza, ugrep, bat), direnv+bash-preexec ordering |
| `usr/share/ublue-os/bling/bling.fish` | fish equivalent |
| `usr/share/fish/vendor_conf.d/fish_greeting.fish` | shows `uwelcome` on fish start, migrates motd flag |
| `usr/share/fish/vendor_conf.d/starship.fish` | `starship init fish | source` if present |
| `usr/share/fish/vendor_conf.d/ublue-fastfetch.fish` | fish alias for fastfetch |
| _(zsh plumbing)_ | **NOT** in shared — `etc/zsh/*` lives in bluefin |

### 2i. Config / defaults

| Path | Purpose |
|------|---------|
| `etc/skel/.config/ghostty/config.ghostty` | Ghostty defaults (Catppuccin Mocha, single-instance, 132×36, notify-on-finish) |
| `etc/ublue-os/tags.json` | `["bluefin","gnome"]` |
| `etc/uupd/config.json` | `{"modules":{"distrobox":{"disable":true}}}` |
| `etc/uwelcome/config.json` | uwelcome: greeting "󱍢 ", links (issues/ask/docs), motd=`umotd`, commands=`ujust --choose` etc |
| `etc/geoclue/conf.d/99-beacondb.conf` | `url=https://api.beacondb.net/v1/geolocate` |
| `usr/share/chairlift/config.yml` | ChairLift maintainer defaults (system/updates/apps/maintenance/help pages, strict schema) |
| `usr/share/polkit-1/actions/org.frostyard.ChairLift.bootc.policy` | `ChairLift.bootc.stage → /usr/libexec/bootc-update-stage auth_admin` |
| `usr/share/polkit-1/actions/org.ublue.privileged.user.setup.policy` + `rules.d/*.rules` | privileged setup polkit |
| `usr/share/polkit-1/rules.d/org.debian.pcsc-lite.access_card.rules` | pcsc-lite |
| `usr/share/color/icc/colord/framework*.icc` | Framework display ICC profiles |
| `usr/share/icons/.../ampere-logo-symbolic.svg`, `framework-logo-symbolic.svg`, `asus-rog-symbolic.svg`, `ChairLift*` | OEM/ChairLift icons |
| `usr/share/pipewire/pipewire-pulse.conf.d/50-bluefin-bt-switch.conf` | `module-switch-on-connect` (BT auto-switch + A2DP preference) |
| `usr/lib/modprobe.d/amd-legacy.conf` | `amdgpu si/cik_support=1, radeon …=0` |
| `usr/share/applications/org.frostyard.ChairLift.desktop` | vendored ChairLift desktop entry (Exec=/home/linuxbrew/.../chairlift-wrapper) |

---

## 3. Bluefin side — `/system_files/bluefin/` (GNOME only — NOT rsynced by pluto today)

> Rule: GNOME theming, Bluefin branding, GNOME Shell extensions, gom-specific services.

### 3a. Just recipes

| File | Purpose |
|------|---------|
| `usr/share/ublue-os/just/00-entry.just` | **Entry point** for `ujust` — sets `allow-duplicate-recipes`, `ignore-comments`, defines `_default` (prints docs link + `ujust --list`), then `import`s apps/default/shared/update/system/changelog/60-bonedigger + `import? 60-custom.just` |
| `usr/share/ublue-os/just/60-bonedigger.just` | `report` → `/usr/libexec/bonedigger-report` (`BONEDIGGER_BRAND="🫐 Bluefin Bug Report"`, v0.2.0) |
| `usr/share/ublue-os/just/changelog.just` | `changelogs` → `bctl changelogs` else GitHub Releases (row `image-name` dakota/lts/bluefin, tag gts/stable/lts) |
| `usr/share/ublue-os/just/system.just` | `bluefin-cli` (bling toggle + `cli.Brewfile`), `devmode`/`toggle-devmode` (Docker/podman/VM/lima/incus/IDEs/editors via brew+flatpak + groups), `toggle-testing`, `setup-vms`/`toggle-vms`, `install-system-flatpaks`/`bluefin-apps` (bctl delegate + `system-flatpaks.Brewfile`), `bazaar-preview`, `check-sb-key` |
| _(flutter.just)_ | optional import via `import?` if present (not in current tree) |

### 3b. Brewfiles (bluefin-only flatpak lists via brew)

| File | Entries |
|------|---------|
| `usr/share/ublue-os/homebrew/system-flatpaks.Brewfile` | 37 flatpaks (Firefox, Thunderbird, GNOME apps, Bazaar, MissionCenter, Flatseal, Warehouse, …) — consumed by `install-system-flatpaks` |
| `usr/share/ublue-os/homebrew/system-dx-flatpaks.Brewfile` | 6 DX flatpaks (Podman Desktop, Builder, DevToolbox …) |
| `usr/share/ublue-os/homebrew/full-desktop.Brewfile` | ~60 GNOME Circle flatpaks (Fotema, Dialect, Rnote, Health, PikaBackup, …) |

### 3c. systemd

| Path | Purpose |
|------|---------|
| `usr/lib/systemd/system/dconf-update.service` | `ExecStart=/usr/bin/dconf update` → `WantedBy=multi-user.target` |
| `usr/lib/systemd/user/bazaar.service` | `flatpak run …Bazaar --no-window` at `graphical-session.target` |
| `usr/lib/systemd/user/bluefin-dynamic-wallpaper.service` + `.timer` | monthly wallpaper rotation via `/usr/libexec/bluefin-dynamic-wallpaper` (geoclue latitude → hemisphere-season logic, respects user wallpaper) |
| `usr/lib/tmpfiles.d/bazaar-flatpak.conf` | tmpfiles for Bazaar |
| _(user preset)_ | `bazaar.service` and `bluefin-dynamic-wallpaper.timer` use `WantedBy=graphical-session.target` |
| _(dconf-update preset)_ | relies on `systemctl preset-all` (same as shared) |

### 3d. Shell / zsh

```
etc/zsh/zlogin | zlogout | zprofile | zshenv | zshrc
usr/share/fish/vendor_functions.d/fish_prompt.fish   (container-aware prompt)
etc/environment                                      (GNOME_SHELL_SLOWDOWN_FACTOR=0.8)
usr/share/ublue-os/bling/env.sh                     (BLING_MESSAGE_ENABLE/DISABLE)
```

### 3e. GNOME / dconf / theming

| Path | Purpose |
|------|---------|
| `etc/dconf/db/distro.d/01-bluefin-folders` | app-folder definitions (GamingUtilities, Utilities, Games, Containers, Wine) |
| `…/02-bluefin-keybindings` | media-keys custom bindings |
| `…/03-bluefin-ptyxis-palette` | Ptyxis catppuccin palette |
| `…/04-bluefin-custom-command-menu` | custom-command-list menu |
| `…/05-bluefin-searchlight-extension` | searchlight |
| `…/locks/01-bluefin-locked-settings` | locked dconf keys |
| `usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override` | gschema override: favorite-apps, enabled-extensions, background, interface, mutter, filechooser, ptyxis, etc |
| `etc/skel/.config/Code/User/settings.json` | VS Code defaults |
| `etc/skel/.local/share/flatpak/overrides/com.google.Chrome` | Chrome wayland + dirs override |
| `etc/skel/.local/share/flatpak/overrides/com.visualstudio.code` | Code wayland + podman socket override |
| `etc/skel/.local/share/org.gnome.Ptyxis/palettes/catppuccin-dynamic.palette` | Ptyxis palette |

### 3f. Bazaar app store

| Path | Purpose |
|------|---------|
| `etc/bazaar/{bazaar,curated,blocklist}.yaml` | Bazaar config (curated feed + blocklist) |
| `etc/bazaar/hooks.py` is **not** in bluefin — `bluefin-branding/system_files/etc/bazaar/*.jxl` are JXL banners converted at build → `/system_files/bluefin/etc/bazaar/*.png` (Containerfile: `djxl … --color_space=sRGB`) |
| `usr/libexec/bazaar-hook` | python3 hook: `stage==setup` jetbrains detection, `spawn_ujust`, `spawn_brew` via `flatpak-spawn --host xdg-terminal-exec` |
| `usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar` | `filesystems=host-etc` |
| `usr/share/flatpak/preinstall.d/bazaar.preinstall` | `[Flatpak Preinstall io.github.kolunmi.Bazaar] Branch=stable` (comment warns removal uninstalls Bazaar) |

### 3g. Scripts / helpers

| Path | Purpose |
|------|---------|
| `usr/libexec/bluefin-dynamic-wallpaper` | picks `/usr/share/backgrounds/bluefin/MM-bluefin.xml` by month + geoclue latitude hemisphere flip |
| `usr/libexec/get-geoclue-latitude` | gdbus GeoClue2 client (30s timeout, respects denied/disabled → exit 2) |
| `usr/libexec/bonedigger-report` | privacy-respecting bug report collector (baseline ≤64KiB, profile ≤500KiB, bundle ≤2MiB, gh issue creation) |
| `usr/libexec/ensure-libvirt-session-config` | `mkdir -p ~/.config/libvirt; echo 'uri_default = "qemu:///session"' >> libvirt.conf` |
| `usr/lib/dracut/dracut.conf.d/90-passkeys-tpm.conf` | passkeys-TPM dracut config |
| `etc/ublue-os/fastfetch.json` | fastfetch defaults for bluefin (slate theme, shuffle-logo?) |
| `usr/share/ublue-os/fastfetch.jsonc` | fastfetch.jsonc variant |
| `usr/share/ublue-os/firefox-config/01-bluefin-global.js` | `webrender.all=true, hardware-video-decoding=true` |
| `usr/share/ublue-os/otel/ujust-report-config.yaml` | OTel for ujust-report |
| `usr/share/ublue-os/user-setup.hooks.d/20-dynamic-wallpaper.sh` | runs dynamic wallpaper on user-setup |
| `usr/share/xdg-terminal-exec/gnome-xdg-terminals.list` | `org.gnome.Ptyxis.desktop` |
| `etc/gnome-initial-setup/vendor.conf` | `skip=software` |
| `etc/xdg/mimeapps.list`, `etc/ublue-os/tags.json` (bluefin side?) | mime + tags |
| `etc/ublue-os/fastfetch.json` | bluefin fastfetch config |

### 3h. Branding / assets

| Path | Purpose |
|------|---------|
| `usr/share/backgrounds/bluefin/*.xml + *.jxl` (via Containerfile) | monthly bluefin wallpapers + GNOME background properties |
| `usr/share/ublue-os/bluefin-logos/{bluefin,chicken,dolly,karl}.{png,sixels/*,symbols/*}` | logos for fastfetch/motd |
| `usr/share/icons/.../ublue-logo-symbolic.svg`, `ublue-discourse.svg`, etc | icons |
| `usr/share/pixmaps/faces/bluefin/*.jpg` (15 faces) | user avatar faces |
| `usr/share/pixmaps/fedora-*.png`, `system-logo-white.png`, `plymouth/...` | fedora/plymouth branding |

---

## 4. Nvidia side — `/system_files/nvidia/` (NVIDIA variant only)

| File | Purpose |
|------|---------|
| `usr/lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service` | sync NVIDIA flatpak runtime |
| `usr/libexec/ublue-nvidia-flatpak-runtime-sync` | helper script |

> Ignorable for pluto (no NVIDIA image).

---

## 5. How pluto currently consumes common

Refs are to `pluto/Containerfile` and `pluto/build/10-build.sh`.

### 5a. OCI stage wiring — `Containerfile:39-50`

```dockerfile
# Containerfile:39
FROM ghcr.io/projectbluefin/common:latest@sha256:44c7c59… AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:5c5b6dea… AS brew
FROM scratch AS ctx
COPY build /build
COPY custom /custom
COPY --from=common /system_files /oci/common    # Containerfile:49
COPY --from=brew /system_files /oci/brew        # Containerfile:50
```

The `scratch` ctx aggregates local + OCI trees, then each `RUN --mount=type=bind,from=ctx,source=/,target=/ctx` makes them visible at `/ctx/...`.

### 5b. Overlay & wiring — `build/10-build.sh` (full rsync strategy)

| Step | Command | What it brings |
|------|---------|----------------|
| Brew overlay | `rsync -rvKl /ctx/oci/brew/ /` | Homebrew tarball + brew services + profile.d |
| Shared overlay | `rsync -rvKl /ctx/oci/common/shared/ /` | Everything in §2 |
| Bluefin cherry-pick | `install -Dm0644 /ctx/oci/common/bluefin/.../00-entry.just /usr/share/ublue-os/just/00-entry.just` | Only entry point, nothing else from bluefin |
| Presets | `systemctl preset-all` + `systemctl --global preset-all` | enables uupd.timer, rechunker, flatpak-appstream, brew-preinstall |
| Explicit enable | `systemctl enable flatpak-preinstall.service` | Required because it has no preset |
| Brew preinstall | `cp /ctx/custom/brew/*.Brewfile → /usr/share/ublue-os/homebrew/preinstall.d/` | Every pluto Brewfile auto-installed at first login |
| Justfiles | `find /ctx/custom/ujust -name '*.just' | cat >> /usr/share/ublue-os/just/60-custom.just` | Consolidates pluto's recipes alongside ujust entry |
| Flatpak preinstall | `cp /ctx/custom/flatpaks/*.preinstall → /usr/share/flatpak/preinstall.d/` | Consumed by `flatpak-preinstall.service` |
| System files | `rsync -rvKl /ctx/custom/files/ /` | greetd, PAM, systemd presets/wants, gschema, xdg-terminal-exec |
| Skel | `rsync -rvKl /ctx/custom/config/ /etc/skel/` | `~/.config/niri`, `ghostty`, `environment.d/90-dms.conf` — wins over common's ghostty |

Other relevant pluto files:

- `build/00-image-info.sh` — writes `/usr/share/ublue-os/image-info.json` (`image-name`, `image-vendor`, `image-tag`, `base-image-name`, `fedora-version`) + patches `/usr/lib/os-release`; consumes `ARG IMAGE_NAME/VENDOR/UBLUE_IMAGE_TAG/BASE_IMAGE_NAME/FEDORA_MAJOR_VERSION/VERSION` from Containerfile.
- `build/20-base.sh` + `build/packages/base.toml` — wm-agnostic desktop foundation (fonts, portals, flatpak, greetd, zram, power-profiles-daemon).
- `build/25-multimedia.sh` + `build/packages/multimedia.toml` — negativo17 fedora-multimedia with vendor assert.
- `build/40-niri.sh` + `build/packages/niri.toml` + `custom/files/` — niri/DMS stack, greeter, flatpak-theming.service, gschema, `preset-all --global` for DMS.
- `build/clean-stage.sh` — `keepcache=0`, `versionlock clear`, disables `flatpak-add-fedora-repos.service`, cleans `/var`/`/tmp`/`/boot`/`/run` without EBUSY.

---

## 6. Answers to the 4 questions

### Q1 — Are we using common correctly?

**Yes, with one intentional divergence that is correct.**

- The `FROM …common AS common` + `COPY --from=common /system_files /oci/common` + `rsync /oci/common/shared/ /` pattern in `Containerfile:49` + `build/10-build.sh:34` is exactly the documented usage (`README.md` "Copy everything" / "Copy only …").
- Cherry-picking only `bluefin/…/00-entry.just` and not the whole `bluefin/` tree is the right call for a non-GNOME compositor (niri). The comment in `10-build.sh:17` ("bluefin/ layer is NOT rsynced — GNOME-specific — except 00-entry.just, which ujust requires") matches `system_files/README.md` layer semantics.
- `preset-all` + explicit `enable flatpak-preinstall.service` is the correct preset handling (flatpak-preinstall intentionally has no preset; the other three system units + brew user unit are preset-enabled).
- Brew and flatpak wiring (`custom/brew/*.Brewfile → preinstall.d/`, `custom/flatpaks/*.preinstall → /usr/share/flatpak/preinstall.d/`) correctly feeds the consumers that the shared overlay ships (`brew-preinstall.service`, `flatpak-preinstall.service`).

**Minor nit that does not break anything:** `10-build.sh` runs `systemctl --global preset-all` once in the shared section (`:56`) and again in `40-niri.sh` after DMS user units exist — the second run is *necessary* (comment in `40-niri.sh:47` explains ordering), but the first global preset does nothing useful for DMS at that point (units not yet installed). Harmless; just worth knowing the second invocation is the one that matters for pluto's DMS preset `custom/files/usr/lib/systemd/user-preset/90-pluto-dms.preset`.

**No misuse of `dnf5`/`copr`/`clean-stage` rules:** `pluto` keeps COPRs enabled only for install layers and disables them via `clean-stage.sh` (the script currently just cleans caches; COPR disabling is handled inline by the package helpers — check `build/scripts/package-lib.sh` for `dnf5 config-manager setopt *.enabled=0` if present; otherwise add it).

### Q2 — Are we doing duplicate work that common already provides?

**A few overlaps exist — most are intentional re-implementations for the niri stack, one is true duplication:**

| Area | Common provides | Pluto provides | Verdict |
|------|-----------------|----------------|---------|
| `dconf-update.service` | `bluefin/usr/lib/systemd/system/dconf-update.service` (`dconf update`, `WantedBy=multi-user.target`) | `custom/files/usr/lib/systemd/system/dconf-update.service` — identical unit (diff confirms same 7-line service) | **Duplicate** — delete `custom/files/usr/lib/systemd/system/dconf-update.service` and let the bluefin cherry-pick (or rsync of shared? actually this unit is bluefin-only, not shared) be the source. If you keep not rsyncing bluefin, you need this file; if you start rsyncing bluefin's `dconf-update.service` via a narrow cherry-pick like `00-entry.just`, you can remove it. Today you *do* need it because shared doesn't ship it. Keep it, but note it's not "free" from shared — it's a justified copy. |
| Gschema theming | `bluefin/.../zz0-bluefin-modifications.gschema.override` (GNOME theme/favorite-apps) | `custom/files/usr/share/glib-2.0/schemas/zz0-pluto-theme.gschema.override` (3 lines: `prefer-dark`, `adw-gtk3`, `Adwaita`) | **Not duplicate** — pluto's override is intentionally minimal (niri doesn't need GNOME dash/favorite-apps). Compiled by `glib-compile-schemas` in `40-niri.sh` — correct. |
| `xdg-terminal-exec` list | `bluefin: org.gnome.Ptyxis.desktop` | `custom/files: com.mitchellh.ghostty.desktop` | **Not duplicate** — correct niri replacement. |
| Flatpak theming service | none in shared (bluefin relies on GNOME theming propagation) | `custom/files/usr/lib/systemd/system/flatpak-theming.service` (`flatpak override --filesystem=xdg-data/themes` + wayland + mask) | **Pluto-only, correct** — niri has no GNOME theme bridge. |
| `brew-preinstall` / `flatpak-preinstall` | both shipped by shared | pluto wires `custom/brew` + `custom/flatpaks` into their `preinstall.d/` dirs | **Not duplicate** — correct consumer pattern. |
| ujust recipes | `default.just:benchmark`, `update.just:update` etc | `custom/ujust/custom-system.just:benchmark` (re-implements benchmark), `update-and-reboot`, `clean-containers` | **Partial duplicate**: `custom-system.just:benchmark` duplicates `shared/default.just:benchmark` (plus a slightly different guard). Recommend removing pluto's `benchmark` — the shared one is identical in behavior and `ujust benchmark` already works after the overlay. `update-and-reboot` and `clean-containers` are pluto-specific — keep. |
| `image-info.json` / `os-release` | not shipped by common (each image builds its own) | `build/00-image-info.sh` | **Not duplicate** — correct, each downstream owns its branding. Pattern matches `ublue-os/image-template:scripts/image-info.sh`. |
| `zram-generator.conf` + `power-profiles-daemon` | not in common (image-specific) | `build/20-base.sh` | **Not duplicate** — correctly in pluto. |

**Actionable dedup:** remove `custom/ujust/custom-system.just:benchmark` (keep the other recipes). The shared `benchmark` is already available via `ujust benchmark` after `10-build.sh`. Everything else is either correctly pluto-specific or a justified copy due to not rsyncing bluefin.

### Q3 — What can we just rsync from the bluefin side as well (useful justfiles)?

**Safe to rsync selectively — do NOT rsync all of bluefin (it's GNOME wallpaper + dconf that would fight niri):**

| Candidate | Source | What it adds | Conflict with niri? | Recommendation |
|-----------|--------|--------------|---------------------|---------------|
| `changelog.just` | `bluefin/usr/share/ublue-os/just/changelog.just` | `ujust changelogs` (bctl → GitHub Releases) | None — pluto already re-implements `changelogs` in `custom-system.just` (bctl → github siddhj2206/pluto). Common's version is more generic (handles dakota/lts/bluefin). | **Rsync it** — then delete pluto's `changelogs` recipe and let the common one serve all users (it reads `image-name`/`image-tag` from `image-info.json`, so it works for pluto too). Alternatively keep pluto's override in `60-custom.just` — `allow-duplicate-recipes` means pluto's wins when imported after; but cleaner to drop the duplicate. |
| `system.just` recipes individually | `bluefin/.../system.just` | `check-sb-key`, `bluefin-cli` (bling), `install-system-flatpaks`/`bluefin-apps`, `bazaar-preview`, `setup-vms`/`toggle-vms`, `toggle-devmode`/`devmode`, `toggle-testing` | **Mixed**: `check-sb-key` (harmless, useful), `bluefin-cli` (bling + `cli.Brewfile` — useful, but pluto's `system-cli` preinstall already has fzf/glow/htop/sh etc; still safe), `install-system-flatpaks` (would pull GNOME flatpaks — not wanted on niri), `setup-vms`/`toggle-vms` (flatpak-based VMs — actually useful for any desktop, niri included), `toggle-devmode` (bctl-gated, heavy: docker/podman/virt/lima/incus/IDEs — useful), `bazaar-preview` (Bazaar is GNOME app-store — not needed on niri), `toggle-testing` (generic — useful) | **Cherry-pick recipes, not whole file.** Best approach: copy the individual recipes you want into `custom-system.just` (you already did this informally) rather than rsyncing all of `system.just` and inheriting GNOME-only deps. If you want a one-liner, `install -Dm0644 bluefin/.../system.just /usr/share/ublue-os/just/bluefin-system.just` and `import` it from a custom `00-entry.just` variant — but the per-recipe copy is clearer. |
| `60-bonedigger.just` (+ `usr/libexec/bonedigger-report`) | `bluefin/.../60-bonedigger.just` + script | `ujust report` (bug report via `gh`) | None — requires `gh` (via brew) + `bonedigger-report` binary | **Rsync if you want bug reports** — `install -Dm0644 60-bonedigger.just …` + `install -Dm0755 bonedigger-report /usr/libexec/bonedigger-report`. Hardened script, privacy-reviewed. Useful for any downstream. |
| `dconf-update.service` | `bluefin/usr/lib/systemd/system/dconf-update.service` | `dconf update` on boot | None | **Already duplicated** — either delete pluto's copy and cherry-pick this one, or keep as-is. Don't rsync *and* keep duplicate. |
| Everything else in bluefin | wallpapers, icons, `zz0-bluefin-*.gschema`, `etc/dconf/`, `etc/zsh/*`, `etc/gnome-initial-setup/*`, `etc/environment` | GNOME theming | **Conflicts with niri** — wallpapers override DMS theming, dconf locks fight niri settings, zsh config fights ghostty, `GNOME_SHELL_SLOWDOWN_FACTOR` irrelevant | **Do NOT rsync.** |

**Minimal safe rsync addition (recommended):**

```bash
# in build/10-build.sh, alongside the 00-entry.just cherry-pick:
install -Dm0644 /ctx/oci/common/bluefin/usr/share/ublue-os/just/changelog.just \
	/usr/share/ublue-os/just/changelog.just
install -Dm0644 /ctx/oci/common/bluefin/usr/share/ublue-os/just/60-bonedigger.just \
	/usr/share/ublue-os/just/60-bonedigger.just
install -Dm0755 /ctx/oci/common/bluefin/usr/libexec/bonedigger-report \
	/usr/libexec/bonedigger-report
# also:
install -Dm0644 /ctx/oci/common/bluefin/usr/lib/systemd/system/dconf-update.service \
	/usr/lib/systemd/system/dconf-update.service  # then delete custom/files/.../dconf-update.service
```

Then adjust `00-entry.just` imports: the shipped `bluefin/00-entry.just` already `import`s `changelog.just` and `60-bonedigger.just` — but pluto's image *doesn't use* that entry's imports verbatim; `ujust` just runs `just --justfile /usr/share/ublue-os/just/00-entry.just`, and that file's `import` lines are absolute paths. After rsyncing the two files, the existing `00-entry.just` will find them automatically — no extra edit needed. Remove pluto's duplicate `changelogs` and `benchmark` from `60-custom.just`.

If you prefer zero bluefin rsync, the status quo is fine — you just retain two duplicated recipes.

### Q4 — Does anything from the shared side depend on files we made/need to make or on things from the bluefin side?

**Shared side self-contained except for two correct dependencies that pluto already satisfies:**

| Shared artifact | Dependency | Status in pluto |
|---|---|---|
| `ujust` (`usr/bin/ujust`) | **Hard requires** `bluefin/usr/share/ublue-os/just/00-entry.just` at `/usr/share/ublue-os/just/00-entry.just` (exec path is absolute). Shared does NOT ship its own entry — only bluefin does. | ✅ Satisfied — `10-build.sh:38` cherry-picks it. Without this line, `ujust` exits with "justfile not found". |
| `flatpak-preinstall.service` | Requires `/usr/share/flatpak/preinstall.d/*.preinstall` + a flatpak remote defined (`flathub` flatpak repo). | ✅ Satisfied — `10-build.sh:64` copies `custom/flatpaks/*.preinstall`, `20-base.sh` runs `flatpak remote-add flathub`. |
| `brew-preinstall.service` (user) | Requires `/home/linuxbrew/.linuxbrew/bin/brew` (installed via `ublue-os/brew` OCI) + `/usr/share/ublue-os/homebrew/preinstall.d/*.Brewfile` + `graphical-session.target` + `ublue-user-setup.service` ordering | ✅ Satisfied — brew OCI rsynced, Brewfiles copied, preset enabled, `graphical-session.target` exists. |
| `uupd.timer` + `uupd-on-ac.service` + `uupd.service.d/10-bluefin.conf` + `99-uupd-on-ac.rules` | Requires `uupd` binary/package (the updater daemon, from COPR `ublue-os/packages` on Bluefin). **Not** installed by common's `Containerfile` — shipped as an RPM downstream. Verified absent from pluto: `grep -ri uupd build/packages/*.toml` → 0 hits (checked 2026-08-29). `uupd.timer` is nonetheless `preset enable`'d and `99-uupd-on-ac.rules` will `systemctl start uupd-on-ac.service` on AC connect. | ⚠️ **Unsatisfied (inert, not broken)** — timer/rules are harmless when unit is absent (`systemctl is-enabled` returns disabled, `systemctl start` is a no-op for missing unit) but they are dead weight. **Fix:** either add `uupd` to `build/packages/base.toml` (COPR `ublue-os/packages`) + keep `etc/uupd/config.json` override, or mask/disable the timer: `systemctl disable uupd.timer; systemctl mask uupd-on-ac.service` + drop/replace the udev rule. Bluefin installs it; pluto currently silently carries the preset without the daemon. Decide whether you want background auto-updates (uupd) or manual-only (`bootc upgrade` via `ujust update`). |
| `rechunker-group-fix.service` | Requires `rechunker-group-fix` script + `systemd-sysusers` + `systemd-tmpfiles` + `/run/ostree-booted` condition | ✅ Satisfied — script is part of shared overlay, condition guards non-ostree. |
| `ublue-system-setup.service` / `ublue-user-setup.service` | Requires hook dirs + `libsetup.sh` versioning JSON at `~/.local/share/ublue/setup_versioning.json` | ✅ Satisfied — scripts + hooks all shipped by shared overlay. No pluto hook needed. OEM hooks (`10-framework.sh`, `11-asus.sh`, `20-oem-brew.sh`) auto-exit on non-matching DMI — zero cost. |
| `uwelcome.sh` / `fish_greeting.fish` / `starship.fish` / `bling` | Require `uwelcome`/`umotd` binaries (built in Containerfile) + `starship` (from `system-cli.Brewfile` via brew-preinstall) + ghostty skel | ✅ Satisfied — binaries are in shared `/usr/bin/`, starship arrives via brew-preinstall at first login, ghostty skel overridden correctly by pluto's rsync order (`custom/config` last). |
| `policy.json` + `pki/containers/*.pub` | No dependency — purely additive. | ✅ No pluto action needed. |
| `geoclue 99-beacondb.conf` | Requires `geoclue` service + `lib/udev/rules` already present | ✅ Satisfied — geoclue is typically in base; config is additive. |
| `chairlift` desktop + policy | Requires brew-preinstall's `chairlift.Brewfile` (frostyard tap) + `org.frostyard.ChairLift` policy | ✅ Satisfied — chairlift Brewfile is in shared preinstall.d and gets installed at first login. |
| `bluetooth pipewire conf` | Requires `pipewire` + `wireplumber` | ✅ Satisfied — pluto's base installs pipewire. |

**Bluefin-on-shared dependency (not triggered because pluto doesn't rsync bluefin):**

- `bluefin`'s `changelog.just`/`system.just` import `justfile()` relative paths and call `bctl`/`glow` — `bctl` is `bluefinctl` from `preinstall.d/bluefinctl.Brewfile` (shared preinstall, so present). `glow` is in shared `system-cli.Brewfile` — also present. No missing dep if you rsync `changelog.just`.

**One pluto-made dependency that shared does NOT need but you provide:**

- `custom/files/usr/lib/systemd/user-preset/90-pluto-dms.preset` enables `dms.service` — this is pluto's compositor autostart and is orthogonal to shared's `01-brew-preinstall.preset`. The second `systemctl --global preset-all` in `40-niri.sh` is required precisely because this preset's target (`dms.service`) only exists after `niri.toml` COPRs install it. Common has no knowledge of it — correct.

**No hidden shared→bluefin dependency** — shared never imports or execs anything under `/system_files/bluefin/`. The only direction is `ujust` (shared binary) → `00-entry.just` (bluefin entry) which pluto satisfies via cherry-pick. All other shared units/scripts read from `/etc`/`/usr` paths that shared itself populates.

---

## 7. Directory tree (complete, with file counts)

```
system_files/
├── shared/                              (≈ 95 files)
│   ├── etc/
│   │   ├── containers/policy.json
│   │   ├── containers/registries.d/{quay.io-toolbx-images.yaml, ublue-os.yaml}
│   │   ├── geoclue/conf.d/99-beacondb.conf
│   │   ├── profile.d/{caffeinate.sh, ublue-fastfetch.sh, uwelcome.sh}
│   │   ├── skel/.config/ghostty/config.ghostty
│   │   ├── ublue-os/tags.json
│   │   ├── uupd/config.json
│   │   └── uwelcome/config.json
│   ├── usr/bin/{brew-preinstall,luks-tpm2-autounlock,rechunker-group-fix,ublue-bling,ublue-bling-fastfetch,ublue-fastfetch,ublue-image-info.sh,ublue-privileged-setup,ublue-system-setup,ublue-user-setup,ujust,umotd,uwelcome}
│   ├── usr/libexec/{bootc-update-stage,brew-preinstall}
│   ├── usr/lib/{modprobe.d/amd-legacy.conf,pki/containers/*.pub,systemd/system/*,systemd/user/*,systemd/system-preset/*,systemd/user-preset/*,ublue/setup-services/libsetup.sh,udev/rules.d/*}
│   └── usr/share/{applications/ChairLift.desktop,chairlift/config.yml,color/icc/colord/*.icc,fish/vendor_conf.d/*.fish,icons/.../*.svg,pipewire/.../50-bluefin-bt-switch.conf,polkit-1/...,... ,ublue-os/{bling/*,homebrew/*.Brewfile,homebrew/preinstall.d/*.Brewfile,just/*.just,oem/*/*,system-setup.hooks.d/*,user-setup.hooks.d/*}}
│       + build-generated: usr/share/{bash-completion/completions/ujust,zsh/site-functions/_ujust,fish/vendor_completions.d/ujust.fish}
├── bluefin/                             (≈ 75 files + wallpapers)
│   ├── etc/{bazaar/*,dconf/db/distro.d/*,environment,gnome-initial-setup/vendor.conf,skel/{.config/Code/...,.local/share/flatpak/overrides/*,.local/share/org.gnome.Ptyxis/...},ublue-os/fastfetch.json,xdg/mimeapps.list,zsh/*}
│   └── usr/{lib/{dracut/.../90-passkeys-tpm.conf,systemd/system/dconf-update.service,systemd/user/{bazaar.service,bluefin-dynamic-wallpaper.*},tmpfiles.d/bazaar-flatpak.conf},libexec/{bazaar-hook,bluefin-dynamic-wallpaper,bonedigger-report,ensure-libvirt-session-config,get-geoclue-latitude},share/{applications/*.desktop,backgrounds/bluefin/*,flatpak/preinstall.d/bazaar.preinstall,flatpak-overrides/*,glib-2.0/schemas/zz0-bluefin-*.gschema.override,icons/.../*,pixmaps/faces/bluefin/*.jpg,plymouth/... ,ublue-os/{bling/env.sh,bluefin-logos/*,fastfetch.jsonc,firefox-config/*,homebrew/*.Brewfile,just/*.just,otel/*,user-setup.hooks.d/20-dynamic-wallpaper.sh},xdg-terminal-exec/gnome-xdg-terminals.list}}
│       + build-generated: etc/bazaar/*.png (JXL→PNG via djxl)
└── nvidia/                              (3 files)
    └── usr/{lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service,libexec/ublue-nvidia-flatpak-runtime-sync}
```

---

## 8. Inventory checklists (copy-paste for auditing)

### Shared — already consumed via `rsync /oci/common/shared/ /`

- [x] ujust + entry wiring (requires bluefin cherry-pick)
- [x] brew-preinstall + flatpak-preinstall + uupd + rechunker + system/user-setup services + presets
- [x] udev rules (game devices + YubiKey + platform quirks)
- [x] bling / uwelcome / umotd / fastfetch shell integration
- [x] chairlift policy + desktop + brew bundle
- [x] container sigstore policy
- [x] OEM hooks (Framework/ASUS) — zero-cost on non-matching hardware
- [x] Brewfiles (system-cli, chairlift, bluefinctl preinstalled; cli/cncf/ai-tools etc opt-in)
- [x] libsetup.sh versioning helper

### Bluefin — mostly intentionally excluded; candidates to cherry-pick

- [ ] `just/changelog.just` → `ujust changelogs` (safe, remove pluto duplicate)
- [ ] `just/60-bonedigger.just` + `libexec/bonedigger-report` → `ujust report` (opt-in)
- [ ] `just/system.just:check-sb-key` (safe, one-recipe cherry-pick)
- [ ] `system/dconf-update.service` (already duplicated in pluto — consolidate)
- [x] `just/00-entry.just` — already cherry-picked (required)
- [ ] NOT `etc/dconf/*`, `zz0-bluefin-*.gschema`, wallpapers, `etc/zsh/*`, `gnome-initial-setup`, `flatpak/preinstall.d/bazaar.preinstall` — GNOME-only, skip

### Nvidia — ignore (no variant)

---

## 9. References

- `common/system_files/README.md` — layer semantics
- `common/README.md` — usage examples
- `common/Containerfile` — build stages + SHA256-pinned fetches
- `pluto/Containerfile:39,49-50` — OCI wiring
- `pluto/build/10-build.sh:17-67` — overlay + cherry-pick + preset + wiring
- `pluto/build/40-niri.sh:47-52` — second `preset-all --global` for DMS
- `common/system_files/shared/usr/share/polkit-1/actions/org.frostyard.ChairLift.bootc.policy` — pkexec path pin
- `common/system_files/shared/usr/lib/ublue/setup-services/libsetup.sh` — version-script helper
- `common/docs/skills/oem-hardware-hooks.md`, `.../brew-lifecycle/references/service-mechanics.md`
