# Research Archive

Durable research reports produced during pluto's development (primarily the
Fedora Hummingbird rebase). **Convention: any future research work is archived
here** (subagent reports, package audits, source-code analyses) so findings can
be re-consulted without re-doing the legwork. Fetch-date and sources are
recorded in each report's header.

The living design plan that consumes these reports is
[`../fedora-hummingbird-rebase.md`](../fedora-hummingbird-rebase.md).

| File | Topic | Key takeaways |
|---|---|---|
| `hummingbird-research.md` | Full-site pass over hummingbird-project.io (2026-08-28) | Two Hummingbirds (container factory vs bootc-os); bootc-os = minimal F43 server base, experimental, rolling `latest`; derivative docs = 4 lines |
| `hummingbird-research-2.md` | Primary-source verification of research #1 (repo clones, Quay, GitLab MRs) | F43 content confirmed at lockfile level; **kernel `7.1.10-100.fc43` — ARK claim dead**; F44 rebase = draft MR !15860; no F44/Rawhide bootc-os exists; SELinux at `/usr/lib/selinux` |
| `bootc-vs-fedora-diff.md` | bootc-os (302 pkgs) vs Fedora 43 Workstation comps (752) | 42 overlap; base has **zero** fonts/graphics/audio/firmware/portals/flatpak; tier-1 shortlist; greetd+tuigreet now in F43 |
| `bootc-os-packages.txt` | Full bootc-os x86_64 package-name list (from lockfile) | What the base actually ships |
| `fedora-workstation-packages.txt` | Fedora 43 Workstation comps mandatory package names | What a desktop normally includes |
| `dakota-analysis.md` | projectbluefin/dakota (BuildStream, from-scratch OS on GNOME OS) | One manifest-of-record; junction-override = base delta; bootc post-install protocol (ldconfig boot-loop regression, `00-defaults.toml`); session packaging via `wayland-sessions/*.desktop` + `TryExec=` |
| `gnome-os-analysis.md` | GNOME/gnome-build-meta (manifest pyramid, systemd-repart/sysupdate, OCI export) | Stack-element manifest pattern; bootc graph integration steps (symlinks, machine-id); `NN-category.preset` opt-in model; pinned flathub.flatpakrepo; `/usr/manifest.json` BOM |
| `niri-packages.md` | niri + DankMaterialShell + tunaOS niri images (F43, dnf-verified) | **DMS = Quickshell(Qt6/QML)+Go shell, replaces waybar/swaylock/mako/fuzzel/polkit agent**; `dms-greeter` is the greetd integration; COPRs `avengemedia/dms` + `avengemedia/danklinux`; canonical greetd config.toml; config placement rules |
| `bluefin-packages.md` | projectbluefin/bluefin TOML package manifest verified + package harvest | TOML schema `[fedora]/[fedora_vNN]/[excluded]`; tomllib reader + `assert_packages_present` gate; useful wm-agnostic package harvest; first-boot hook pattern; `kargs.d` toml |
| `common-brew-analysis.md` | projectbluefin/common + ublue-os/brew overlay contents | common `shared/` vs `bluefin/` split (`00-entry.just` = ujust entry point!); pluto never rsyncs common → flatpak/Brewfile runtime currently inactive; brew UID-1000/chown design; graphical-session.target requirement; git+jq needed at runtime (now in base.toml) |
| `niri-layer-design.md` | 40-niri layer research: DMS install mechanics, GUI apps, theming, envs | dankinstall installs niri/quickshell/dms/dms-greeter itself; `dms run` does NOT write niri config (bake at build); native-app set (gnome-disk-utility ⚠ not on Flathub, udiskie, kanshi, satty via terra…); verified Flathub preinstall list (Firefox, Papers, Bazaar, MissionCenter…); **flatpak does NOT read /etc/flatpak/overrides** → tmpfiles-symlink pattern from common; Qt stack = qt6ct+kf6; niri IS in Fedora F43 |
| `dms-docs.md` | DMS documentation map (DankLinux-Docs repo, dank-greeter) | Docs live in git (clone, don't webfetch); DMS auto-regenerates settings.json but niri fragments are NOT auto-created; `dms-greeter install` disabled on ostree → manual greetd config is correct; DMS owns bar/lock/idle/polkit-agent/clipboard/screenshot; envs per docs (QT_QPA_PLATFORMTHEME=gtk3); greeter user via sysusers.d/tmpfiles.d |
| `neptuno-analysis.md` | Audit of sibling GNOME+niri/DMS image (silverblue-based, rebased-only history) | Ports applied: xdg-terminals.list (ghostty), GTK_USE_PORTAL + Wayland envs, touchpad input block, gdk-pixbuf cache rebuild, negativo VENDOR assert, sulogin generator + dconf-update.service, install-dms-config + changelogs ujust, hardware/CLI/font packages, khal, intel-gmmlib+libheif overrides, +7 flatpaks. ⚠ DANGER: build-time flatpak override/mask only survived rebases — pluto's first-boot unit is correct. GDM path not portable; yalter/niri COPR redundant; alsa-tools-firmware/flatpak-spawn are non-packages |

Source clones used by the agents (kept in scratch, not archived):
`/tmp/opencode/{hummingbird-containers,dakota,gnome-build-meta,dms,niri-refs/tunaOS,common,brew,bluefin,fedora-comps}`
