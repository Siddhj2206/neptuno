# Pluto — Fedora Hummingbird Rebase: Design Reference

**Status:** IMPLEMENTED 2026-08-30 (PR #15; base since rolled — current pin in `Containerfile`). This doc is the **planning record** — package versions, digests, and `/tmp` paths below are the 2026-08-28 snapshot, not current state. Manifests of record: `build/packages/*.toml`.
**Last updated:** 2026-09-05 (status only; body frozen as planning snapshot)
**Companion goal:** pluto becomes a **niri + DankMaterialShell desktop** built on **Fedora Hummingbird `bootc-os`** (an experiment — no production guarantees expected).

---

## 1. Ground truth: what Hummingbird is

There are **two Hummingbirds** — never conflate them:

1. **Project Hummingbird (Red Hat)** — a *container-image factory*: 49 distroless images (157 variants incl. FIPS/multi-arch), built with Konflux/Tekton on GitLab, hermetic RPM-lockfile builds, chunkah content-addressed layers, SLSA-3 provenance, cosign signing, near-zero-CVE goal. **This is for app containers, not an OS base.**
2. **Fedora Hummingbird / `bootc-os`** — the *OS* application of the same factory model: a **rolling, bootc-based, minimal server/VM OS** shipped as an OCI image. Announced 2026-05-12. **This is our base.**

### bootc-os factsheet (verified 2026-08-28, primary sources)

| Fact | Value |
|---|---|
| Image | `quay.io/hummingbird-community/bootc-os:latest` (multi-arch x86_64 + aarch64) |
| Digest (at verification) | `sha256:ad50d8ad73f21b639956d20f0891ccf0bf67e1809a1a8f58b76f4de5fb0e04d7` — planning snapshot, SUPERSEDED (current pin: `Containerfile` `FROM` line) |
| Content | Fedora **43** packages (`fedora-43.repo`) + Hummingbird-rebuilt RPMs (pulp, `priority=10`). ~94% Hummingbird-rebuilt, ~6% Fedora (14–16 pkgs incl. all kernel packages) |
| Kernel | **`kernel-7.1.10-100.fc43` from `fedora-43-updates`** — plain Fedora kernel. **The ARK kernel claim (Magazine) is dead — no ARK/CKI anywhere in the repo** |
| Package count | **302** (x86_64 lockfile) |
| Base contents | kernel, bootc, bootupd, systemd, dracut, grub2/shim, NetworkManager, firewalld, chrony, **dnf5**, podman, skopeo, openssh, sudo, polkit, dbus-broker, bubblewrap, libxkbcommon, xkeyboard-config, selinux-policy-targeted. **NO desktop, NO flatpak, NO fonts (not even fontconfig), NO mesa/audio, NO firmware/microcode, NO NetworkManager-wifi/wpa_supplicant** |
| Tags | `latest` only — rolling, rebuilt ~daily (not strictly: no push 08-27/08-28 despite merged MRs), no version tags |
| Support level | `community`; README: *"Experimental… not suitable for production… may change without notice"* |
| F44 coming | **Draft MR !15860** (2026-08-27): rebases bootc-os to `fedora-44.repo`, regenerated lockfile → `kernel-7.1.10-200.fc44`. Not merged, no ETA. Hummingbird-rebuilt userspace stays fc43-era until the `rpms` side rebuilds → **expected mixed-version window** (F44 kernel/fedora pkgs + fc43-era userspace, `glibc 2.43-8.2.hum1`, `systemd 261.2-1.hum1`, `dnf5 5.4.3.0-2.hum1`) |
| Nothing F45/rawhide-rolling exists | Even the "rawhide" distro config tracks `fedora-44.repo`; `fedora-rawhide.repo` unused. No newer-than-F44 OS image exists anywhere (verified: pipeline config + registry probes) |
| SELinux | Policy store at **`/usr/lib/selinux`** (not `/etc` — deliberate, avoids 3-way merge overhead) |
| Install path | No native ISO → **bootc-image-builder** (`--type qcow2|iso|ami|…`); updates via `bootc switch` |
| systemd quirks | `systemd-firstboot` masked (unmask comment in their Containerfile), systemd-preset-all, `/var` cleared pre-ship, tmpfiles fixes (`home.conf` removed, `provision.conf` `/root→/var/roothome`) |
| Locale | C-only (`glibc-minimal-langpack`) |
| Build model | scratch-composed: `FROM hummingbird-builder` → `download-locked-packages` → `dnf-installroot` → `chunkah build` → `FROM oci-archive:out.ociarchive`, `LABEL containers.bootc=1`, `CMD ["/sbin/init"]` |
| `installWeakDeps` | **false** at build → niri's `Recommends:` are NOT pulled — must be explicit |
| Derivative docs | The entire public "how to build on it": `FROM bootc-os:latest` + `RUN dnf install` + `COPY` + `bootc switch`. No template, no desktop guidance, no tag/versioning guidance |

---

## 2. Package math: bootc-os vs Fedora Workstation (verified)

| Set | Size |
|---|---|
| bootc-os packages (x86_64 lockfile) | 302 |
| Fedora 43 Workstation comps (mand+default) | 752 |
| Overlap | 42 |
| Workstation-only (what we must supply) | ~710 (~395 fonts, ~33 firmware) |

Details file (planning scratch, not in repo): `/tmp/opencode/bootc-vs-fedora-diff.md`; raw lists: `/tmp/opencode/bootc-os-packages.txt`, `/tmp/opencode/fedora-workstation-packages.txt`.

---

## 3. Package manifest (dnf5, Fedora 43)

### 3.1 COPRs — one dnf transaction per repo
(TunaOS lesson #1009: one bad name kills the whole transaction → use `copr_install_isolated` helper, then **disable the COPり after use** — template rule)

| COPR | Packages |
|---|---|
| `avengemedia/dms` | `dms dms-cli` (stable 1.5.3) |
| `avengemedia/danklinux` | `dms-greeter quickshell-git matugen danksearch dgop material-symbols-fonts` |

- `quickshell` is **not in F43 base repos** (only 44+/Rawhide) — hence the COPR.
- `greetd` (0.10.3) + `tuigreet` (0.9.1) **are** in F43 proper — no COPR needed for the greeter stack.
- **DMS is a Quickshell (Qt6/QML) + Go shell** — it replaces waybar, swaylock, swayidle, mako, fuzzel, and the polkit agent. **Not GTK/Libadwaita.**
- The greeter is a separate package: **`dms-greeter`** (repo `AvengeMedia/dank-greeter`) — *this* is the greetd integration. greetd launches `dms-greeter --command niri`, running niri itself as the greeter compositor.

### 3.2 Tier 1 — desktop foundation (F43 base repos)

| Group | Packages |
|---|---|
| Compositor + DM | `niri greetd greetd-selinux xwayland-satellite` (niri's hard Requires; no bundled Xwayland anymore) |
| Portals | `xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk xdg-user-dirs xdg-utils` |
| Audio | `pipewire wireplumber pipewire-pulseaudio pavucontrol alsa-ucm alsa-sof-firmware` |
| Graphics | `mesa-dri-drivers mesa-vulkan-drivers mesa-va-drivers vulkan-loader` (base has zero graphics) |
| Fonts | `fontconfig default-fonts google-noto-color-emoji-fonts google-noto-emoji-fonts` (base has no fontconfig at all) |
| Keyring/security | `gnome-keyring gnome-keyring-pam` + PAM edit in `/etc/pam.d/greetd`; **`polkit-kde`** (polkit-gnome is retired Fedora-wide — verified absent) |
| Net/hardware | `NetworkManager-wifi wpa_supplicant linux-firmware microcode_ctl brightnessctl playerctl NetworkManager-tui` |
| Apps/helpers | `foot wl-clipboard nautilus cava qt6-qtmultimedia dconf glib-networking flatpak` |
| Locale | `langpacks-en` (or `glibc-all-langpacks` when more locales wanted) |

### 3.3 Tier 2 — DMS stack
`dms dms-cli dms-greeter quickshell-git matugen danksearch dgop material-symbols-fonts` (COPRs above)

### 3.4 Tier 3 — explicitly-opted-out / optional
- **Do NOT install:** `swaylock swayidle swaybg fuzzel waybar alacritty` — niri's spec only *Recommends* them, DMS replaces them (lock, bar, launcher, notifications, polkit agent). Keep `foot` as the terminal (niri's default binding spawns alacritty — rebind to what we ship).
- **Optional later:** gstreamer plugins, cups suite, avahi/nss-mdns, bluez, xdg-user-dirs-gtk, ibus, noto-cjk fonts, `cliphist` (COPR-only on F43 — DMS has built-in clipboard history, skip).

### 3.5 Base already covers (do NOT reinstall)
`sudo dnf5 podman skopeo bootc firewalld chrony NetworkManager openssh polkit dbus-broker systemd-udev bubblewrap libxkbcommon xkeyboard-config selinux-policy-targeted`

---

## 4. Config placement & integration

### greetd / DMS greeter (system-level)
- `/etc/greetd/config.toml`:
  ```toml
  [terminal]
  vt = 1

  [default_session]
  user = "greeter"
  command = "/usr/bin/dms-greeter --command niri -C /etc/greetd/niri/config.kdl"
  ```
- Enable: `systemctl enable greetd.service`; default `graphical.target`; display-manager alias.
- PAM: keyring unlock via `gnome-keyring-pam` needs the `greetd` PAM service file adjusted (add `pam_gnome_keyring.so` lines).
- SELinux: `greetd-selinux` package (base has selinux-policy-targeted at `/usr/lib/selinux`).

### User-level (via /etc/skel)
- `/etc/skel/.config/niri/config.kdl` + `dms/{colors,layout,alttab,binds}.kdl` fragments; env block `QT_QPA_PLATFORM=wayland`, `XDG_CURRENT_DESKTOP=niri`;
- `layer-rule { match namespace="^quickshell$" place-within-backdrop true }`
- `/etc/skel/.config/DankMaterialShell/` — DMS config stays user-level; theme sync via `dms-greeter sync` after first login
- **Autostart:** bake `systemctl --global add-wants niri.service dms` at build (**do NOT** also add `spawn-at-startup "dms" "run"` to niri config — double-start bug)
- `wayland-sessions/niri.desktop` ships inside the niri RPM — nothing to do

### systemd presets (files, `NN-category.preset`)
- `80-niri.preset` (compositor), `80-network.preset` (NetworkManager on, systemd-networkd off), user presets enabling `pipewire.socket`, `wireplumber.service`, `pipewire-pulse.socket`
- `99-default-disable.preset` opt-in model (GNOME OS pattern)

### Flatpak
- `flatpak` + sha256-pinned `flathub.flatpakrepo` → `/usr/share/flatpak/remotes.d/`
- **flatpak preinstall:** base has no `flatpak-preinstall.service` (Silverblue shipped it) → we ship our own once-only first-boot unit (marker-file guarded) that runs `flatpak preinstall` from `/usr/share/flatpak/preinstall.d/` (existing `custom/flatpaks/*.preinstall` pipeline stays)

### Bootc image integration steps (copy verbatim from Dakota/GNOME OS; a missed step = boot loop)
1. `mkdir /boot`; `/sysroot/ostree` relative symlink (GNOME OS: `/sysroot/ostree` exists in image)
2. `/var`-relative symlinks: `/home → var/home`, `/root → var/roothome`, `/opt → var/opt`, `/mnt → var/mnt`
3. `touch /etc/machine-id`
4. `10-bootc.conf` tmpfiles (GNOME OS pattern) + `prepare-root.conf`: `[composefs] enabled = yes`, `[sysroot] readonly = true` (only if we adopt composefs)
5. `/usr/lib/bootc/install/00-defaults.toml` with explicit root filesystem type — **bootc no longer defaults it; `bootc install to-disk` fails without it** (Dakota regression PR #497)
6. `systemd-sysusers` → `glib-compile-schemas` → `/usr/etc`→`/etc` merge → `dconf update` → `ldconfig -r /` (stale ldconfig cache caused a GNOME Shell boot loop in Dakota)
7. `bootc container lint --fatal-warnings` (already in CI pipeline)

---

## 5. Pluto file-organization plan

```
build/
├── 00-image-info.sh            # unchanged (ARG-driven)
├── 10-build.sh                 # mostly unchanged (brew/custom overlays)
├── 15-desktop-packages.sh      # NEW: COPR enable (isolated) + manifest pyramid install
├── 16-niri-config.sh           # NEW: greetd/DMS/skel configs, presets, bootc integration steps
├── 17-firstboot.sh             # NEW: first-boot units (user creation, flatpak preinstall)
├── packages/                   # NEW — the manifest of record (dakota/GNOME-OS pattern)
│   ├── base.lst                #   (empty — base covers; documented, not installed)
│   ├── desktop.lst             #   Tier 1
│   ├── dms.lst                 #   Tier 2
│   ├── apps.lst                #   Tier 3 optional
│   └── optional.lst            #   future/optional
└── copr-helpers.sh             # existing, reused
custom/
├── niri/                       # NEW: config.kdl fragments → /etc/skel/.config/
├── dms/                        # NEW: DankMaterialShell defaults → /etc/skel/.config/DankMaterialShell/
├── greetd/                     # NEW: config.toml, pam.d/greetd, graphical.target wiring
├── systemd/                    # NEW: units (flatpak-preinstall, firstboot-user) + NN-category.preset
├── brew/  flatpaks/  ujust/    # unchanged
```

### Containerfile changes
- `FROM quay.io/hummingbird-community/bootc-os:latest@sha256:<live digest>` (re-verify digest at write time)
- ARGs: `BASE_IMAGE_NAME="hummingbird"`, `FEDORA_MAJOR_VERSION="43"` (comment: bump when !15860 rolls), header comment base-options list gains bootc-os
- Keep ctx multi-stage (`@projectbluefin/common` + `@ublue-os/brew` overlays — compat unvalidated against bootc-os; keep, audit later)

### CI (unchanged, verified compatible)
- `build-image.yml`, `pr-validation.yml` (`validate`), promotion main→stable, keyless cosign, `bootc container lint` — all base-agnostic; image name/owner derived from repo metadata
- Renovate: replace silverblue "no major upgrade" rule with a **bootc-os rule: digest updates auto-merge but batched** (~daily rebuilds → weekly batches)
- `ENABLE_RECHUNKING` stays `"false"` (base is already chunkah-optimized)
- Do NOT adopt Konflux/EC/Testing Farm — not transferable to GitHub Actions

### Renovate note
Base is rolling: digest pin + batched updates is the linchpin. Plan for the base to switch Fedora release mid-cycle (F43→F44 via !15860) and for a mixed-version window (F44 kernel + fc43-era userspace).

---

## 6. From-scratch assembly reference patterns (what Dakota/GNOME OS taught)

1. **One manifest of record** — commented, category-grouped `.lst` files concatenated into one `dnf5 install -y $(cat ...)` transaction; never scattered install lines across scripts.
2. **Treat the base as a junction** — one documented delta (adds/removes/overrides) auditable in one place.
3. **Session packaging pattern** — `wayland-sessions/*.desktop` + `TryExec=` guard + systemd user target (Dakota's gamescope-session template) — niri RPM already ships this.
4. **Presets as files** with opt-in model (`99-default-disable.preset`).
5. **Portals/audio/flatpak as manifest sections**, not post-install hacks; pinned Flathub repo file.
6. **Optional: generated `/usr/manifest.json`-style BOM** (dnf transaction list) + git build stamp into the image (GNOME OS `collect_manifest` analogue).
7. **FHS/bootc skeleton hygiene** — see §4 bootc integration steps.
8. **First-boot units must self-remove** (or marker-file guard) to avoid reruns.

---

## 7. Open decisions (pending user)

1. **First user creation** — greetd has no GNOME-style first-run. Options: (a) first-boot unit that creates a user (prompt or default), (b) user created post-install from console/SSH. TBD.
2. **DMS channel** — stable (`avengemedia/dms`) vs git (`dms-git`, tunaOS's choice). TBD.
3. **`IMAGE_PRETTY_NAME`** — deferred ("My Custom OS" → e.g. "Pluto"). TBD.
4. Optional extras under DMS — lean (recommended) vs keep sway*/fuzzel/waybar fallbacks.

---

## 8. Rollout phases

1. **A — Build:** implement §3–§5 → `shellcheck`/YAML/`just --list` → **local `just build`** (podman/buildah available) → push `main` → CI green.
2. **B — Boot test:** `just build-qcow2` + `run-vm-qcow2` — prove greetd greeter works, niri boots, DMS runs, audio/network/wifi work, Flathub reachable, first-boot units ran.
3. **C — Promote:** after `:stable-testing` behaves, let the auto promotion land on `stable`.
4. **D — Iterate:** track !15860 (F44 roll), audit common-overlay SELinux assumptions (`/usr/lib/selinux`), kernel/firmware checks, adjust `FEDORA_MAJOR_VERSION`.

---

## 9. Reference materials & files

Research archive (in-repo, see `docs/research/README.md` for the index):
- `docs/research/hummingbird-research.md` — original full-site research
- `docs/research/hummingbird-research-2.md` — primary-source verification (lockfile, MR !15860, f44)
- `docs/research/dakota-analysis.md` — projectbluefin/dakota (BuildStream, from-scratch assembly)
- `docs/research/gnome-os-analysis.md` — GNOME/gnome-build-meta (manifest pyramid, bootc graph)
- `docs/research/niri-packages.md` — niri + DMS + tunaOS package manifest research
- `docs/research/bootc-vs-fedora-diff.md` (+ `bootc-os-packages.txt`, `fedora-workstation-packages.txt`) — package diff
- `docs/research/bluefin-packages.md` — bluefin TOML manifest verification + package harvest
- `docs/research/common-brew-analysis.md` — common/brew overlay content audit

Source clones used by the research agents (scratch, not archived):
`/tmp/opencode/{hummingbird-containers,dakota,gnome-build-meta,dms,niri-refs/tunaOS,common,brew,bluefin,fedora-comps}`

Reference repos (upstream):
- tunaOS builder (canonical niri+DMS bootc reference): `github.com/tuna-os/tunaOS` — `manifests/desktops/niri.yaml`, `build_scripts/desktop/niri.sh`, `build_scripts/checks/verify-branding-niri.sh`
- DMS: `github.com/AvengeMedia/DankMaterialShell` · greeter: `github.com/AvengeMedia/dank-greeter`
- bonus: `github.com/gabeklavans/bazzite-niri`

---

## 10. Gotcha checklist (things that WILL bite)

- [ ] niri's `Recommend`s are not pulled (installWeakDeps=false) — install sway*/fuzzel/waybar only if dropping DMS coverage; rebind terminal
- [ ] `polkit-gnome` retired — use `polkit-kde`
- [ ] No fontconfig in base — fonts are Tier 1, not optional
- [ ] C-only locale in base — `langpacks-en` needed
- [ ] `xdg-desktop-portal-niri` doesn't exist — niri spec points at `-gnome`
- [ ] greetd needs PAM keyring lines + `greetd-selinux`
- [ ] `quickshell` not in F43 — COPR `avengemedia/danklinux`
- [ ] One dnf transaction per COPR (tunaOS#1009)
- [ ] /etc/machine-id + symlinks + `00-defaults.toml` or `bootc install to-disk` fails / boot loops
- [ ] Double-start DMS (add-wants vs spawn-at-startup) — pick one
- [ ] Base is rolling: digest pin + Renovate batching mandatory; expect F43→F44 mid-cycle switch + mixed-version window
- [ ] SELinux store at `/usr/lib/selinux` — audit common overlay for `/etc/selinux` assumptions
- [ ] systemd-firstboot masked in base — first-run/user-creation flow is ours to design (§7.1)
- [ ] `flatpak-preinstall.service` must be authored by us
- [ ] Re-verify `bootc-os:latest` digest at FROM-line write time; verify Hummingbird base repo parity with F43 stable before first build (tunaOS note)
