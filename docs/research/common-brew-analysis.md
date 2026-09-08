# Audit: projectbluefin/common + ublue-os/brew OCI context images vs. pluto on Hummingbird bootc-os

**Date:** 2026-08-28 · **Prepared by:** subagent analysis session
**Repos inspected (shallow, depth 1):**
- `projectbluefin/common` @ `726e853fac` (2026-08-27)
- `ublue-os/brew` @ `4576300de2` (2026-07-08)
- `projectbluefin/bluefin` @ `c442e5c46f` (2026-08-18) — already cloned by another agent; reused for the "bluefin part" **only** (no package-manifest work duplicated)
- `projectbluefin/branding` @ main (submodule of common, cloned separately; shallow clone does not fetch submodules)
- Local context: pluto repo (`/var/home/sid/Documents/Projects/pluto`), Hummingbird `images/bootc-os` Containerfile (`/tmp/opencode/hummingbird-containers`), prior research notes in `/tmp/opencode/*.md`

**How pluto consumes these (verified):**
- `Containerfile:39-40` pins `common:latest@sha256:df2fa93…` and `brew:latest@sha256:5c5b6de…`; `Containerfile:49-50` copies **all** of common's `/system_files` to `/oci/common` and brew's `/system_files` to `/oci/brew`.
- `build/10-build.sh` runs `rsync -rvK /ctx/oci/brew/ /` and **never touches `/oci/common`** (verified: grep for `oci/common` only hits Containerfile comments). So pluto currently ships the brew overlay and nothing from common. Everything pluto gets from common below is *prospective*.

---

## 1. common (`projectbluefin/common`) — repo layout and image content

### 1.1 What feeds `/system_files` in the published OCI image

The image's `ctx` stage (`Containerfile:85-92`) assembles `/system_files` from five sources:

| Source | Lands in | Content |
|---|---|---|
| `/system_files/shared` (repo) | `/system_files/shared` | all-variant overlay |
| `/bluefin-branding/system_files` (submodule → `projectbluefin/branding`) | `/system_files/bluefin` | bazaar banner art (`.jxl`; converted to `.png` at build, `Containerfile:75-80`) |
| `/system_files/bluefin` (repo) | `/system_files/bluefin` | Bluefin-GNOME overlay |
| `/system_files/nvidia` (repo) | `/system_files/nvidia` | NVIDIA-only overlay |
| build stage `/out/*` | merged into `shared/` and `bluefin/` | generated artifacts (below) |

**Build-time additions** (`Containerfile:15-83`, `system_files/README.md:27-32`):
- `shared/usr/bin/umotd`, `shared/usr/bin/uwelcome` — static Go binaries (built from `projectbluefin/umotd` @ c9df8ec, `projectbluefin/uwelcome` @ 5280521)
- `shared/usr/share/bash-completion/completions/ujust`, `.../zsh/site-functions/_ujust`, `.../fish/vendor_completions.d/ujust.fish` — just completions renamed to ujust
- `shared/usr/lib/udev/rules.d/71-*.rules` ×24 — game-devices-udev (fetched, sha256-pinned)
- `shared/usr/lib/udev/rules.d/70-u2f.rules` — Yubico libfido2
- `bluefin/usr/share/backgrounds/bluefin/*` (`.jxl`+`.xml`) + `bluefin/usr/share/gnome-background-properties/*.xml` — from `ghcr.io/ublue-os/bluefin-wallpapers-gnome` (sed-repointed `~/.local/share`→`/usr/share`, `Containerfile:17-24`)
- `bluefin/etc/bazaar/*.png` — bazaar banner JXL→PNG conversions

The repo also declares two submodules (`.gitmodules`): `bluefin-branding` (above) and `system_files/bluefin/usr/share/gnome-shell/extensions/custom-command-list@storageb.github.com` (StorageB/custom-command-menu — GNOME shell extension source).

> **Note:** the published image's tree therefore ≠ the git tree exactly (umotd/uwelcome, ujust completions, udev rules, wallpapers, PNG banners are generated). Everything below that matters for pluto is available at the documented paths after `COPY --from=common /system_files /oci/common`.

### 1.2 Tree summary of `system_files/` (git tree)

