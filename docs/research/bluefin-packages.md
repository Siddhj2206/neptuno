# projectbluefin/bluefin — Package List System Research

**Repo**: https://github.com/projectbluefin/bluefin (clone at commit `c442e5c46f6d3a0e95dda5b1d6794dc7f56906ae`, "chore: promote testing to main (#1093)", 2026-08-18)
**Base image**: `quay.io/fedora-ostree-desktops/silverblue` (Justfile: `base_image_org := "quay.io/fedora-ostree-desktops"`, `base_image_name := "silverblue"`)
**Variants**: `bluefin` (main) and `bluefin-nvidia` flavors.

---

## 1. TOML CLAIM: VERIFIED ✅

projectbluefin/bluefin uses **exactly one TOML package manifest**:

```
build_files/packages/base.toml
```

It is the only `.toml` in the repo (other TOML files: `cliff.toml` for changelog tooling; a dynamically generated `cliff-consumer-validation.toml` in a workflow; a bootc `kargs.d/00-nvidia.toml` written by the akmod script — none are package manifests).

### Exact format (verbatim structure)

```toml
# Package manifest for the bluefin base image.
# Read by build_files/base/03-packages.sh via build_files/shared/read-packages.
#
# Sections:
#   [multimedia_overrides]   packages synced from fedora-multimedia repo
#   [fedora]                 base Fedora packages, all versions
#   [fedora_v42]             additions for Fedora 42 only
#   [fedora_v43]             additions for Fedora 43 only
#   [fedora_v44]             additions for Fedora 44 only
#   [excluded]               packages removed from the base image

[fedora]
packages = [
    "adw-gtk3-theme",
    "adwaita-fonts-all",
    "alsa-firmware",
    ...
    "zsh",
]

[fedora_v43]
packages = [
    "evolution-ews-core",
    "gnupg2-scdaemon",
]

[excluded]
packages = [
    "default-fonts-cjk-sans",
    "fedora-bookmarks",
    ...
    "yelp",
]
```

**Schema rules (observed)**:
- Flat `[section]` tables; each section has exactly one key: `packages = [ "pkg", ... ]`.
- Entries are **plain dnf5 package names/globs** — no versions, no flags, no reasons attached per entry.
- **Comments** are the reason/notes mechanism (TOML `#`), placed above tables or inline.
- **Version pins** are NOT expressed in the TOML. Pinned overrides are applied *after* install via `dnf5 versionlock add` in the consuming script (see below).
- **Version-gated sections**: `[fedora_v42]` / `[fedora_v43]` / `[fedora_v44]` — script selects `fedora_v${FEDORA_MAJOR_VERSION}` with `|| true` fallback when absent.
- An explicit **`[excluded]`** section drives post-install removal — a first-class "uninstall list" concept worth copying.

### How it's consumed

1. **Reader**: `build_files/shared/read-packages` — a 34-line Python 3.11+ script:
   ```python
   # Usage: read-packages <manifest.toml> <section>
   import sys, tomllib
   ...
   data = tomllib.load(f)
   if section not in data:
       print(f"read-packages: section '{section}' not found in {path}", file=sys.stderr)
       sys.exit(1)
   for pkg in data[section].get("packages", []):
       print(pkg)
   ```
   → prints one package per line to stdout, **exits 1 if the section is missing or malformed** (errors propagate via `set -euo pipefail` in the caller).

