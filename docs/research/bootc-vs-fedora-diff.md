# bootc-os vs Fedora Workstation (F43) — package-level comparison

- **Date**: 2026-08-28
- **bootc-os source**: Fedora Hummingbird `images/bootc-os/hummingbird/default` (lockfile pins fc43 content)
- **Workstation source**: official F43 comps (fedora-comps repo, `comps-f43.xml.in`), Fedora Workstation environment + its grouplist

## 0. Sources & extraction method

| Artifact | Location |
|---|---|
| bootc-os lockfile | `/tmp/opencode/hummingbird-containers/images/bootc-os/hummingbird/default/rpms/rpms.lock.yaml` (5764 lines; `- arch: aarch64` at line 4, `- arch: x86_64` at line 2870) |
| bootc-os explicit request | `images/bootc-os/hummingbird/default/rpms/rpms.in.yaml` (same dir) |
| bootc-os Containerfile | `images/bootc-os/hummingbird/default/Containerfile` |
| comps f43 | `/tmp/opencode/fedora-comps/comps-f43.xml.in` (pagure clone) — kojipkgs `comps-f43.xml.xz` returned 404, fell back to `git clone https://pagure.io/fedora-comps.git` (no `--depth`, pagure rejects shallow over dumb HTTP) |
| Package-name lists | `/tmp/opencode/bootc-os-packages.txt` (302 names), `/tmp/opencode/fedora-workstation-packages.txt` (752 names + type column) |

Extraction details:
- **Lockfile**: names extracted with regex `^    name: (\S+)` from the x86_64 section (line 2870 → EOF), deduped. aarch64 section exists but was not used; bootc-os is identical across arches modulo arch-specific kernel/grub/shim entries, so the x86_64 set is representative.
- **Workstation set**: union of `mandatory` **+** `default` `packagereq` entries from every group in `workstation-product-environment`'s grouplist (what a default dnf groupinstall of the env installs): `base-graphical, container-management, core, firefox, fonts, gnome-desktop, guest-desktop-agents, hardware-support, libreoffice, multimedia, networkmanager-submodules, printing, workstation-product, desktop-accessibility`. Verified there is **no separate `workstation-product-core` group in f43** — `workstation-product` exists (comps-f43.xml.in line 5458) and is itself named *"Fedora Workstation product core"*; the environment (`<id>workstation-product-environment</id>`, line 6049) references only `workstation-product` via `<groupid>` (line 6068). The old core group's package set has been folded into `workstation-product`.
- Fedora availability checks used: `https://src.fedoraproject.org/rpms/<name>` (HTTP 200 = project exists), Bodhi API `https://bodhi.fedoraproject.org/updates/?packages=<p>&releases=F43` (stable f43 build proof), and comps membership.

## 1. Counts

| Set | Size |
|---|---|
| bootc-os packages (x86_64, from lockfile) | **302** |
| Workstation comps env set (mandatory + default, 14 groups) | **752** |
| of which strictly mandatory | 90 |
| Overlap | **42** |
| bootc-os ⊄ Workstation | **260** |
| Workstation ⊄ bootc-os | **710** (~395 are font packages, ~33 firmware) |

Overlap (42): `NetworkManager acl attr audit bash bzip2 chrony coreutils cpio cryptsetup curl dnf5 dosfstools e2fsprogs file filesystem firewalld glibc gnupg2 iproute kbd less ncurses openssh-clients openssh-server podman policycoreutils polkit procps-ng psmisc rpm selinux-policy-targeted setup shadow-utils skopeo sudo systemd systemd-udev tar util-linux vim-minimal which`

Note: `coreutils` (not just `coreutils-single`) is present in both the lockfile (line 1972) and comps; `installWeakDeps: false` is set in `rpms.in.yaml`.

## 2. bootc-os ⊄ Workstation (260) — what the base gives beyond a WS install

The lockfile's explicit request (`rpms.in.yaml`) is 39 packages; everything else in the 302 is their dependency closure (built with weak deps off). Grouped:

- **Hummingbird identity/rebuilds**: `hummingbird-gpg-keys`, `hummingbird-release`, `hummingbird-repos` (repo metadata + keys for the hummingbird-project.io mirror).
- **Container/bootc/VM tooling** (server-ish): `bootc`, `bootupd` (+`rust-bootupd`), `ostree`/`ostree-libs`, `composefs`/`composefs-libs`, `crun`, `conmon`, `catatonit`, `containers-common`/`-extra`, `container-selinux`, `netavark`, `aardvark-dns`, `passt`/`passt-selinux`, `podman-sequoia`, `bubblewrap`, `cloud-utils`/`cloud-utils-growpart`, `dbus-python`, `python3-firewall`, `python3-nftables`, `firewalld-filesystem`.
- **Kernel + boot chain**: `kernel`, `kernel-core`, `kernel-modules`, `kernel-modules-core`, `grub2` + `grub2-efi-x64` + `grub2-pc` + `grub2-tools*`, `shim`/`shim-x64`, `mokutil`, `efibootmgr`, `efi-filesystem`/`efi-rpm-macros`, `os-prober`, `dracut`, `bootupd` (already counted).
- **Crypto/security plumbing**: `crypto-policies` + config, `openssl-fips-provider-upstream`, `rpm-sequoia`, `tpm2-tss`, `libfido2`, `audit-rules`, `authselect`/`authselect-libs`, `libpwquality`, `libkcapi*`, `p11-kit`/`p11-kit-trust`.
- **DNF/pkg stack**: `libdnf5`, `libdnf5-cli`, `librepo`, `libsolv`, `libmodulemd`, `zchunk`/`zchunk-libs`, `rpm-plugin-selinux`.
- **Minimal-base choices** (differ from WS deliberately): `coreutils-single`, `util-linux-core`, `glibc-minimal-langpack` (WS ships `glibc-all-langpacks` — base is C-locale only), `vim`+`vim-data`, `openssh` client+server daemons.
- **Everything else**: normal lib closure (`glib2`, `gnutls`, `krb5`, `openldap`, `libxml2`, `sqlite`, `lvm2`, `device-mapper`, `nftables`, `iptables-libs`, `NetworkManager-libnm`, `libndp`, `xkeyboard-config`, `libxkbcommon`…).

## 3. Workstation ⊄ bootc-os (710) — what a desktop needs that the base does NOT ship ⚠️

Everything below was confirmed absent from the bootc-os lockfile (grep `name: <pkg>$` = 0 hits) unless marked ✓.

### 3.1 Compositor / Wayland session
- **No compositor of any kind** ships in base. Workstation refs `gnome-shell` + `gnome-session-wayland-session` + `gdm`; for us: `niri`, `xwayland-satellite`.
- Base **does** ship the input/keymap groundwork: `libxkbcommon` ✓, `xkeyboard-config` ✓, and `systemd-udev` ✓.
- **Nothing X11** (no `libX11`, no `xorg-x11-*`, no `xwayland`); niri brings `xwayland-satellite` for X11 app compat.

### 3.2 Display / login / greeter
- `gdm` (WS) — irrelevant for niri. `greetd` + `tuigreet` — **in Fedora 43** (see §4; task assumption "greetd is COPR-only" is **refuted**).
- `regreet`, `wlgreet` — **not** in Fedora (verification: src.fedoraproject.org → 404).

### 3.3 Audio
- **No pipewire, no alsa userspace, no UCM**: `pipewire`, `pipewire-pulseaudio`, `pipewire-alsa`, `wireplumber`, `alsa-ucm`, `alsa-sof-firmware`, `alsa-firmware`, `alsa-utils` all absent. Base has no sound stack whatsoever.

### 3.4 GPU / video / mesa
- **No mesa at all**: `mesa-dri-drivers`, `mesa-vulkan-drivers`, `mesa-libEGL`, `mesa-libGL`, `vulkan-loader`, `libglvnd-gles` absent.
- No VA-API hardware decode: `libva-intel-media-driver` absent.
- No media framework: `gstreamer1-*` packages (openh264, libav, dav1d, good/bad-free/ugly-free plugins) absent.