```
system_files/
├── README.md                  # layer rules (quoted in §1.3)
├── shared/                    # ALL variants (bluefin, bluefin-lts, dakota, knuckle, forks)
│   ├── etc/
│   │   ├── containers/{policy.json, registries.d/{quay.io-toolbx-images.yaml, ublue-os.yaml}}
│   │   ├── geoclue/conf.d/99-beacondb.conf
│   │   ├── profile.d/{caffeinate.sh, ublue-fastfetch.sh, uwelcome.sh}
│   │   ├── skel/.config/ghostty/config.ghostty
│   │   ├── ublue-os/tags.json
│   │   ├── uupd/config.json
│   │   └── uwelcome/config.json
│   ├── usr/
│   │   ├── bin/{brew-preinstall, luks-tpm2-autounlock, rechunker-group-fix,
│   │   │        ublue-bling, ublue-bling-fastfetch, ublue-fastfetch,
│   │   │        ublue-image-info.sh, ublue-privileged-setup, ublue-system-setup,
│   │   │        ublue-user-setup, ujust}
│   │   ├── lib/
│   │   │   ├── modprobe.d/amd-legacy.conf
│   │   │   ├── pki/containers/{quay.io-toolbx-images.pub, ublue-os.pub, ublue-os-backup.pub}
│   │   │   ├── systemd/system/{flatpak-preinstall.service, flatpak-appstream-refresh.service,
│   │   │   │         ublue-system-setup.service, uupd.timer, uupd-on-ac.service,
│   │   │   │         uupd.service.d/10-bluefin.conf, rechunker-group-fix.service}
│   │   │   ├── systemd/system-preset/{00-rechunker-group-fix.preset, 01-uupd.preset,
│   │   │   │         02-flatpak-appstream-refresh.preset}
│   │   │   ├── systemd/user/{ublue-user-setup.service, brew-preinstall.service}
│   │   │   ├── systemd/user-preset/01-brew-preinstall.preset
│   │   │   ├── ublue/setup-services/libsetup.sh   (⚠ empty in git tree — "could not verify" content)
│   │   │   └── udev/rules.d/ (10-switch, 50-framework16, 50-steam-horipad, 50-usb-realtek,
│   │   │           50-zsa, 60-amd-s2idle-fixes, 60-arduino-mbed, 70-titan-key, 70-wooting,
│   │   │           88-neutron_hifi_dac, 90-apple-superdrive, 92-viia, 99-uupd-on-ac)
│   │   ├── libexec/{bootc-update-stage, brew-preinstall}
│   │   └── share/
│   │       ├── applications/org.frostyard.ChairLift.desktop
│   │       ├── chairlift/config.yml
│   │       ├── color/icc/colord/{framework13.icc, framework16.icc}
│   │       ├── fish/vendor_conf.d/{fish_greeting.fish, starship.fish, ublue-fastfetch.fish}
│   │       ├── icons/hicolor/scalable/{actions/{ampere,asus-rog,framework}-logo-symbolic.svg,
│   │       │        apps/{org.frostyard.ChairLift, org.frostyard.ChairLift-flower}.svg,
│   │       │        symbolic/apps/org.frostyard.ChairLift-symbolic.svg}
│   │       ├── pipewire/pipewire-pulse.conf.d/50-bluefin-bt-switch.conf
│   │       ├── polkit-1/actions/{org.frostyard.ChairLift.bootc.policy,
│   │       │        org.ublue.privileged.user.setup.policy}
│   │       ├── polkit-1/rules.d/{20-privileged-user-setup.rules,
│   │       │        org.debian.pcsc-lite.access_card.rules}
│   │       └── ublue-os/
│   │           ├── bling/{bling.sh, bling.fish}
│   │           ├── homebrew/{ai-tools, artwork, cli, cncf, experimental-ide, fonts,
│   │           │        fonts-dev, ide, k8s-tools, swift}.Brewfile
│   │           ├── homebrew/preinstall.d/{bluefinctl, chairlift, system-cli}.Brewfile
│   │           ├── just/{apps.just, default.just, shared.just, update.just}
│   │           ├── oem/{ASUS/{logo, packages.Brewfile},
│   │           │        Framework/{51-framework-desktop.conf, logo, packages.Brewfile}}
│   │           ├── system-setup.hooks.d/{10-framework.sh, 11-asus.sh}
│   │           └── user-setup.hooks.d/{10-theming.sh, 20-oem-brew.sh}
├── bluefin/                    # Bluefin GNOME variants only
│   ├── etc/
│   │   ├── bazaar/{bazaar.yaml, blocklist.yaml, curated.yaml, hooks.py} (+ build-time *.png, submodule *.jxl)
│   │   ├── dconf/db/distro.d/{01-bluefin-folders, 02-bluefin-keybindings,
│   │   │       03-bluefin-ptyxis-palette, 04-bluefin-custom-command-menu,
│   │   │       05-bluefin-searchlight-extension} + locks/01-bluefin-locked-settings
│   │   ├── environment                      # GNOME_SHELL_SLOWDOWN_FACTOR=0.8
│   │   ├── gnome-initial-setup/vendor.conf  # skip=software
│   │   ├── skel/.config/Code/User/settings.json
│   │   ├── skel/.local/share/flatpak/overrides/{com.google.Chrome, com.visualstudio.code}
│   │   ├── skel/.local/share/org.gnome.Ptyxis/palettes/catppuccin-dynamic.palette
│   │   ├── ublue-os/fastfetch.json
│   │   ├── xdg/mimeapps.list
│   │   └── zsh/{zlogin, zlogout, zprofile, zshenv, zshrc}
│   └── usr/
│       ├── lib/dracut/dracut.conf.d/90-passkeys-tpm.conf
│       ├── lib/systemd/system/dconf-update.service
│       ├── lib/systemd/user/{bazaar.service, bluefin-dynamic-wallpaper.service,
│       │        bluefin-dynamic-wallpaper.timer}
│       ├── lib/tmpfiles.d/bazaar-flatpak.conf
│       ├── libexec/{bazaar-hook, bluefin-dynamic-wallpaper, bonedigger-report,
│       │        ensure-libvirt-session-config, get-geoclue-latitude}
│       ├── share/
│       │   ├── applications/{bluefin-help, discourse, documentation, noop,
│       │   │        system-update}.desktop
│       │   ├── fish/vendor_functions.d/fish_prompt.fish
│       │   ├── flatpak/preinstall.d/bazaar.preinstall
│       │   ├── glib-2.0/schemas/zz0-bluefin-modifications.gschema.override
│       │   ├── gnome-shell/extensions/custom-command-list@storageb.github.com  (submodule)
│       │   ├── icons/hicolor/scalable/{actions/ublue-logo-symbolic.svg,
│       │   │        places/{ublue-discourse, ublue-docs, ublue-update}.svg}
│       │   ├── pixmaps/faces/bluefin/*.jpg (16), fedora-gdm-logo.png,
│       │   │        fedora-logo*.png, fedora_logo_med.png, fedora_whitelogo_med.png,
│       │   │        system-logo-white.png
│       │   ├── plymouth/themes/spinner/{silverblue-watermark.png, watermark.png}
│       │   └── ublue-os/
│       │       ├── bling/env.sh
│       │       ├── bluefin-logos/{bluefin.png, chicken.png, dolly.png, karl.png,
│       │       │        sixels/{bluefin,chicken,dolly,karl}, symbols/{bluefin,chicken,dolly,karl}}
│       │       ├── fastfetch.jsonc
│       │       ├── firefox-config/01-bluefin-global.js
│       │       ├── flatpak-overrides/io.github.kolunmi.Bazaar
│       │       ├── homebrew/{full-desktop, system-dx-flatpaks, system-flatpaks}.Brewfile
│       │       ├── just/{00-entry.just, 60-bonedigger.just, changelog.just, system.just}
│       │       ├── otel/ujust-report-config.yaml
│       │       └── user-setup.hooks.d/20-dynamic-wallpaper.sh
└── nvidia/                      # NVIDIA image variant only
    ├── README.md
    └── usr/{lib/systemd/system/ublue-nvidia-flatpak-runtime-sync.service,
        libexec/ublue-nvidia-flatpak-runtime-sync}
```