2. **Consumer**: `build_files/base/03-packages.sh` (the numbered-script convention — note: packages all live in ONE manifest, not per-script `.lst` files):
   ```bash
   READ_PKGS="python3 /ctx/build_files/shared/read-packages"
   PKGS_TOML="/ctx/build_files/packages/base.toml"
   readarray -t FEDORA_PACKAGES < <($READ_PKGS "$PKGS_TOML" fedora)
   readarray -t _ver_pkgs < <($READ_PKGS "$PKGS_TOML" "fedora_v${FEDORA_MAJOR_VERSION}" 2>/dev/null || true)
   readarray -t OVERRIDES < <($READ_PKGS "$PKGS_TOML" multimedia_overrides)
   dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
   dnf5 versionlock add "${OVERRIDES[@]}"
   dnf5 -y install --enablerepo='tailscale-stable' --enablerepo='fedora-multimedia' -x PackageKit* "${FEDORA_PACKAGES[@]}" tailscale ffmpeg{,-libs} ...
   readarray -t EXCLUDED_PACKAGES < <($READ_PKGS "$PKGS_TOML" excluded)
   remove_excluded_packages EXCLUDED_PACKAGES
   ```
   Note: the script ALSO installs curated multimedia/cli packages **inline** (not in the TOML): `tailscale`, `ffmpeg{,-libs}`, `libavcodec`, `@multimedia` (dnf5 group), `gstreamer1-plugins-{bad-free,bad-free-libs,good,base}`, `lame{,-libs}`, `libfdk-aac`, `libjxl`, `ffmpegthumbnailer`, plus `uupd` from COPR. So bluefin's TOML is the manifest-of-record for the *base* set, but not 100% exhaustive of every RPM.

3. **Helpers** (`build_files/shared/package-lib.sh`):
   - `install_fedora_packages ARRAY_NAME` — bulk install
   - `remove_excluded_packages ARRAY_NAME` — only removes packages actually installed (`rpm -qa --queryformat='%{NAME}\n'` filter)
   - `assert_packages_present ARRAY_NAME` — post-install verifier: exits 1 with a missing-list if any package didn't land. **This is the error-handling / completeness gate.**

4. **COPR isolation** (`build_files/shared/copr-helpers.sh`, security invariant): `copr enable` → `copr disable` *immediately* → `dnf5 install --enablerepo="$repo_id"`. Never install with a COPR left enabled (repo-priority poisoning).

5. **Validation/tests**:
   - `.pre-commit-config.yaml` includes `check-toml` (pre-commit-hooks) on the manifest.
   - `tests/unit/03-packages_test.bats` (bats) stubs `dnf5`/`rpm`, runs the real script against the real TOML, asserts per-version and per-package behavior. `tests/unit/21-container-native-iso_test.bats` also reads the TOML.
   - `docs/skills/packages/SKILL.md` is the decision tree: GUI app → Flatpak, CLI/user tool → Homebrew, required system dep → Fedora RPM, third-party → isolated COPR. "Put base package data in the package manifest, not an inline shell array."

6. **Containerfile wiring**: Stage 1 (`RUN` with `--mount=type=cache,dst=/var/cache/libdnf5`, bind-mounted `/ctx/build_files`) runs `03-packages.sh`, `04-install-kernel-akmods.sh`, `05-override-install.sh` in sequence. Kernel/akmod/variant packages (v4l2loopback, nvidia-container-toolkit-base, zfs stack, kernel RPMs) are handled by `04-install-kernel-akmods.py` (Python), NOT the TOML.

**Error handling summary**: malformed TOML → tomllib raises → script dies; missing section → exit 1 with stderr message; `set -ouex pipefail` everywhere; `dnf5` failures abort the layer; missing-but-required packages caught by `assert_packages_present`; excluded-removal silently skips uninstalled packages.

---

## 2. Full harvested package set (installed RPMs, dnf5-friendly names)