### 3.5 Fonts + fontconfig
- **`fontconfig` itself is absent** — no font infrastructure at all.
- No core fonts: `dejavu-*-fonts`, `liberation-*-fonts`, `google-noto-emoji-fonts`, `default-fonts-*` meta packages, all absent. (WS `fonts` group = 394 packages.)

### 3.6 XDG plumbing & portals
- `xdg-utils`, `xdg-user-dirs`, `xdg-user-dirs-gtk` absent.
- `xdg-desktop-portal` and all backends (`-gnome`, `-gtk`) absent.
- `xdg-desktop-portal-niri` does not exist as a Fedora package (404); niri uses `xdg-desktop-portal-gnome` (see niri spec Recommends, §4).

### 3.7 Flatpak
- `flatpak` absent; Flathub is **not** preconfigured. WS uses `fedora-flathub-remote` (default in `workstation-product`).

### 3.8 Polkit agent & keyring
- `polkit` **daemon: present in base** ✓ (explicit in `rpms.in.yaml`, lockfile hit) — but **no auth agent** (`polkit-gnome` absent).
- `gnome-keyring` absent. `pam` ✓ + `systemd-pam` ✓ in base; the pam keyring module must be configured on top.
- `fprintd-pam`, `pcsc-lite`/`pcsc-lite-ccid` (smartcard) absent.

### 3.9 Desktop plumbing (GTK/GLib)
- `dconf` absent (no GSettings backend — config storage for GTK apps).
- `glib-networking` absent (GLib HTTP/TLS for apps).
- `at-spi2-core`/`at-spi2-atk` absent (a11y bus).
- `qt5-qtbase`, `qt5-qtbase-gui`, `qt5-qtdeclarative`, `qadwaitadecorations-qt5` absent (Qt app runtime + Adwaita decoration bridge).

### 3.10 First-boot / user / locale plumbing
- **`systemd-firstboot` is masked in bootc-os** — Containerfile lines 155–157:
  > `# Mask systemd-firstboot: its interactive prompts (locale, timezone, root`
  > `# password) hang on headless/VM boots.  Users who need firstboot can unmask it.`
  > `RUN ln -sf /dev/null ${NEWROOT}/usr/lib/systemd/system/systemd-firstboot.service`
  Implication: no interactive locale/timezone/root-password prompts; the image must bake `locale.conf`, timezone, and user accounts (base has `systemd-sysusers` ✓ and `systemd-pam` ✓ to create users at build).