### 1.3 Shared vs. bluefin-specific — what the repo docs say

`system_files/README.md:7-25` (exact boundaries):

- **`shared/`** — "Applied to **all** Bluefin variants: `bluefin`, `bluefin-lts`, `dakota`, `knuckle`, and any downstream fork." Rule: *"A file goes in `shared/` if its absence would meaningfully degrade the experience on any variant, or if it provides infrastructure consumed by all variants (systemd units, udev rules, shell utilities, OEM hardware hooks)."*
- **`bluefin/`** — "Applied only to the **Bluefin GNOME desktop** variants. Contains: GNOME dconf defaults and locks; Bluefin brand identity (icons, wallpapers via the `bluefin-branding` submodule); GNOME Shell extensions; Bazaar app store configuration; Bluefin-specific just recipes and Flatpak lists." Rule: *"A file goes in `bluefin/` if it is specific to the GNOME desktop, Bluefin product identity, or has no meaning on headless or non-GNOME variants."*
- **`nvidia/`** — "Applied to the **NVIDIA GPU** image variant."

Top-level `README.md` confirms: *"`system_files/bluefin/` — Files specific to Bluefin: GNOME desktop settings and theming, Bluefin wallpapers and branding, Desktop-specific environment variables, GNOME Initial Setup configuration"* and *"`system_files/shared/` — Files shared with [Aurora](https://getaurora.dev) — Aurora maintainers can cherry-pick commits touching this directory."*

**Where "the bluefin part" lives (two places):**
1. `common`'s `system_files/bluefin/` + the `bluefin-branding` submodule content (GNOME desktop layer of the common image).
2. `projectbluefin/bluefin`'s own `system_files/shared/` — the bluefin repo ships its remaining product-specific overlay itself (numbered scripts/packages are in `build_files/`, out of scope here — other agent's domain). Bluefin's `Containerfile:36-49` merges in its `ctx` stage: `common /system_files/shared` **then** `common /system_files/bluefin` **then** `brew /system_files` — all into one tree (`system_files/shared`), which Stage 2 rsyncs to `/` minus gnome-shell extensions (`Containerfile:143`, `rsync -rvK --exclude="/usr/share/gnome-shell/extensions/***"`). Extensions are compiled separately by `extension-builder` and copied at `Containerfile:125-126`.

Bluefin repo `system_files/shared/` tree (all GNOME-product files):

```
system_files/shared/
├── etc/dconf/db/distro.d/04-bluefin-custom-command-menu
├── etc/profile.d/{90-bluefin-starship.sh, 91-bluefin-aliases.sh}
├── etc/rpm-ostreed.conf                          # AutomaticUpdatePolicy=stage (rpm-ostree only)
├── usr/libexec/bluefin-refresh-stats
├── usr/lib/modprobe.d/fw-charge-control.conf
├── usr/lib/systemd/system/{bluefin-stats-refresh.service, bluefin-stats-refresh.timer,
│        bootc-unified-storage.service, flatpak-nuke-fedora.service}
├── usr/lib/udev/rules.d/61-amd-s2idle-hp.rules
├── usr/share/dnf/plugins/copr.vendor.conf
├── usr/share/flatpak/preinstall.d/bazaar.preinstall   # CollectionID=org.flathub.Stable —
│        differs from common's bazaar.preinstall (diff verified)
├── usr/share/icons/hicolor/scalable/actions/ublue-logo-symbolic.svg
├── usr/share/ublue-os/privileged-setup.hooks.d/{10-tailscale.sh,
│        11-framework-ucsi-workaround.sh, 99-flatpaks.sh}
├── usr/share/ublue-os/user-setup.hooks.d/{12-gnupg.sh, 20-framework.sh, 99-privileged.sh}
└── usr/share/gnome-shell/extensions/  (9 submodules: appindicatorsupport, bazaar-integration,
         blur-my-shell, caffeine, dash-to-dock, gradia-integration, gsconnect,
         search-light, custom-command-list)
```