### From `base.toml` [fedora] — 64 packages
| Group | Packages |
|---|---|
| Bootstrap/CLI | `distrobox`, `fish`, `zsh`, `fzf`, `fastfetch`, `gum`, `just`, `make`, `gcc`, `gcc-c++`, `git-credential-libsecret`, `zenity`, `openssh-askpass` |
| Desktop foundation (WM-agnostic) | `wl-clipboard`, `xdg-terminal-exec`, `waypipe`, `flatpak-spawn`, `firewall-config`, `nautilus-gsconnect` |
| Compositor/HW accel | `mesa-libGLU`, `libva-utils`, `ddcutil`, `evtest`, `igt-gpu-tools`, `switcheroo-control`, `input-remapper`, `libratbag-ratbagd`, `openrgb-udev-rules`, `libcamera-gstreamer`, `libcamera-tools`, `pipewire-libs-extra` |
| Audio/firmware | `alsa-firmware`, `alsa-tools-firmware` |
| Fonts | `adwaita-fonts-all`, `google-noto-sans-cjk-vf-fonts` |
| Theme/icons | `adw-gtk3-theme`, `libappindicator-gtk3`, `libayatana-appindicator-gtk3` (tray/indicator support) |
| Input methods | `ibus-mozc`, `mozc`, `ibus-unikey` (GNOME-flavored) |
| Storage/drivers | `libblockdev-btrfs`, `libblockdev-dm`, `libblockdev-lvm`, `libblockdev-mpath`, `libxcrypt-compat` |
| Network | `wireguard-tools`, `gvfs-nfs`, `waypipe` |
| GNOME-only (for comparison) | `gnome-tweaks`, `gnome-ponytail-daemon`, `python3-gnome-ponytail-daemon` (Wayland GUI-test harness), `slitherer` (Wayland test input tool), `nautilus-gsconnect`, `adw-gtk3-theme` |
| Boot/ISO/install | `bootc`, `bootupd`, `dracut-live`, `anaconda-live`, `livesys-scripts`, `grub2-efi-x64-cdboot`, `isomd5sum`, `squashfs-tools`, `xorriso`, `containerd` |
| GUI apps pulled as RPM | `firefox` |
| Other | `gnupg2-scdaemon` (F43+), `evolution-ews-core` (F42/43, TODO-removed in F44) |

### From `[multimedia_overrides]` — 12 packages (negativo17 fedora-multimedia, versionlocked)
`intel-gmmlib`, `intel-mediasdk`, `intel-vpl-gpu-rt`, `libheif`, `libva`, `libva-intel-media-driver`, `mesa-dri-drivers`, `mesa-filesystem`, `mesa-libEGL`, `mesa-libGL`, `mesa-libgbm`, `mesa-vulkan-drivers`

### Inline in `03-packages.sh` (not in TOML)
`tailscale` (tailscale-stable repo), `ffmpeg`, `ffmpeg-libs`, `libavcodec`, `@multimedia` (group), `gstreamer1-plugins-bad-free`, `gstreamer1-plugins-bad-free-libs`, `gstreamer1-plugins-good`, `gstreamer1-plugins-base`, `lame`, `lame-libs`, `libfdk-aac`, `libjxl`, `ffmpegthumbnailer`, `uupd` (COPR ublue-os/packages)

### `04-install-kernel-akmods.py` (variant-specific kmods + tooling)
`v4l2loopback`, `nvidia-container-toolkit-base` (nvidia flavor), zfs stack (`kmod-zfs`, `libnvpair`, `libuutil`, `libzfs`, `libzpool`, `python3-pyzfs`, `zfs`), full `kernel`/`kernel-core`/`kernel-modules*`/`kernel-devel` + akmods payload.

### From `[excluded]` — 15 packages (removed post-install)
`default-fonts-cjk-sans`, `fedora-bookmarks`, `fedora-chromium-config`, `fedora-chromium-config-gnome`, `fedora-third-party`, `firefox-langpacks`, `gnome-extensions-app`, `gnome-shell-extension-background-logo`, `gnome-software`, `gnome-software-rpm-ostree`, `gnome-terminal-nautilus`, `google-noto-sans-cjk-fonts`, `podman-docker`, `totem-video-thumbnailer`, `yelp`