- `accountsservice` absent (no AccountsService daemon; greetd/login managers can run without it — it's a GDM-centric service).
- `glibc-minimal-langpack` (base) vs `glibc-all-langpacks` (WS): non-C locales are limited until added.
- `hostname` package absent (basic `/bin/hostname`; `util-linux` still provides `hostnamectl`).

### 3.11 Networking extras
- `NetworkManager` ✓ base — but **not `NetworkManager-wifi`** (802.11 + wpa_supplicant integration!), nor `-wwan`, `-adsl`, `-bluetooth`, `-ppp`, vpn submodules. Also `wpa_supplicant` itself absent.
- `avahi`, `nss-mdns` absent.
- `systemd-resolved` absent (base uses systemd-networkd-free NM + stub; WS ships it as default).

### 3.12 Firmware / microcode
- **No `linux-firmware`**, no `amd-ucode-firmware`/`intel-gpu-firmware`/`nvidia-gpu-firmware`, no `microcode_ctl`, no `iwlwifi-*-firmware`, no `alsa-sof-firmware`, no `alsa-ucm`. Firmware is entirely bring-your-own (~33 firmware packages in the WS set). Note: `microcode_ctl` (WS mandatory in `workstation-product`) carries %post-style CPU microcode init — install explicitly at image build.

### 3.13 Printing / scanning / misc desktop apps (all absent, optional)
- `cups`, `cups-filters`, `cups-pk-helper`, `system-config-printer`, `hplip`, `sane-backends-drivers-scanners`, `foomatic*`, `gutenprint*`.
- `power-profiles-daemon`-family: WS ships `thermald`, `uresourced`, `systemd-oomd-defaults`, `zram-generator-defaults`, `plymouth` (boot splash), `PackageKit*`, `gnome-*` suite, `firefox`, `libreoffice*`, `toolbox`, `fwupd`, `colord`, `gvfs*`, `pcsc-lite*`.

## 4. Must-add shortlist for a niri desktop (F43 package names)

### Tier 1 — Required (core function; all plain `dnf5` from Fedora 43 repos)

| Purpose | Packages | Verified in F43 via |
|---|---|---|
| Compositor + X11 fallback | `niri`, `xwayland-satellite` | niri.spec f43 branch: `Requires: xwayland-satellite >= 0.7`; bodhi `niri-26.04-1.fc43` stable (also 25.08/25.11 series); src.fp.o 200 |
| Greeter/login | `greetd`, `tuigreet` | bodhi `greetd-0.10.3-6.fc43` + `tuigreet-0.9.1-7.fc43` stable update (2026-02-08) — **in Fedora, no COPR** |
| Audio | `pipewire`, `pipewire-pulseaudio`, `wireplumber` | pipewire/wireplumber src 200; `-pulseaudio` is a pipewire subpackage (comps `multimedia` group) |
| GPU | `mesa-dri-drivers`, `mesa-vulkan-drivers`, `vulkan-loader` | mesa src 200 (subpackages per comps `hardware-support`); vulkan-loader src 200 |
| Fonts | `fontconfig`, `dejavu-sans-fonts` (or `liberation-fonts`; WS also ships `google-noto-emoji-fonts`) | comps `fonts` group membership; fontconfig/liberation-fonts src 200 |
| Portals/XDG | `xdg-desktop-portal-gnome`, `xdg-desktop-portal-gtk`, `xdg-utils` | all src 200; niri spec `Recommends: xdg-desktop-portal-gnome` |
| Auth/keyring | `polkit-gnome` (agent; daemon already in base), `gnome-keyring` (niri spec `Recommends`) | src 200 |
| Desktop plumbing | `dconf`, `glib-networking`, `at-spi2-core` | src 200 |
| Flatpak | `flatpak` + enable Flathub remote (WS uses `fedora-flathub-remote` rpm) | src 200 |
| WiFi (laptops) | `NetworkManager-wifi`, `wpa_supplicant` | comps `networkmanager-submodules` group |
| Firmware/microcode | `linux-firmware`, `microcode_ctl`, `intel-gpu-firmware`, `amd-ucode-firmware`, `alsa-sof-firmware`, `alsa-ucm` | comps `workstation-product` (mandatory) + `hardware-support` |
| Runtime audio config | `alsa-ucm` (UCM profiles, comps `hardware-support`) | comps membership (part of alsa-lib src split in F43) |

### Tier 2 — Required for a stock niri UX (niri's default keybindings/startup apps) ⚠️

Fedora marks these `Recommends` in niri.spec, and **bootc image builds run with `installWeakDeps: false`** (`rpms.in.yaml`, first lines) — so they will **not** be pulled in automatically at container-commit time. Install explicitly:

- `swaylock` (lock shortcut), `waybar` (started at login per default config), `fuzzel` (launcher shortcut), `alacritty` (default terminal), `wireplumber` (already Tier 1).
- Source: niri.spec f43 — `Recommends: gnome-keyring / xdg-desktop-portal-gnome / xdg-desktop-portal-gtk / alacritty / fuzzel / swaylock / wireplumber / waybar`.

### Tier 3 — Nice-to-have

- Media: `gstreamer1-plugins-good`, `gstreamer1-plugins-bad-free`, `gstreamer1-plugin-libav`, `gstreamer1-plugin-openh264`
- Printing: `cups`, `cups-filters`, `system-config-printer`, `hplip`
- mDNS: `avahi`, `nss-mdns`
- Bluetooth: `NetworkManager-bluetooth`, `bluez` (WS: `gnome-bluetooth` depends on bluez)
- User dirs: `xdg-user-dirs-gtk` (creates ~/Documents, ~/Pictures…)
- Locales: `glibc-all-langpacks` (base ships `glibc-minimal-langpack` only)
- Power: `power-profiles-daemon` or `thermald` + `uresourced`
- Qt apps: `qt5-qtbase`, `qt5-qtbase-gui`, `qadwaitadecorations-qt5`
- IM: `ibus` + engines (comps `workstation-product` defaults)
- Smartcard/fingerprint: `pcsc-lite`, `pcsc-lite-ccid`, `fprintd-pam`
- Config tool: `niri-config` (GUI; separate Fedora package)

### COPR surprises (verified, source of truth = Bodhi API + src.fedoraproject.org)

| Package | In Fedora 43? | Evidence |
|---|---|---|
| `greetd` | ✅ **yes** | `greetd-0.10.3-6.fc43` stable update via Bodhi API (`updates/?packages=greetd&releases=F43`) |
| `tuigreet` | ✅ yes | `tuigreet-0.9.1-7.fc43` same stable update |
| `niri` | ✅ yes | `niri-26.04-1.fc43` + 25.11, 25.08 series |
| `xwayland-satellite` | ✅ yes | src 200; hard Requires of niri |
| `regreet` | ❌ **no** | src.fedoraproject.org/rpms/regreet → 404. COPR routes exist (`psoldunov/regreet`; historically `ublue-os/staging`) — see unverified note |
| `wlgreet` | ❌ no | src.fedoraproject.org/rpms/wlgreet → 404 |
| `xdg-desktop-portal-niri` | ❌ no | 404; use `xdg-desktop-portal-gnome` (niri's own recommendation, per spec Recommends) |

**Conclusion on COPRs**: nothing in the required Tier 1/2 list needs a COPR on F43 — the task's premise ("greetd lives in a copr") is outdated; greetd landed in Fedora proper (0.10.3-6.fc43). The only COPR pressure is if you want the GUI greeter `regreet` instead of TUI `tuigreet`.

## 5. What the base already provides (no reinstall needed)

Explicit in `rpms.in.yaml` (quotable): `NetworkManager audit bash bootc bootupd bubblewrap ca-certificates chrony cloud-utils-growpart containernetworking-plugins coreutils-single curl dbus-broker dnf5 dosfstools dracut e2fsprogs efibootmgr findutils firewalld fuse-overlayfs grep grub2 iproute kernel less openssh-clients openssh-server passwd podman polkit procps-ng python3 selinux-policy-targeted skopeo sudo systemd systemd-pam tar util-linux vim-minimal grub2-efi-x64 shim-x64`

- **`sudo` ✓, `dnf5` ✓, `podman` ✓** (plus `skopeo`, `bootc`) — our finpilot template's previous explicit installs of `sudo`/`dnf5`/`podman` are now redundant.
- `polkit` **daemon** ✓, `dbus-broker` ✓ (base's bus is dbus-broker, not dbus-daemon), `firewalld` ✓, `chrony` ✓, `openssh` (client+server) ✓, `gnupg2` ✓, `systemd-udev` ✓, `selinux-policy-targeted` ✓ (SELinux enforcing-ready), `bubblewrap` ✓ (container/sandbox helper).
- `libxkbcommon` + `xkeyboard-config` ✓ — the Wayland input groundwork compositors need.

## 6. Unverified / limits

- `ublue-os/staging` COPR current contents: API (`api_3/coprs/ublue-os/staging/packages/`) returned an empty item list — could not confirm whether it still carries `greetd`/`regreet` for F43. Historical 2026-05 build records exist (web search); `psoldunov/regreet` COPR confirmed alive via search result. Treat "regreet via COPR" as *available somewhere* but exact repo contents unconfirmed.
- kojipkgs `comps-f43.xml.xz` 404'd; used the pagure comps source (same data the release compose consumes).
- `greetd-0.10.3-6.fc43` ships in the f43 **updates** repo (stable 2026-02-08); pull it with `dnf5 install greetd` on a current F43 tree, not from a stale base image snapshot.
- DejaVu/`mesa-*`/`pipewire-*subpackages` verified by comps-f43 membership (comps has a `check-missing` CI against real packages) + src-project existence; I did not query F43 repodata directly.
- Lockfile counts are for the x86_64 section; aarch64 mirrors it (302 vs ~300) per section layout.