### 1.4 Categorized content of the published image

- **Branding/artwork:** wallpapers (`bluefin/usr/share/backgrounds/bluefin/*`, `gnome-background-properties/*`), bazaar banners, bluefin-logos (png + sixel + symbol sets), fastfetch configs + themes (`shared/usr/bin/ublue-bling-fastfetch`), pixmaps incl. `fedora-gdm-logo.png`, plymouth spinner watermarks, OEM logos (ASUS/Framework).
- **Configs:** dconf distro DB + locks (GNOME), gschema override (GNOME), `etc/environment` (GNOME), containers policy + sigstore pubkeys (image-pull verification), uupd/uwelcome JSON, geoclue, pipewire-pulse, polkit, mimeapps, ghostty/Code/Ptyxis skel configs, firefox global pref.
- **systemd units (system):** flatpak-preinstall, flatpak-appstream-refresh, ublue-system-setup, uupd.timer + uupd-on-ac (+ drop-in), rechunker-group-fix; bluefin layer: dconf-update. **(user):** ublue-user-setup, brew-preinstall; bluefin layer: bazaar, bluefin-dynamic-wallpaper.*.
- **First-boot/user-setup machinery:** `ublue-system-setup` → `system-setup.hooks.d/*`, `ublue-user-setup` → `user-setup.hooks.d/*`, `ublue-privileged-setup` (pkexec-gated) → `privileged-setup.hooks.d/*`, version-gated via `libsetup.sh` `version-script`. **Note: there is no ublue-firstboot binary in the current tree** — first-boot work is split between these hook runners and flatpak-preinstall/brew-setup services.
- **Services/infra:** brew-preinstall (user unit + libexec, content-addressed brew bundle sync), ChairLift (bootc update GUI: polkit action + `bootc-update-stage`), uupd, umotd/uwelcome binaries.
- **ujust recipes:** entry `00-entry.just` **ships in the bluefin layer** (imports apps/changelog/default/shared/system/update + optional `60-custom.just`, `60-bonedigger.just` — files in the bluefin layer); `ujust` wrapper hardcodes `--justfile /usr/share/ublue-os/just/00-entry.just`.
- **Tools:** luks-tpm2-autounlock, rechunker-group-fix, udev rules (13 shipped + 24 game-devices + u2f), dracut passkeys modules, piping.

### 1.5 GNOME / GDM / ostree-desktop assumptions (drop/adapt list — exact paths)

**Common `bluefin/` layer — GNOME desktop–fixed:**