### Notable for pluto (niri / non-GNOME / audio-portals-firmware-flatpak)
- **niri-relevant additions bluefin made over stock silverblue**: `wl-clipboard`, `xdg-terminal-exec`, `waypipe`, `switcheroo-control`, `input-remapper`, `libratbag-ratbagd`, `evtest`, `igt-gpu-tools`, `ddcutil`, `openrgb-udev-rules`, `libva-utils`, `pipewire-libs-extra`, `libcamera-*` (full camera stack), `alsa-firmware` + `alsa-tools-firmware`, `flatpak-spawn`, `firewall-config`, `libappindicator-gtk3`/`libayatana-appindicator-gtk3` (tray — needed when there's no GNOME Shell), `gvfs-nfs`, `wireguard-tools`.
- Not applicable to niri: `gnome-ponytail-daemon`/`python3-…`/`slitherer` (they're actually Wayland-testing tools — could still be useful to pluto's CI!), `ibus-mozc`/`mozc`/`ibus-unikey`, `adw-gtk3-theme`/`nautilus-gsconnect`/`gnome-tweaks`.
- Bluefin does NOT install `xwayland`, `xdg-desktop-portal-*`, or pipewire/wireplumber explicitly — they arrive via silverblue base. For a raw bootc-os rebase, pluto should verify those are present in the Hummingbird base (they generally are, but portal/pipewire presence should be asserted with `assert_packages_present`-style checks since niri depends on `xdg-desktop-portal-gtk`/`-hyprland`-style backends).

---

## 3. Config / first-boot conventions (bluefin)

No `skel/` dir — user-level defaults are handled by **ublue-os/setup-services hooks**:

```
system_files/shared/
├── etc/dconf/db/distro.d/04-bluefin-custom-command-menu      # dconf system defaults
├── etc/profile.d/90-bluefin-starship.sh, 91-bluefin-aliases.sh
├── etc/rpm-ostreed.conf
├── usr/share/ublue-os/user-setup.hooks.d/12-gnupg.sh, 20-framework.sh, 99-privileged.sh
├── usr/share/ublue-os/privileged-setup.hooks.d/10-tailscale.sh, 11-framework-ucsi-workaround.sh, 99-flatpaks.sh
├── usr/lib/systemd/system/{flatpak-nuke-fedora,bootc-unified-storage,bluefin-stats-refresh}.service
├── usr/lib/systemd/system/bluefin-stats-refresh.timer
├── usr/lib/udev/rules.d/61-amd-s2idle-hp.rules
├── usr/lib/modprobe.d/fw-charge-control.conf
├── usr/share/flatpak/preinstall.d/bazaar.preinstall
└── usr/share/gnome-shell/extensions/… (11 git submodules, built by build-gnome-extensions.sh)
```

Patterns:
- **Numbered hook scripts** (10-/12-/20-/99-) sourced from `/usr/lib/ublue/setup-services/libsetup.sh` with a `version-script flatpaks privileged 1 || exit 0` version guard.
- systemd **units under `usr/lib/systemd/system`** straight into the image; enabled where needed in `17-cleanup.sh`/`18-workarounds.sh` (`systemctl enable/pre-setup`).
- **bootc kargs** injected via `/usr/lib/bootc/kargs.d/*.toml` files (`00-nvidia.toml`: `kargs = ["rd.driver.blacklist=nouveau", …]`) — directly relevant to pluto (e.g. niri shares this mechanism).
- Firewall defaults via `/usr/lib/firewalld/zones/`; Flathub flatpak remote switch in `17-cleanup.sh`.
- Layer hygiene: scripts are *bind-mounted* into the build (`--mount=type=bind,from=ctx-build,source=/build_files,target=/ctx/build_files`) so edited scripts don't invalidate RPM layers; `rechunk` attrs (`setfattr -n user.component -v bluefin-docs`) for big files.

---

## 4. What I could NOT verify

- Whether `@multimedia` group content differs between silverblue base and raw bootc-os (group membership is repo-side, not visible in the clone).
- Bluefin's CI-side TOML validation beyond pre-commit `check-toml` (workflows only showed cliff toml usage).
- Whether the inline packages in `03-packages.sh` (ffmpeg family, tailscale) are planned to migrate into `base.toml` (comments suggest the TOML is the direction of travel; SKILL.md says "not an inline shell array").
- `ublue-os/config` / `ubuntu-os` shared inputs were not checked (out of scope; direct config checkout not present in this repo — it uses setup-services hooks instead).
