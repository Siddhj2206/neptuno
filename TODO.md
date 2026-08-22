# neptuno TODO — sync with upstream / hardening

Trailing: "we'll do that after" = G21/G22/G23 (container-native ISO via dakota-iso, testing channel, ChairLift).

## ✅ Done
- [x] **G12 — preinstall Brewfile wired** — `custom/brew/default.Brewfile` auto-installs at first login (`400ac75`; relocated from `preinstall.d/` to the standard `custom/brew/` path, build copies it into the image's `preinstall.d/`)
- [x] **G4 — bonedigger** — `60-bonedigger.just` dropped, `ujust report` gone (`400ac75`)
- [x] **install-dms-config** — rewritten + tested (dead ujust.sh source, tput styling, env-overridable paths, robust backups) (`400ac75`)
- [x] **Services/timers enabled explicitly** — brew-update/upgrade timers, flatpak-appstream-refresh, rechunker-group-fix, user brew-preinstall (presets never fire on bootc) (`400ac75`)
- [x] **G13 — rechunking confirmed ON** — `build-image.yml:146` `chunka` action (max-layers 128) on default-branch builds
- [x] **G1 — sudo + linuxbrew** — `secure_path` sed in `20-base.sh` (`b100436`)
- [x] **G2 — tailscale operator** — privileged-setup chain added: `99-privileged.sh` + `10-tailscale.sh` (polkit YES rule already on image) (`b100436`)
- [x] **G3 — flatpak Brewfiles** — `system-flatpaks.Brewfile` + `system-dx-flatpaks.Brewfile` shipped; `install-system-flatpaks`/`bluefin-apps` work (`b100436`)
- [x] **G5 — VM recipes** — `ensure-libvirt-session-config` shipped; `setup-vms`/`toggle-devmode` work (`b100436`)
- [x] **G6 — changelogs** — overridden in 60-custom.just → `siddhj2206/neptuno` (`b100436`)
- [x] **G9 — starship bash init** — `profile.d/90-starship.sh` (`b100436`)
- [x] **G10 — flatpak-nuke ordering** — `Before=flatpak-system-helper.service` aligned with upstream (`b100436`)

## 🔧 P1 — infra/hardening
- [x] **G14 — initramfs** — `60-initramfs.sh` rewritten (bluefin pattern): arch-qualified kver, marker skip + `FORCE_INITRAMFS` override, `DRACUT_NO_XATTR=1`, `--reproducible`, explicit `ostree dmsquash-live dmsquash-live-autooverlay`; VFIO `80-vfio.conf` now actually takes effect (replaces blunt `--regenerate-all`)
- [x] **G16 — firewalld** — **already satisfied** by silverblue base: `DefaultZone=FedoraWorkstation`, `IPv6_rpfilter=loose`, `FedoraWorkstation.xml` all present live; no change
- [x] **G17 — emergency-boot** — vendored `coreos-sulogin-force-generator` (from coreos/fedora-coreos-config stable) → `custom/files/usr/lib/systemd/system-generators/`; root password instead of silent drop-to-shell
- [x] **G18 — rpm-ostreed staging** — vendored `/etc/rpm-ostreed.conf` with `AutomaticUpdatePolicy=stage` (matches bluefin)
- [x] **G19 — gdk-pixbuf loader cache** — `gdk-pixbuf-query-loaders-64 --update-cache` after codec installs in `20-base.sh`
- [x] **G20 — uupd-on-ac** — **already wired** by common: `99-uupd-on-ac.rules` (udev → `uupd-on-ac.service` on AC connect) + `10-bluefin.conf` drop-in; unit is udev-triggered/static — nothing to enable

## ❓ Pending decision
- [ ] **G7 — Secure Boot** — research settled: stock Fedora-signed kernel/shim → Secure Boot works out of the box on standard UEFI, nothing to enroll. `ujust enroll-secure-boot-key` only matters for self-signed/akmods kernels (ublue) which neptuno doesn't ship. Fix = replace the recipe with an informational no-op. **Awaiting your go-ahead to edit.**

## ⏸️ Deferred
- [ ] **G8/G22 — testing channel** — `toggle-testing` recipe + release/CI infrastructure. Add later.
- [ ] **G11 — gaming** — `50-gaming.sh` kept, intentionally unconnected (no rpmfusion); revisit when wanted
- [ ] **G15 — two-stage Containerfile / cache boundaries** — build-time optimization, user prefers current single-RUN structure
- [ ] **G21 — container-native ISO / live ISO** — dakota-iso revamp (discuss in detail)
- [ ] **G23 — ChairLift (`bctl`)** — brings inherited `bctl`-delegating recipes alive; needs frostyard/tap in preinstall