| Path | Why it assumes GNOME/GDM | Verdict for pluto (niri+greetd, minimal base) |
|---|---|---|
| `system_files/bluefin/etc/dconf/db/distro.d/` (01-05) + `locks/` | dconf/gsettings GNOME settings; binary dconf DBs | **Drop** (no dconf consumer without GNOME). 03 is Ptyxis-only (keep only if Ptyxis planned) |
| `system_files/bluefin/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override` | org.gnome.* schemas: favorite-apps, extensions, mutter, shell, wm keybindings… | **Drop** (must drop *before* `glib-compile-schemas`; otherwise unknown keys are just ignored) |
| `system_files/bluefin/usr/lib/systemd/system/dconf-update.service` | runs `dconf update`; needs dconf pkg | **Drop** (no dconf db) |
| `system_files/bluefin/etc/gnome-initial-setup/vendor.conf` | gnome-initial-setup (GDM first-login flow) | **Drop** (no GDM; base also masks systemd-firstboot) |
| `system_files/bluefin/etc/environment` | GNOME_SHELL_SLOWDOWN_FACTOR | **Drop** (GNOME-only) |
| `system_files/bluefin/usr/share/applications/{bluefin-help,discourse,documentation,noop,system-update}.desktop` | GNOME-centered launchers (help.gnome.org, GNOME Disks workaround) | **Drop or rewrite** (noop/.desktop could be kept for appimage mime) |
| `system_files/bluefin/usr/share/xdg-terminal-exec/gnome-xdg-terminals.list` | hardcodes org.gnome.Ptyxis.desktop | **Adapt** (point to pluto's terminal or drop) |
| `system_files/bluefin/usr/share/gnome-shell/extensions/custom-command-list@storageb.github.com/` | GNOME Shell extension source | **Drop** |
| `system_files/bluefin/usr/lib/systemd/user/bazaar.service` | `flatpak run … Bazaar --no-window`, WantedBy=graphical-session.target | **Drop unless keeping Bazaar** |
| `system_files/bluefin/usr/libexec/bluefin-dynamic-wallpaper` + `get-geoclue-latitude` + `usr/lib/systemd/user/bluefin-dynamic-wallpaper.{service,timer}` + `usr/share/ublue-os/user-setup.hooks.d/20-dynamic-wallpaper.sh` | gsettings + GeoClue2 D-Bus (gdbus) | **Drop or rewrite** for niri (`niri msg action set-background-image` has no GeoClue analogue) |
| `system_files/bluefin/usr/libexec/ensure-libvirt-session-config` | libvirt session bus setup | **Drop unless libvirt planned** |
| `system_files/bluefin/usr/share/pixmaps/fedora-gdm-logo.png` | GDM login logo | **Drop or replace** (others are generic logos) |
| `system_files/bluefin/usr/share/ublue-os/firefox-config/01-bluefin-global.js` (+ `usr/share/ublue-os/flatpak-overrides/`, `usr/lib/tmpfiles.d/bazaar-flatpak.conf`, `usr/share/flatpak/preinstall.d/bazaar.preinstall`, `etc/bazaar/*`, `skel/.local/share/flatpak/overrides/*`) | Bazaar/Firefox/desktop-app-flatpak wiring; consumed by bluefin's `privileged-setup.hooks.d/99-flatpaks.sh` | **Keep only if pluto ships those flatpaks** (firefox-config is pluto-relevant if Firefox is a target app) |
| `system_files/bluefin/usr/share/ublue-os/homebrew/{full-desktop,system-flatpaks,system-dx-flatpaks}.Brewfile` | Bluefin desktop flatpak bundles | **Skip** (pluto ships its own Brewfiles) |
| `system_files/bluefin/etc/xdg/mimeapps.list` | defaults point to GNOME apps (Papers, Loupe, Showtime…) | **Adapt or drop** |
| `system_files/bluefin/usr/share/plymouth/themes/spinner/*.png`, `usr/lib/dracut/dracut.conf.d/90-passkeys-tpm.conf`, zsh dotfiles, skel Code settings, fish_prompt, `usr/share/ublue-os/just/*` | none — generic/benign | **Keep as desired** (passkeys dracut adds initramfs modules: fido2/tpm2-tss/pkcs11/pcsc) |

**Bluefin repo `system_files/shared/` — GNOME/ostree-desktop assumptions:**

| Path | Assumption | Verdict |
|---|---|---|
| `etc/dconf/db/distro.d/04-bluefin-custom-command-menu` | GNOME dconf | **Drop** |
| `usr/share/gnome-shell/extensions/*` (9 submodule dirs) | GNOME Shell 45+ API | **Drop** |
| `etc/rpm-ostreed.conf` | rpm-ostree daemon | **Drop** (inert on bootc; Hummingbird has no rpm-ostree) |
| `usr/libexec/bluefin-refresh-stats` + `bluefin-stats-refresh.{service,timer}` | curl/jq/numfmt + `ConditionPathIsReadWrite=/var/cache/bluefin`; Bluefin-branded ("countme", Bazaar stats) | **Keep-or-adapt** (works headless; rebrand for pluto) |
| `usr/lib/systemd/system/bootc-unified-storage.service` | bootc (`bootc image set-unified`); `ConditionPathExists=/run/ostree-booted`; reflink FS (btrfs/XFS), experimental upstream | **Optional keep** — bootc-native, but experimental + branded package `ublue-unified-storage`; on ext4 it fails → Restart=on-failure buzz. Decide deliberately |
| `usr/lib/systemd/system/flatpak-nuke-fedora.service` | flatpak installed; removes fedora remotes (Before=flatpak-preinstall, `SuccessExitStatus=1`) | **Keep** once flatpak is in the image (base has none — service no-ops via ConditionPathExists=/usr/bin/flatpak… note `flatpak remote-delete` would fail → exit 1 = success) |
| `usr/share/ublue-os/privileged-setup.hooks.d/11-framework-ucsi-workaround.sh` | **rpm-ostree kargs** — self-skipping guard: `command -v rpm-ostree || exit 0` | **Drop or port to `bootc kargs`** (currently inert on Hummingbird) |
| `usr/share/ublue-os/privileged-setup.hooks.d/10-tailscale.sh` | tailscale binary + `PKEXEC_UID` + wheel | **Keep only if tailscale planned** (generic mechanism) |
| `usr/share/ublue-os/privileged-setup.hooks.d/99-flatpaks.sh`, `user-setup.hooks.d/{12-gnupg,20-framework,99-privileged}.sh`, `etc/profile.d/90-bluefin-starship.sh` (uses `/var/home/linuxbrew` — fine, symlinked), `91-bluefin-aliases.sh`, `61-amd-s2idle-hp.rules`, `copr.vendor.conf` | none (hardware/shared) | **Keep** (12-gnupg is F43+ scdaemon fix — relevant) |
| `usr/share/ublue-os/user-setup.hooks.d/99-privileged.sh` (`pkexec ublue-privileged-setup`) + common's `polkit-1/actions/org.ublue.privileged.user.setup.policy` + `rules.d/20-privileged-user-setup.rules` | polkit present (✓ in base) + wheel group + **a polkit auth agent in session** | **Keep; add a polkit agent** (GNOME's agent is absent; niri needs e.g. polkit-gnome) — see §4 |

**Common `shared/` layer — not GNOME-specific but base-specific assumptions (verified against Hummingbird facts):**

