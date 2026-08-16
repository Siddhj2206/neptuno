# neptuno TODO — sync with upstream / hardening

Trailing: "we'll do that after" = G21/G22/G23 (container-native ISO via dakota-iso, testing channel, ChairLift).

## ✅ Done this session
- [x] Bonedigger removed (`60-bonedigger.just` dropped, G4)
- [x] `install-dms-config` recipe rewritten + tested (dead ujust.sh source removed)
- [x] `flatpak-nuke-fedora.service` stale unit name fixed (`flatpak-appstream-refresh`)
- [x] Services explicitly enabled: `brew-update.timer`, `brew-upgrade.timer`, `flatpak-appstream-refresh.service`, `rechunker-group-fix.service`, user `brew-preinstall.service`
- [x] Local ujust cleanup: removed `custom-apps.just`, `development.Brewfile`, `fonts.Brewfile`
- [x] Preinstall Brewfile wired: `custom/brew/preinstall.d/default.Brewfile` → auto-installed at first login (G12)

## 🔧 To fix (P0 — quick wins)
- [ ] **G1 — sudo can't run brew binaries** — add linuxbrew path to `secure_path` in `/etc/sudoers` (bluefin `build_files/base/05-override-install.sh` pattern) → `build/steps/20-base.sh`
- [ ] **G2 — tailscale operator unset** — add `custom/files/usr/share/ublue-os/privileged-setup.hooks.d/10-tailscale.sh` (`tailscale set --operator=$USER`) → CLI works for non-root
- [ ] **G3 — `ujust install-system-flatpaks` / `bluefin-apps` broken** — copy common `system-flatpaks.Brewfile` (+ `system-dx-flatpaks.Brewfile`?) into the image, or override the recipes in 60-custom.just
- [ ] **G5 — `ujust setup-vms` / `toggle-devmode` broken** — copy `ensure-libvirt-session-config` from common bluefin layer → `/usr/libexec/` (libvirt is baked)
- [ ] **G6 — `ujust changelogs` shows Bluefin's** — override changelog.just in 60-custom.just to point at siddhj2206/neptuno
- [ ] **G9 — starship not initialized in bash** — add profile.d/90-neptuno-starship.sh (fish already covered by common)
- [ ] **G10 — flatpak-nuke ordering** — add `Before=flatpak-system-helper.service` to match current bluefin unit

## 🔧 To fix (P1 — infra/hardening)
- [ ] **G14 — initramfs unconditional + non-reproducible** — port bluefin `19-initramfs.sh`: marker skip, `DRACUT_NO_XATTR=1`, `--reproducible`, add `ostree dmsquash-live dmsquash-live-autooverlay`; keep neptuno VFIO `80-vfio.conf`
- [ ] **G16/G17 — firewalld defaults + emergency-boot** — FedoraWorkstation zone + `IPv6_rpfilter=loose`; fetch `coreos-sulogin-force-generator` (root password instead of silent drop-to-shell)
- [ ] **G18 — rpm-ostreed staging** — `/etc/rpm-ostreed.conf` `AutomaticUpdatePolicy=stage` safety net
- [ ] **G19 — gdk-pixbuf loader cache** — `gdk-pixbuf-query-loaders-64 --update-cache` after codec installs
- [ ] **G20 — uupd-on-ac service** — explicitly enable `uupd-on-ac.service` (AC-aware scheduling already ships)

## ❓ Research first
- [ ] **G7 — Secure Boot** — neptuno uses the stock Fedora-signed kernel/shim, so Secure Boot works out of the box on standard UEFI with SB enabled; nothing to enroll. `ujust enroll-secure-boot-key` is only needed for self-signed/akmods kernels (ublue akmods) — neptuno doesn't have them → replace recipe with an informational no-op. (Confirm before editing.)

## ⏸️ Deferred
- [ ] **G8/G22 — testing channel** — `toggle-testing` recipe + release/CI infrastructure. Add later.
- [ ] **G11 — gaming** — `50-gaming.sh` kept, intentionally unconnected (no rpmfusion); revisit when wanted
- [x] **G13 — rechunking** — ✅ already enabled: `.github/workflows/build-image.yml:146` "Rechunk image" step (`projectbluefin/actions/bootc-build/chunka`, max-layers 128) on non-PR default-branch builds
- [ ] **G15 — two-stage Containerfile / cache boundaries** — build-time optimization, user prefers current single-RUN structure
- [ ] **G21 — container-native ISO / live ISO** — dakota-iso revamp (discuss in detail)
- [ ] **G23 — ChairLift (`bctl`)** — brings inherited `bctl`-delegating recipes alive; needs frostyard/tap in preinstall