| Path | Assumption | Status on Hummingbird bootc-os |
|---|---|---|
| `usr/lib/systemd/system/flatpak-preinstall.service` | `ConditionPathExists=/usr/bin/flatpak`; runs `flatpak preinstall -y`; WantedBy=multi-user.target; **no preset shipped** (must `systemctl enable` explicitly — bluefin does it in its build scripts) | **Flatpak absent from base** → install flatpak package or unit no-ops |
| `usr/lib/systemd/system/flatpak-appstream-refresh.service` | `After=flatpak-system-helper.service`; ExecCondition probes NetworkManager D-Bus metered state (`busctl get-property org.freedesktop.NetworkManager …`) | Base has NetworkManager ✓ (no `NetworkManager-wifi`, per prior research) — on no-NM failure the `$(…)` is empty → condition passes → still runs |
| `usr/lib/systemd/system/ublue-system-setup.service` | `After=rpm-ostreed.service` (missing unit → ordering silently ignored; no failure); `Before=systemd-user-sessions.service` ✓; needs `ublue-system-setup` + hooks + `jq` (gracefully falls back if absent) | Works; jq missing → defaults used |
| `usr/lib/systemd/system/rechunker-group-fix.service` + `usr/bin/rechunker-group-fix` | `ConditionPathExists=/run/ostree-booted`; `After=bootc-sysusers-shadow-sync.service` (bootc-native); runs systemd-sysusers + `systemd-tmpfiles --create --remove --boot` | bootc images create `/run/ostree-booted` at boot (standard ostree prepare-root behavior; **could not verify** from local clones); unit comments demand caution — keep |
| `usr/lib/systemd/system/uupd.timer` + `uupd-on-ac.service` + `uupd.service.d/10-bluefin.conf` + preset `01-uupd.preset` | the actual `uupd.service`/binary ship as an RPM (projectbluefin/uupd), **not in common** — **could not verify** whether pluto installs it | Preset is inert if unit absent; decide whether to adopt uupd |
| `usr/lib/systemd/user/ublue-user-setup.service`, `usr/lib/systemd/user/brew-preinstall.service` (+ user preset) | WantedBy=**graphical-session.target**; `ConditionUser=!@system`; brew-preinstall also `After=ublue-user-setup.service` + `ConditionPathExists=/home/linuxbrew/.linuxbrew/bin/brew` | **Needs the niri session to activate graphical-session.target** (greetd alone does not). Without it, user hooks + brew preinstall never run |
| `usr/share/polkit-1/rules.d/org.debian.pcsc-lite.access_card.rules` | pcscd/polkit, wheel | Keep (YubiKey) |
| ChairLift desktop + policy + `usr/libexec/bootc-update-stage` | boots `bootc upgrade` via pkexec; GUI app (GTK) | Works headless-less; GUI needs a desktop session — optional |
| `etc/containers/policy.json` + pki/pubkeys + registries.d | container signature verification for toolbx-images + ublue-os (harmless without those remotes; **blanket `""` insecureAcceptAnything for docker** remains) | Keep (matches bluefin; affects podman pulls) |
| `usr/lib/udev/rules.d/*`, `modprobe.d/amd-legacy.conf`, `pipewire-pulse.conf.d/50-bluefin-bt-switch.conf`, `profile.d/*`, skel ghostty config, umotd/uwelcome | none | Keep; uwelcome runs on interactive shells (fine on TTY) |
| `nvidia/` (ublue-nvidia-flatpak-runtime-sync) | `ConditionPathExists=/sys/module/nvidia/version` + `/run/ostree-booted` | Inert without NVIDIA GPU — harmless to ship |

---

## 2. brew (`ublue-os/brew`) — image content and Hummingbird compatibility

### 2.1 What the OCI ships (`/system_files`), from `Containerfile:10-12` + repo tree

`FROM scratch AS ctx: COPY system_files /system_files; COPY --from=builder /out/homebrew.tar.zst /system_files/usr/share/homebrew.tar.zst`

```
/usr/share/homebrew.tar.zst          # prebuilt Homebrew 5.0.8 (=BREW_VERSION), glibc-based Linux bottle set,
                                     # built on wolfi (Containerfile), extracted at first boot
/etc/profile.d/brew.sh               # interactive bash: eval brew shellenv, append brew bin to PATH
                                     #   (system PATH wins — brew must NOT override dbus etc.)
/etc/profile.d/brew-bash-completion.sh
/etc/security/limits.d/30-brew-limits.conf         # * soft nofile 4096; root soft nofile 4096
/usr/lib/systemd/system/brew-setup.service         # first-boot extractor (see below)
/usr/lib/systemd/system/brew-update.service        # User=1000; brew update
/usr/lib/systemd/system/brew-update.timer          # OnBootSec=10min; OnUnitInactiveSec=6h; Persistent=true
/usr/lib/systemd/system/brew-upgrade.service       # User=1000; brew upgrade
/usr/lib/systemd/system/brew-upgrade.timer         # OnBootSec=30min; OnUnitInactiveSec=8h; Persistent=true
/usr/lib/systemd/system-preset/01-homebrew.preset  # enable brew-setup.service, brew-update.timer, brew-upgrade.timer
/usr/share/fish/vendor_conf.d/ublue-brew.fish      # interactive fish: brew shellenv + appended PATH
```

`brew-setup.service` behavior: `ConditionPathExists=!/etc/.linuxbrew`, `!/home/linuxbrew/.linuxbrew`, `/usr/share/homebrew.tar.zst` → extracts tar to `/tmp/homebrew`, `cp -R -n` to `/home/linuxbrew/.linuxbrew`, `chown -R 1000:1000`, `touch /etc/.linuxbrew`; WantedBy=default.target+multi-user.target.

### 2.2 Compat flags for a Hummingbird base (F43, glibc 2.43)

- **`/home/linuxbrew` path — OK.** Hummingbird keeps `/home` → `var/home` (bootc-os Containerfile: `ln -s var/home ${NEWROOT}/home`; `/var/home` recreated by `usr/lib/tmpfiles.d/bootc-os-var.conf`). The recent brew fix commit ("use /home/linuxbrew instead of /var/home/linuxbrew") matches pluto's `/home` symlink reality; `/var` persists across updates, so the extraction survives.
- **`/var` cleared pre-ship — OK by design.** First boot wipes `/var` → `/home/linuxbrew` and `/etc/.linuxbrew` markers gone → `brew-setup` runs on the first real boot (exactly its purpose). `etc/.linuxbrew` persists afterwards via bootc's `/etc` 3-way merge (same mechanism bluefin relies on).
- **glibc/kernel ABI — OK.** Homebrew-on-Linux uses the *system* glibc (tarball has no bundled glibc); F43's glibc 2.43 is newer than the brew CI/bluefin-tested baseline. **Could not verify** brew binaries against the exact Hummingbird rebuild, but glibc is byte-identical per prior research (`glibc 2.43-8.2.hum1`).
- **Hardcoded `User=1000` / `chown 1000:1000`:** assumes the first real user is UID 1000. Hummingbird masks systemd-firstboot and has no gnome-initial-setup → **user provisioning is pluto's job** (useradd/cloud-init/ignition); if the user isn't UID 1000, brew-setup/update/upgrade misbehave. Flag for pluto's setup design.
- **First-boot ordering:** `brew-setup` Wants/After=basic.target only — no GDM/display-manager dependency, runs headless at boot. Network needed only later by update/upgrade timers (base has NetworkManager ✓; wifi caveats irrelevant to timers).
- **Missing deps in base:** Homebrew needs `git` (brew update/install use it) and `curl` (present ✓) — **git is NOT in bootc-os** (prior research overlap list). Pluto must add git (and `jq` for brew-preinstall's state hashing and for ublue-system-setup defaults — botht degrade gracefully without it, but brew-preinstall uses `jq` for state; without jq its state handling breaks, not just degrades).
- **SELinux:** store relocation to `/usr/lib/selinux` doesn't affect these files; `/home/linuxbrew` gets `user_home_t` from the standard policy home rules at extraction (`cp` from `/tmp` creates files per parent context) — identical to what bluefin images do on enforcing Fedora today.
- **shell integration:** bash/fish only (no zsh file in brew; zsh users rely on profile.d? **could not verify** — no zsh integration shipped) — pluto's niri session shells get it via profile.d.
- **Known upstream limitation (README):** brew env leaks into non-interactive shells launched from a TTY (krunner/rofi-class launchers) — with greetd+niri, shells launched from the session inherit minimal env by default; brew.sh only evals when `[[ $- == *i* ]]` so risk is low.
- **Stale README flap:** README mentions `usr/lib/tmpfiles.d/homebrew.conf` — **that file does not exist in the repo tree (could not verify in the published image)**; the only extractor is brew-setup.service. The README also says extraction targets `/var/home/linuxbrew/…` while the current unit uses `/home/linuxbrew` — docs lag the fix commit.

### 2.3 What pluto already gets via `rsync -rvK /ctx/oci/brew/ /`

Everything in §2.1, plus: **preset application** — pluto explicitly runs `systemctl enable brew-setup.service`, `brew-update.timer`, `brew-upgrade.timer` (10-build.sh, so the `01-homebrew.preset` is belt-and-braces). Notable: pluto enables these but **does not** enable the user units (`brew-preinstall.service` from common — not present in brew's image at all: the preinstall machinery and its `preinstall.d/*.Brewfile` collection live in **common**, not brew). `brew-preinstall` state hashing depends on `jq`; pluto's own Brewfiles are copied to `/usr/share/ublue-os/homebrew/` but nothing runs them today (no `brew-preinstall` unit, no `brew bundle` bootstrap) — **verified gap**: pluto ships Brewfiles that are currently dead weight until the common-based user unit or an equivalent is wired in, *and* graphical-session.target activation exists.

---

## 3. The "bluefin part" — what pluto would need from it beyond common

Because bluefin's `system_files/shared/` and common's `bluefin/` layer are merged (bluefin Containerfile `ctx`), the bluefin-specific overlay is: **common/system_files/bluefin/** + **bluefin/system_files/shared/** (listed in §1.5). From those, the pieces with *functional* value for a niri image (i.e., not pure GNOME) are:

1. `usr/share/ublue-os/just/` — **`00-entry.just` lives in common's bluefin layer** and is the hardcoded entry for `/usr/bin/ujust`; pluto's own consolidated `60-custom.just` is imported via `import?` from exactly that entry file. Without the bluefin layer, `ujust` fails at startup (`justfile not found`). To use `ujust` on pluto you need either common's bluefin just dir or an equivalent entry file of your own.
2. `flatpak-preinstall.d/bazaar.preinstall` (bluefin repo variant carries `CollectionID=org.flathub.Stable`, common's doesn't) — matters only if Bazaar is kept.
3. Hardware/shared hooks: `12-gnupg.sh`, `20-framework.sh`, `91-bluefin-aliases.sh`, `90-bluefin-starship.sh`, `61-amd-s2idle-hp.rules`, `copr.vendor.conf`, `flatpak-nuke-fedora.service`, stats refresh (rebrandable), `bootc-unified-storage.service` (optional, experimental).
4. GNOME shell extensions — **no value on niri**; the extension-builder stage in bluefin is pure GNOME machinery. Drop.

---

## 4. What pluto might be missing entirely (verified + could-not-verify)

**Verified missing today (pluto consumes only brew):**
- `flatpak-preinstall.service` — pluto "relies on it" (task statement) but it ships only in **common's shared layer**, which pluto never rsyncs; the Hummingbird base has no flatpak at all. Both the unit **and** the flatpak package are absent. When adding: also `systemctl enable flatpak-preinstall.service` (no preset exists in common/bluefin), or the preinstall files under `/usr/share/flatpak/preinstall.d/` (pluto copies its own) stay inert.
- `/usr/bin/ujust` + all just recipes (`00-entry.just` …), `ublue-bling`, `uwelcome`/`umotd` (every shell login currently has no MOTD), `ublue-system-setup`/`ublue-user-setup`/`ublue-privileged-setup` + hooks, `brew-preinstall` machinery, udev rule set (game-devices/u2f/framework/etc.), containers `policy.json` + sigstore keys, `luks-tpm2-autounlock`, `rechunker-group-fix`, dracut passkeys modules, ChairLift (optional), fastfetch/bling theming, OEM hooks.
- **No niri/greetd content exists anywhere in common/bluefin/brew** — session files, greetd config, niri config, autologin: all pluto-side work.
- **graphical-session.target activation for user units**: `ublue-user-setup` and `brew-preinstall` are WantedBy=graphical-session.target — with greetd→niri you must ensure the session starts that target (typical: session wrapper runs `systemctl --user start graphical-session.target` once niri is up), or first-login user setup and brew CLI preinstalls silently never run.
- **Polkit auth agent**: bluefin flows (`99-privileged.sh` etc.) and ChairLift presuume a polkit agent in the session; GNOME's is gone with the desktop — pluto needs e.g. `polkit-gnome`/`polkit-kde` on the niri session.
- **User provisioning / UID 1000**: systemd-firstboot is masked and there's no gnome-initial-setup; brew services hardcode UID 1000 (`chown -R 1000:1000`, `User=1000`) — pluto must create the user itself (or override the units).
- **`git` package** (brew runtime dep) and **`jq`** (brew-preinstall state, ublue setup defaults) absent from bootc-os — add or accept degraded behavior.
- **First-boot configs**: no firstboot/postinstall mechanism in the base beyond systemd units (base uses `systemctl preset-all` at image build; `80/90/99` presets exist) — pluto's units must rely on presets, `WantedBy`, or explicit `systemctl enable` in the container build (pluto already does the latter for brew).
- **Portals/desktop integration**: nothing in these images configures `xdg-desktop-portal` for a non-GNOME session; niri needs `xdg-desktop-portal-gtk`/`-wlr`-class config on pluto's side. **Could not verify** whether any portal config ships (none found in either repo).
- **`/run/ostree-booted` on bootc**: standard for bootc systems (units like `rechunker-group-fix`, `bootc-unified-storage`, nvidia sync condition on it) — **could not verify** from local clones; if pluto's runtime lacks it those units self-skip (mostly harmless, but `flatpak-nuke-fedora`/`bootc-unified-storage` behavior changes).
- **`usr/lib/ublue/setup-services/libsetup.sh`** appears empty in the git tree (hooks `source` it; `version-script` would be a no-op or missing-function error) — **could not verify**; if empty in the published image, all `version-script … || exit 0` guards become `command not found` under `set -e`… (hooks use `set -euo pipefail` only inside; system-setup runner calls `bash "$script"` — a missing function aborts that hook). Worth an actual image inspection: `skopeo copy` the common image and check. Same for the published image contents overall — the git tree is a reliable map but containers' `COPY` semantics (dir-content merge) and build-time artifacts make the published tree the only ground truth.

---

## 5. Bottom line

1. **common's OCI provides** (categorized) — §1.2/§1.4: shared infra (systemd units incl. `flatpak-preinstall.service`, user/privileged setup hook runners, brew-preinstall, ujust + recipes, udev, polkit, containers policy keys, umotd/uwelcome, ChairLift, OEM), bluefin GNOME layer (dconf, gschema overrides, wallpapers, Bazaar, GNOME extensions, GDM logo), nvidia layer (inert w/o NVIDIA).
2. **Shared vs bluefin-specific** — docs-quoted split is `shared/` (all variants incl. Aurora) vs `bluefin/` (GNOME product identity); the additional "bluefin part" lives in the bluefin repo's own `system_files/shared/` (merged by bluefin over common's two layers). Pluto needs from the bluefin part: the just entry files (incl. `00-entry.just`), flatpak-nuke, stats (rebrand), gnupg/framework hooks, copr vendor conf, udev rule — and none of the GNOME shell/dconf/GDM content.
3. **Drop/adapt list** — §1.5 tables with exact paths.
4. **brew overlay** — §2: tar + setup/update/upgrade units + profile.d/fish integration + limits + preset; compatible with Hummingbird modulo UID-1000 assumption, missing `git`/`jq`, and graphical-session-target activation of the *user* preinstall layer (which brew's image itself doesn't ship).
5. **Missing entirely** — §4: flatpak unit+package, ujust bootstrap, user hooks & brew preinstall motion, polkit agent, user provisioning, portal config, niri/greetd session (all pluto-side).
