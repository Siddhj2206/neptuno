# Homebrew integration in Dakota, Utah and finpilot — and whether Neptuno's wiring is right

**Date:** 2026-10-24
**Scope:** read-only source audit of the repositories listed below, plus one inspection of a live Neptuno image (`45.20261024`, this machine) to confirm what the build actually produces.
**Related:** this report covers *how each distro wires Homebrew up and enables it*; `common` and `ublue-os/brew` contents are documented in their own repositories.

## Sources inspected

| Repo | Clone path | Commit | Notes |
|---|---|---|---|
| `projectbluefin/dakota` | `/tmp/opencode/homebrew-research/dakota` | `49a53df78cf7d499514a07f62303b59c917811e7` (2026-10-23) | BuildStream; junction `gnome-build-meta` `gnome-51` @ `51.1-3-g24bd9e3` |
| `projectbluefin/utah` | `.../utah` | `028d3f41c2c2b808e115906d6e2cd9aa4e239970` (2026-10-24) | Hummingbird bootc; dnf5 package factory |
| `projectbluefin/finpilot` | `.../finpilot` | `0f96b01bb43161b7d768306faf40a67b5e7efbf5` (2026-10-24) | the template Neptuno forked from |
| `projectbluefin/common` | `.../common` | `3c4399e449e836184baa7f58ae0677c1f5cc9549` (2026-10-22) | ships `brew-preinstall`, `preinstall.d/`, `ublue-user-setup` |
| `ublue-os/brew` | `.../ublue-brew` | `373e0ac907ba33269522e37fd38f45894f1bd984` (2026-08-30) | the Homebrew OCI image; also Dakota's git element pin |
| `projectbluefin/brew` | `.../brew` | `6f0e89a07f902fcff674bde2e46ee7820729ee55` (2025-12-16) | **moved stub** — `README.md:1-2` says `# MOVED` → `ublue-os/brew`. Stale (`/var/home/linuxbrew`, `tmpfiles.d/homebrew.conf`); do not consume |
| Neptuno (fork under test) | `/var/home/sid/Documents/Projects/neptuno` | `f03945f973baaff082ee7016a8a33c520cd0f90f` | pins `common@sha256:c1b6fa4…` (built 2026-10-22) and `brew@sha256:393b567…` (same tag Utah pins) |

Pinned upstream images were verified to contain the files cited here: `common@c1b6fa4` is an image built 2026-10-22T21:44Z (same day as `common` HEAD), and the `brew@393b567` layer contains `system_files/usr/lib/systemd/system-preset/01-homebrew.preset` and `system_files/usr/share/homebrew.tar.zst`.

**Answers by number:** Q1 → §1, Q2 → §2, Q3 → §1–§4 and §9, Q4 → §7, Q5 → §8, Q6 → §5, Q7 → §9, verdict → §10.

---

## TL;DR

1. **Both new distros ship Homebrew, and neither changes the delivery mechanism**: a prebuilt tarball at `/usr/share/homebrew.tar.zst` plus systemd units, unpacked on first boot by `brew-setup.service`. Dakota pulls it as two BuildStream elements (one git, one `kind: docker`); Utah copies it straight out of `ghcr.io/ublue-os/brew`. No RPM, no package manager involvement.
2. **`brew-preinstall` lives in `common`, not in `ublue-os/brew`.** `ublue-os/brew` ships zero user units; its preset covers only `brew-setup.service`, `brew-update.timer`, `brew-upgrade.timer`.
3. **Enablement differs by build system, and the difference is load-bearing.** Dakota is BuildStream and gets both system *and global user* presets applied at image build by freedesktop-sdk's `prepare-image.sh` (`systemctl --root … --global preset-all`). finpilot/Neptuno/Utah are Containerfile builds where nothing applies user presets — `common`'s `01-brew-preinstall.preset` is inert there. Utah and Neptuno both compensate with `systemctl --global enable brew-preinstall.service`; **that call is required, not redundant.**
4. **Brewfile placement has two distinct meanings**, and the projects split cleanly: `/usr/share/ublue-os/homebrew/*.Brewfile` = declaration only (opt-in, ujust/ChairLift), `…/preinstall.d/*.Brewfile` = auto-installed for every user by `brew-preinstall.service`. Dakota and finpilot *declare*; Neptuno *auto-installs*.
5. **Neptuno's wiring works.** A live Neptuno image has all four symlink sets in `/etc`, `brew-preinstall.service` enabled and exited 0, and a state file listing the union of `common`'s 11 packages plus Neptuno's 14. What is wrong is one doc sentence, one overlay-order deviation, four duplicate declarations, and one undeclared runtime dependency (`jq`).

---

## Comparison table

| | **dakota** | **utah** | **finpilot** (template) | **Neptuno** (fork) |
|---|---|---|---|---|
| Base | freedesktop-sdk + gnome-build-meta via BuildStream, exported as bootc OCI (`kind: script` + `build-oci`) | `quay.io/hummingbird-community/os-minimal` + Utah RPM factory, bootc | `quay.io/fedora-ostree-desktops/silverblue:44` (Neptuno: `:45`) | same as finpilot, `silverblue:45` |
| Brew delivery | tarball, two BST elements: `brew.bst` (git `ublue-os/brew`) + `brew-tarball.bst` (`kind: docker ghcr:ublue-os/brew`) → `/usr/share/homebrew.tar.zst` | tarball copied from `ghcr.io/ublue-os/brew` `/system_files` → `/usr/share/homebrew.tar.zst` | same as Utah (`COPY --from=brew /system_files /oci/brew`, rsync to `/`) | same as finpilot |
| Brewfile source in repo | *(none of its own for preinstall)*; two opt-in files `files/just-overrides/{dakota-fonts,dakota-dev-flatpaks}.Brewfile`; one appended line to `common`'s `system-flatpaks.Brewfile` | *(none)* — everything inherited from `common` | `custom/brew/*.Brewfile` | `custom/brew/default.Brewfile` |
| Brewfile install location | `usr/share/ublue-os/homebrew/*.Brewfile` (from `common` + its own two), `…/homebrew/preinstall.d/*.Brewfile` (from `common` only) | inherited paths only; no `preinstall.d` of its own | `custom/brew/*.Brewfile` → `/usr/share/ublue-os/homebrew/` (declaration only) | `custom/brew/*.Brewfile` → `/usr/share/ublue-os/homebrew/preinstall.d/` (**auto-install**) |
| Auto-install? | only `common`'s `preinstall.d` (chairlift + 11 CLI tools) | same | only `common`'s `preinstall.d`; `custom/brew` is **not** auto-installed | `common`'s `preinstall.d` **plus** Neptuno's `default.Brewfile` |
| System units enabled | `brew-setup.service`, `brew-update.timer`, `brew-upgrade.timer` | same | same | same |
| User units enabled | `brew-preinstall.service` | `brew-preinstall.service`, `ublue-user-setup.service` | `brew-preinstall.service`, `ublue-user-setup.service` | same |
| Enablement mechanism | presets only: `01-homebrew.preset` (system) and `common`'s `01-brew-preinstall.preset` (global user), both applied at **build** by `prepare-image.sh` | explicit `systemctl enable` / `systemctl --global enable` in `scripts/configure-services.sh`, plus a system preset to survive bootc first-boot `preset-all`, plus `85-utah-desktop.preset` (user, inert) | explicit `systemctl enable` / `--global enable` in `build/10-overlay.sh` | same, in `build/10-build.sh` |
| `ublue-system-setup.service` | inherited, nothing enables it (see §11) | `systemctl enable` + preset line | `systemctl enable` | `systemctl enable` |
| `ublue-user-setup.service` | inherited, nothing enables it (see §11) | `systemctl --global enable` | `systemctl --global enable` | `systemctl --global enable` |

---

## 1. Dakota — yes, Homebrew ships (tarball via BuildStream)

Dakota has no RPM layer at all; Homebrew arrives as **two BST elements** and is *not* unpacked at build time.

**Units / shell integration / preset** — `dakota/elements/bluefin/brew.bst:6-22`:

```yaml
sources:
- kind: git_repo
  url: github:ublue-os/brew.git
  track: main
  ref: 373e0ac907ba33269522e37fd38f45894f1bd984
...
config:
  install-commands:
  - cp -r system_files/usr/ "%{install-root}%{prefix}/"
  - cp -r system_files/etc/ "%{install-root}%{sysconfdir}/"
```

**The Homebrew payload** — `dakota/elements/bluefin/brew-tarball.bst:7-14, 26-30`:

```yaml
- kind: docker
  url: ghcr:ublue-os/brew
  track: latest
  (?):
  - arch == "x86_64":
      ref: ce2de9ea1bd8ecfc3b64c0415ce85b9f22eb469be5307add0f46a0d8eecfb8db
  - arch == "aarch64":
      ref: aff477fa0ccbbb467946ed12e1ec6cd7726281e555daa152ef64af8f3106a5e6
...
  install-commands:
  - |
    install -Dm644 system_files/usr/share/homebrew.tar.zst \
      "%{install-root}%{datadir}/homebrew.tar.zst"
```

`brew-tarball.bst:20-21` declares `runtime-depends: [bluefin/brew.bst]`, so the tarball and the units always land together. Both are in the single manifest-of-record `dakota/elements/bluefin/deps.bst:14-15`, so they end up in the same composed OCI layer (`dakota/elements/oci/layers/bluefin.bst:1-13`).

Dakota also keeps a **host GCC + GNU Make closure** for Homebrew source builds (`elements/oci/layers/brew-toolchain.bst`, built from `brew-toolchain-closure.bst`) and appends the brew prefix to sudo's `secure_path` (`elements/bluefin/sudo-linuxbrew-path.bst:23-25`). Both exist because `bin/brew` hard-filters `PATH`; the rationale is documented in `.agents/skills/dakota-workstation/references/host-homebrew.md:26-63`.

**Brewfiles:** Dakota ships none for `preinstall.d`. It consumes `common`'s (`common.bst:108-111` copies `system_files/{bluefin,shared}/usr/` and `/etc/`), appends one Flatpak to a declaration Brewfile (`common.bst:159`), and installs its own two opt-in Brewfiles to the declaration directory only (`elements/bluefin/just-overrides.bst:31-32`):

```yaml
- install -Dm644 dakota-fonts.Brewfile "%{install-root}/usr/share/ublue-os/homebrew/dakota-fonts.Brewfile"
- install -Dm644 dakota-dev-flatpaks.Brewfile "%{install-root}/usr/share/ublue-os/homebrew/dakota-dev-flatpaks.Brewfile"
```

They are installed by `ujust install-dev-fonts` (`files/just-overrides/system.just:144`) — i.e. **declaration, not auto-install**.

**Enablement:** nothing in the repo calls `systemctl enable`. It relies on presets, and it works because the OCI element calls freedesktop-sdk's `prepare-image.sh`, which applies *both* preset scopes at build time:

`dakota/elements/oci/bluefin.bst:43-47`:

```
prepare-image.sh \
   --sysroot /layer \
   --initscripts /initial_scripts \
   --seed "%{sysroot-seed}" \
   --noroot --noboot >/dev/null
```

and inside that script (verified at tag `freedesktop-sdk-25.08.0`, the release line the `gnome-51` junction uses):

```sh
echo "Running systemctl preset-all" 1>&2
systemctl --root "${sysroot}" preset-all
echo "Running systemctl preset-all for all users" 1>&2
systemctl --root "${sysroot}" --global preset-all
```

So on Dakota the **preset files are the source of truth**, including the user-scope one. That is the one distro where `common`'s `01-brew-preinstall.preset` is actually effective on its own.

## 2. Utah — yes, Homebrew ships (tarball copied from the brew OCI image)

`utah/Containerfile:15-16` stages the brew image, `:55-58` copies it into the inputs stage, and `:169-175` lands it in the runtime layer together with `common` and Utah's own files:

```dockerfile
cp -a /tmp/utah-inputs/tmp/utah-common/. / && \
cp -a /tmp/utah-inputs/tmp/utah-bluefin/. / && \
cp -a /tmp/utah-inputs/tmp/utah-brew/. / && \
mv /usr/share/ublue-os/just/00-entry.just /usr/share/ublue-os/just/00-common.just && \
cp -a /tmp/utah-inputs/tmp/utah-local/. / && \
```

That single `cp` supplies `/usr/share/homebrew.tar.zst`, the five brew units, `01-homebrew.preset`, `profile.d/brew.sh`, and the fish integration. There is no separate brew layer and no RPM.

**Brewfiles:** Utah has **zero** `*.Brewfile` files of its own (`find utah -name '*.Brewfile'` → nothing) and no `homebrew/preinstall.d`. Everything comes from `common` (`shared/` + `bluefin/`, both copied above). Its own Homebrew feature, the Framework EC tool, is installed by a *user-setup hook* calling `brew install`, not by a Brewfile: `system_files/shared/usr/share/ublue-os/user-setup.hooks.d/20-framework.sh:20-58`.

**Enablement:** `scripts/configure-services.sh`:

```bash
enable_unit brew-setup.service            # :60
...
if user_unit_exists ublue-user-setup.service; then
    systemctl --global enable ublue-user-setup.service   # :261-263
fi
...
user_unit_exists brew-preinstall.service
systemctl --global enable brew-preinstall.service        # :269-270  (fails the build if absent)
```

System preset `system_files/shared/usr/lib/systemd/system-preset/85-utah-desktop.preset:16` also enables `ublue-system-setup.service`, and `configure-services.sh:80` enables it explicitly. `brew-update.timer` / `brew-upgrade.timer` are *not* mentioned anywhere in Utah — they are enabled by `ublue-os/brew`'s own `01-homebrew.preset` at bootc first-boot `preset-all`; Utah's docs rely on exactly that (`docs/skills/desktop-contract.md:99-107`: “a vendor preset such as brew's `01-homebrew.preset`”).

Utah also ships a **user** preset, `system_files/shared/usr/lib/systemd/user-preset/85-utah-desktop.preset:26-27`:

```
# Common installs the ChairLift GUI on login; enable globally at build time too.
enable brew-preinstall.service
```

and then says in `docs/skills/desktop-contract.md:143-148` that the preset alone is not enough:

> `brew-preinstall.service` installs the GUI into the shared Homebrew prefix on graphical login after user setup; … Common's `01-brew-preinstall.preset` alone does not enable it on Utah: **bootc applies system presets, not global user presets.** Enable this required unit with `systemctl --global enable` during composition and fail if it is absent.

That is correct (see §7). Utah's contract enforces it: `contracts/bluefin-desktop.toml:297-304` lists `brew-preinstall.service` and `ublue-user-setup.service` under `user_enabled`, “checked with `systemctl --global is-enabled`”.

## 3. finpilot — the template: Brewfiles are *declared*, never auto-installed

`finpilot/build/10-overlay.sh:85-87`:

```bash
# Brewfiles consumed by first-user Homebrew setup.
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/
```

No `preinstall.d`. `custom/brew/README.md:3-5` states the contract: “Brewfiles declared here are copied into the image at `/usr/share/ublue-os/homebrew/`. Users install them after boot; nothing is installed at build time.” Users install them by ujust recipe (`custom/ujust/custom-apps.just:18,25` → `brew bundle --file /usr/share/ublue-os/homebrew/<name>.Brewfile`), and the test suite pins the destination: `tests/template/10-overlay_test.bats:146-152` asserts `${HOMEBREW_DIR}/default.Brewfile`, where `HOMEBREW_DIR="${SANDBOX}/usr/share/ublue-os/homebrew"` (`:28`).

The template *does* still auto-install whatever `common` puts in `preinstall.d` — it rsyncs `common/shared` wholesale (`10-overlay.sh:52`), which includes `preinstall.d/{chairlift,system-cli}.Brewfile`.

Enablement, `10-overlay.sh:138-150`:

```bash
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer
systemctl --global enable brew-preinstall.service
...
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service
```

No ublue-user-setup hook for brew — `common` ships only `10-theming.sh` and `20-oem-brew.sh` in `user-setup.hooks.d/`.

## 4. Neptuno — the fork under test

Two deviations from the template, both in `build/10-build.sh:74-79`:

```bash
echo "::group:: Copy Custom Files"
# brew: every Brewfile auto-installed at first login (hash-tracked)
mkdir -p /usr/share/ublue-os/homebrew/preinstall.d/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/preinstall.d/
```

and the enablement block `10-build.sh:57-72`, which is the template's block plus `uupd`/`countme`/`dconf`:

```bash
# Enable the units the common/brew overlays ship, one by one. Deliberately NOT
# `systemctl preset-all`: ...
# The overlay preset files (common system-preset 01/02/03, user-preset
# 01-brew-preinstall; brew system-preset 01-homebrew) are shipped but no longer
# the source of truth here.
...
systemctl enable brew-setup.service brew-update.timer brew-upgrade.timer
systemctl --global enable brew-preinstall.service
```

Overlay order is also reversed vs the template: Neptuno rsyncs brew first (`:12`) then `common/shared` (`:16`); finpilot rsyncs `common/shared` (`:52`) then brew (`:60`). **This is currently harmless** — I diffed the file lists of `common/system_files/shared` and `ublue-os/brew/system_files`: zero overlapping paths. It is still a contract deviation (finpilot's header at `10-overlay.sh:16-28` documents "1. common/shared, 2. ublue-os/brew" precisely so brew's shell integration wins any future collision).

`custom/brew/README.md` documents the intended semantics (“auto-preinstalled … applied at first login … content-addressed”) but contains one factual error at `:29-31`: “`brew-preinstall.service` runs in the graphical session after brew is extracted (`brew-setup.service`); **both are user units**”. `brew-setup.service` is a system unit.

**Live-image verification** (this machine, `Neptuno 45.20261024`):

| Check | Result |
|---|---|
| `/usr/share/ublue-os/homebrew/preinstall.d/` | `chairlift.Brewfile`, `default.Brewfile`, `system-cli.Brewfile` |
| `/etc/systemd/system/{default,multi-user}.target.wants/brew-setup.service` | present |
| `/etc/systemd/system/timers.target.wants/brew-{update,upgrade}.timer` | present |
| `/etc/systemd/user/graphical-session.target.wants/brew-preinstall.service` | present (so `--global enable` worked) |
| `systemctl --user status brew-preinstall.service` | `active (exited)`, `code=exited, status=0/SUCCESS`, started 12:03 today |
| `~/.local/share/ublue-os/brew-preinstall-state.json` | one hash; 25 formulae; `casks: ["projectbluefin/tap/chairlift"]` |
| owner of `/home/linuxbrew/.linuxbrew` | `1000:1000` |

The 25 formulae are exactly `common`'s 11 (`fzf, glow, htop, rclone, restic, smartmontools, squashfs, starship, tcpdump, tmux, ykman`) ∪ Neptuno's 14, which confirms both Brewfile sources merge into one managed set.

## 5. `common` — the `brew-preinstall` contract

`common` ships the implementation (`system_files/shared/usr/libexec/brew-preinstall`, 448 lines), a thin wrapper (`usr/bin/brew-preinstall:1-2`), a **user** unit, and a **user** preset. `ublue-os/brew` ships none of it (searched the whole repo: no `preinstall` string).

**Directory, glob, hash** — `brew-preinstall:28, 46-60, 214-224`:

```bash
PREINSTALL_DIR="/usr/share/ublue-os/homebrew/preinstall.d"
...
for brewfile in "${PREINSTALL_DIR}"/*.Brewfile; do ... done
...
current_hash=$(cat "${brewfiles[@]}" | sha256sum | cut -d' ' -f1)
stored_hash=$(jq -r '.hash // ""' "${STATE_FILE}" 2>/dev/null || echo "")
if [[ "${current_hash}" == "${stored_hash}" && ... ]]; then
    echo "brew-preinstall: Brewfiles unchanged (${current_hash:0:12}...), nothing to do"
    exit 0
fi
```

- Single-level glob, **no recursion** — a Brewfile in a subdirectory of `preinstall.d/` is invisible.
- The hash covers concatenated **contents only**, in glob (lexicographic) order. Renaming a file can change the hash only if it reorders the glob; mtime/mode are irrelevant.
- Opt-out: `--external-chairlift` skips `chairlift.Brewfile` for tapping, hashing, bundling and managed state (`:18-26, 47-55`).

**State and removal** — `:8-15, 29-34, 231-267, 323-446`:

```bash
STATE_FILE="${HOME}/.local/share/ublue-os/brew-preinstall-state.json"
PENDING_FILE="${HOME}/.local/share/ublue-os/brew-preinstall-pending.json"
BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
```

- State is per-user, in `$HOME`, written atomically (`tmp` + `mv`, `:435-443`).
- Removal diffs the previous managed `packages`/`casks` against declarations parsed with `sed` from the current Brewfiles, then `brew uninstall <pkg> --ignore-dependencies` / `brew uninstall --cask`, guarded by `brew list` (`:396-426`).
- A declaration that was already installed *before* the run and is absent from previous managed state stays **user-owned** — never removed (`:231-242, 386-392`; the sanitised `pending` snapshot at `:244-267` exists so a retry after a partial bundle does not reclassify its own installs).
- Any bundle/uninstall failure exits non-zero **without** advancing the hash, so the next login retries (`:292-312, 428-431`).

**Preconditions / UID:**

- `[[ -x "${BREW_BIN}" ]] || { echo "…skipping"; exit 0; }` (`:36-39`) — silent no-op before the tarball exists.
- `[[ -d "${PREINSTALL_DIR}" ]]` else silent no-op (`:41-44`).
- The script makes **no UID assumption itself**; it runs as the invoking user (`ConditionUser=!@system`). The *prefix* imposes one: `brew-setup.service` does `chown -R 1000:1000 /home/linuxbrew` and `brew-update/upgrade.service` run `User=1000`. So the managed set only installs for uid 1000 (first user); other users' runs will fail on prefix permissions and show up as failed units. `common` documents the related consequence for casks at `docs/skills/brew-lifecycle/references/service-mechanics.md:196-202` (“first-user-wins”).
- `jq` is a hard dependency (used at `:139, 149, 156-160, 219, 252, 258-265, 344, 348, 436-442`); with `set -euo pipefail`, a missing `jq` aborts the run rather than degrading.

**The unit** — `common/system_files/shared/usr/lib/systemd/user/brew-preinstall.service:1-19`:

```ini
[Unit]
Description=Preinstall OS-managed Homebrew packages
After=ublue-user-setup.service graphical-session.target
ConditionUser=!@system
ConditionPathExists=/home/linuxbrew/.linuxbrew/bin/brew
StartLimitIntervalSec=600
StartLimitBurst=3

[Service]
Type=oneshot
Slice=background.slice
IOWeight=10
ExecStart=/usr/bin/brew-preinstall
RemainAfterExit=true
Restart=on-failure
RestartSec=30

[Install]
WantedBy=graphical-session.target
```

So: **yes, `graphical-session.target` is required by the shipped unit** (it is both ordered after and wanted by it; `common`'s own red flag at `docs/skills/brew-lifecycle/SKILL.md:236` says do not remove the ordering). It is a **user** unit, started by the user manager on graphical login, *not* by any system unit and *not* by `ublue-user-setup.service` (it only orders after it). No UID, no `User=`, no system-manager network ordering.

`common`'s docs contradict themselves on enablement: `docs/skills/brew-lifecycle/references/service-mechanics.md:25-30` claims “It is enabled globally via `usr/lib/systemd/user-preset/01-brew-preinstall.preset`. Downstream repos do **not** need `systemctl --global enable` calls.” See §7 — that is false for Containerfile builds.

## 6. `ublue-os/brew` — what the mechanism repo actually provides

`Containerfile:1-17` builds the tarball (`curl … install.sh`, `tar --zstd`) and a `scratch` ctx image containing `system_files`:

```
FROM scratch AS ctx
COPY system_files /system_files
COPY --from=builder /out/homebrew.tar.zst /system_files/usr/share/homebrew.tar.zst
```

Contents: `brew-setup.service`, `brew-{update,upgrade}.{service,timer}`, `01-homebrew.preset`, `profile.d/brew.sh`, `brew-bash-completion.sh`, `limits.d/30-brew-limits.conf`, fish integration. **No `brew-preinstall`, no `preinstall.d`.**

`system_files/usr/lib/systemd/system-preset/01-homebrew.preset:1-3`:

```
enable brew-setup.service
enable brew-update.timer
enable brew-upgrade.timer
```

`brew-setup.service:1-20` is a **system** oneshot, `WantedBy=default.target multi-user.target`, `ConditionPathExists=!/etc/.linuxbrew` + `!/home/linuxbrew/.linuxbrew` + `/usr/share/homebrew.tar.zst`, untars to `/tmp/homebrew`, `cp -R -n` into `/home/linuxbrew`, `chown -R 1000:1000`, `touch /etc/.linuxbrew`. It never re-runs once the prefix exists. `brew-update/upgrade.service` are system oneshots with `User=1000` and `ConditionPathIsSymbolicLink=/home/linuxbrew/.linuxbrew/bin/brew`; their timers are `OnBootSec=10min/30min`, `OnUnitInactiveSec=6h/8h`, `Persistent=true`.

The upstream README (`README.md:20-35`) recommends `systemctl preset <unit>` for the three system units; downstreams use `systemctl enable` instead. Both produce the same `/etc` symlinks because `01-homebrew.preset` says `enable` — the README is otherwise stale (`/var/home` paths, `tmpfiles.d/homebrew.conf`, which HEAD no longer ships).

## 7. How enablement actually works (the part that is easy to get wrong)

Four distinct mechanisms are in play; they are not interchangeable:

| Mechanism | What it writes | When it takes effect | Scope |
|---|---|---|---|
| `systemctl enable <system unit>` | `/etc/systemd/system/<wantedby>.wants/<unit>` | immediately, baked into the image | system |
| `systemctl --global enable <user unit>` | `/etc/systemd/user/<wantedby>.wants/<unit>` | immediately, baked into the image, for **every** user | user units, all users |
| `systemctl --user enable <unit>` (e.g. from a setup hook) | `~/.config/systemd/user/<wantedby>.wants/<unit>` | for that one user, after their login | user, one user |
| preset files (`*.preset`) | nothing until something runs `systemctl preset`/`preset-all` | system: bootc/systemd **machine first boot**; user: only if something explicitly runs `--global preset-all` | policy, not state |

Three facts that decide every case here:

1. **systemd applies presets only for the system manager, only on machine first boot.** Upstream `src/core/manager.c` (main, 2026-10-24):

   ```c
   static void manager_preset_all(Manager *m) {
           ...
           if (m->first_boot <= 0)
                   return;
           if (!MANAGER_IS_SYSTEM(m))
                   return;
   ```

   There is no user-manager equivalent. A file in `/usr/lib/systemd/user-preset/` is **inert** unless someone runs `systemctl --global preset-all` (or `--global enable`). `man systemd.preset` only promises first-boot application for the machine.

2. **BuildStream images are the exception** because `prepare-image.sh` runs both scopes at build time (§1). That is why Dakota can ship only presets.

3. **Containerfile images get no such call.** Fedora RPM `%post` scriptlets run `systemctl --global preset` for *their own* units, but a plain file dropped by an overlay is not an RPM, so nothing touches it. Hence finpilot/Neptuno/Utah must call `--global enable` explicitly.

Consequences:

- **Neptuno `10-build.sh:72` is correct and required.** Removing it in favour of "the preset is enough" would silently disable ChairLift and Neptuno's whole auto-install set.
- `10-build.sh:71` (system units) is *not* strictly required on a fresh install (bootc's first-boot `preset-all` would enable them), but it **is** load-bearing on `bootc switch`: first-boot preset application happens once per machine, not per deployment, so a machine rebased onto Neptuno only gets what the image's `/etc` already carries. Keep it.
- Utah's `85-utah-desktop.preset:27` (`enable brew-preinstall.service`) is inert on its own and only documents intent; the `--global enable` at `configure-services.sh:270` is the working mechanism. No harm, but the two must not drift.
- `ublue-user-setup` hooks are a *per-user* enablement path (`systemctl --user enable`). Nothing in any inspected distro enables brew through a hook, and nothing needs to.

## 8. First boot / first login ordering

```
boot ─► system manager ─► basic.target ─► brew-setup.service (oneshot, system, User=root)
                              untar /usr/share/homebrew.tar.zst → /tmp → cp -n → /home/linuxbrew
                              chown 1000:1000, touch /etc/.linuxbrew
        ─► multi-user.target ─► (ublue-system-setup.service)
        ─► graphical.target ─► GDM
                                    │
                             user logs in
                                    ▼
                        user manager ─► graphical-session.target
                                          ├─ ublue-user-setup.service (first login: theming + oem-brew hooks)
                                          └─ brew-preinstall.service   (After=ublue-user-setup.service
                                                                        graphical-session.target)
                                                hash preinstall.d/*.Brewfile
                                                unchanged → exit 0
                                                changed   → brew bundle each file, then removals
```

- **`brew-preinstall` runs after `brew-setup` unpacks in practice, but not by dependency.** They live in different service managers, so no `After=` is possible; the only gates are `ConditionPathExists=/home/linuxbrew/.linuxbrew/bin/brew` and the fact that a graphical login normally happens long after boot.
- **There is a real first-boot race.** `brew-setup.service` is `WantedBy=multi-user.target` and ordered only against `basic.target`; it does not block `graphical.target`. Extracting and copying a multi-GB prefix can outlive a fast GDM login. If `bin/brew` is not there yet, the condition fails, the unit is **skipped** (condition failure is not a restart), `Restart=on-failure` does not help, and the managed set installs on the next login instead. `common` documents the symptom (`docs/skills/brew-lifecycle/SKILL.md:235`: “the service exits 0 silently if brew is not yet installed; check `journalctl --user -u brew-preinstall.service`”).
- **Existing user, image update:** the new deployment ships new Brewfiles in `/usr/share` (read-only image content). On the user's next graphical login the hash differs → `brew bundle` runs → new declarations install; declarations dropped from the managed set uninstall (only if `brew list` confirms and they were managed); user-installed packages are untouched because of the pre-bundle snapshot. `brew` itself is **not** refreshed by the image: `brew-setup` is gated on the prefix not existing, so an existing install keeps its baked brew until `brew-update.timer` fires (10 min after boot, then every 6 h) and `brew-upgrade.timer` (30 min, then every 8 h) upgrades packages.
- **Second user on the same machine:** the prefix is `1000:1000`, so `brew bundle` cannot write. The unit runs, fails, is allowed at most 3 starts per 10 minutes (`StartLimitBurst=3`), then shows as a failed user unit. Only uid 1000 gets the managed set.
- **Rollback:** rolling back to a deployment with different Brewfiles changes the hash again, so the previous package set is restored (and the newer additions removed) on next login.

## 9. Declaration vs auto-install (Q7)

| Project | Where its Brewfiles land | Pattern |
|---|---|---|
| **dakota** | `files/just-overrides/*.Brewfile` → `/usr/share/ublue-os/homebrew/` (`just-overrides.bst:31-32`); `dakota-fonts.Brewfile` via `ujust install-dev-fonts` (`system.just:144`), `dakota-dev-flatpaks.Brewfile` consumed by `dakota-devmode flatpak-install` (`system.just:168`) | **declared / opt-in** |
| **utah** | none of its own; only `common`'s `preinstall.d` | **inherited auto-install only** |
| **finpilot** | `custom/brew/*.Brewfile` → `/usr/share/ublue-os/homebrew/` (`10-overlay.sh:87`), installed by ujust (`custom-apps.just:18,25`) | **declared / opt-in** |
| **Neptuno** | `custom/brew/*.Brewfile` → `/usr/share/ublue-os/homebrew/preinstall.d/` (`10-build.sh:79`) | **auto-install, every user** |

So within the inspected set, **Neptuno is the only project that auto-installs its own `custom/brew` content**. That is a supported pattern (`common`'s `docs/skills/brew-lifecycle/references/service-mechanics.md:111-115` explicitly invites downstreams to “drop `*.Brewfile` files into the same `preinstall.d/` directory”), but it is a different contract from the template's, and it changes three behaviours:

1. every file in `custom/brew/` becomes mandatory for every user, not a menu item;
2. dropping a file or a line uninstalls the package later (OS diet);
3. anything added there for convenience (fonts, an IDE bundle) becomes a default for all users.

`common`'s `package-set.md:53-75` is the authoritative statement of that contract, and its red flag list (`SKILL.md:234`) says not to edit `preinstall.d/` downstream for packages that should live in `common` — which Neptuno does not do (its packages are fork-specific).

## 10. Verdict on Neptuno

### Correct — keep as is

| Location | Why |
|---|---|
| `build/10-build.sh:72` `systemctl --global enable brew-preinstall.service` | The only thing that enables the user unit in a Containerfile build. Verified live: `/etc/systemd/user/graphical-session.target.wants/brew-preinstall.service` exists and the service ran. |
| `build/10-build.sh:71` explicit system enables | Survives `bootc switch`/rebase, where first-boot `preset-all` does not re-run. |
| `build/10-build.sh:149-150` `ublue-system-setup` / `--global ublue-user-setup` | `common` ships no preset for either unit; nothing else enables them. |
| No ublue-user-setup hook for brew | Hooks are per-user, version-gated and `systemctl --user` scoped; brew's enablement is global and its lifecycle is hash-driven. A hook would add a second, racing installer. |
| `custom/brew` → `preinstall.d` | Functionally correct and evidenced by the live state file (25 managed formulae incl. `common`'s set and `chairlift`). |

### Redundant (harmless, but know why)

- **Four duplicate declarations.** `custom/brew/default.Brewfile:15,17,18,22` declare `htop`, `fzf`, `glow`, `starship`, all of which `common` already ships in `system_files/shared/usr/share/ublue-os/homebrew/preinstall.d/system-cli.Brewfile:1-8`. They are bundled twice and deduplicated in state; removing them from Neptuno changes nothing today, but keeping them means Neptuno silently re-adds a tool if `common` ever drops it.
- **System-unit enables vs `01-homebrew.preset`** — redundant on a fresh install, load-bearing on rebase (§7). Keep, but the comment at `10-build.sh:63-65` (“no longer the source of truth here”) is the right framing.

### Wrong or risky

1. **`custom/brew/README.md:29-31` is factually wrong**: “`brew-preinstall.service` runs … after brew is extracted (`brew-setup.service`); both are user units.” `brew-setup.service` is a **system** unit (`ublue-brew/system_files/usr/lib/systemd/system/brew-setup.service:1-20`). The same paragraph also implies a systemd ordering that does not exist (no cross-manager `After=`).
2. **Overlay order is inverted vs the template** (`10-build.sh:12` brew, `:16` common; finpilot does common then brew). No path collides today — I diffed the two file lists — but the template's documented precedence (“brew supplies the mechanism, the template supplies declarations”, `10-overlay.sh:56-60`) depends on brew being last. One future `profile.d` or unit file in `common` would silently shadow brew's copy on Neptuno only.
3. **`jq` is an undeclared hard runtime dependency.** `brew-preinstall` aborts without it; Neptuno's `build/packages/*.toml` does not list it. On the current image it is present only transitively (`rpm -q --whatrequires jq` → `lvm2`). If `lvm2` ever leaves the base, the entire auto-install path fails at login.
4. **Policy drift, not wiring:** `nvtop` is auto-installed for every user (`default.Brewfile:16`) although `common` deliberately removed it as hardware-specific (`package-set.md:27-28, 68-71`). Neptuno's README says the fork is niri/GPU-oriented, so this may be intentional — but it is the one entry that can fail or be useless on non-GPU hardware.

### Recommended changes (file + line)

| # | File:line | Change |
|---|---|---|
| 1 | `build/10-build.sh:72` | Keep the call. Extend the comment: “`01-brew-preinstall.preset` is inert in a Containerfile build — systemd applies presets only for the system manager on machine first boot. This line is the enablement.” Then add a fail-closed assertion: `systemctl --global is-enabled brew-preinstall.service`. |
| 2 | `build/10-build.sh:12,16` | Swap so `common/shared` is overlaid before `oci/brew`, matching `finpilot/build/10-overlay.sh:52,60` and the documented precedence. |
| 3 | `custom/brew/README.md:29-31` | “`brew-setup.service` (system) unpacks the tarball at boot; `brew-preinstall.service` (user) then installs the managed set on graphical login. There is no systemd ordering between them — the user unit is gated on `ConditionPathExists=/home/linuxbrew/.linuxbrew/bin/brew`, so a first login that beats the unpack retries on the next login.” |
| 4 | `custom/brew/default.Brewfile:15,17,18,22` | Drop `htop`, `fzf`, `glow`, `starship` (already in `common`'s `system-cli.Brewfile`), or add a one-line comment saying they are deliberately re-declared so the fork does not depend on `common`'s list. Pick one; today the intent is ambiguous. |
| 5 | `custom/brew/README.md:1-6` | State the difference from the template explicitly: “Unlike finpilot's `custom/brew` (declaration only, installed by `ujust`), everything here is auto-installed for every user and auto-uninstalled when removed.” |
| 6 | `build/packages/base.toml` | Add `jq` to the base package list. |
| 7 | `build/10-build.sh:78-79` | After the copy, assert the file landed and is non-empty (e.g. `test -s /usr/share/ublue-os/homebrew/preinstall.d/default.Brewfile`); the copy is the only thing linking `custom/brew` to the runtime. |
| 8 | optional | If `nvtop` is intentional, say so in `custom/brew/README.md`; if not, drop it (§10.4). |

With those, Neptuno's Homebrew wiring is canonical: the same mechanism as finpilot, with one deliberate, documented policy choice (auto-install rather than declare).

### Status in `throwaway/finpilot-reseed`

This report audited the pre-refresh tree (`f03945f`). On the refresh branch:

- `jq` is declared in `build/packages/base.toml` (item 6).
- The overlay order matches finpilot: common/shared, bluefin cherry-picks, brew,
  custom/files, custom/config (item 2).
- `custom/brew/README.md` states the system/user split and the inert-preset
  reason (items 1, 3, 5).
- The duplicate declarations are documented in `default.Brewfile` as a
  deliberate self-contained contract (item 4).
- `10-overlay.sh` asserts both the Brewfile copy and the global enable
  (items 1, 7).

## 11. Open questions

1. **Dakota and `ublue-system-setup` / `ublue-user-setup`.** Dakota never calls `systemctl enable` and `common` ships no preset for either unit, so the only preset application in its build is `prepare-image.sh`'s `preset-all`. Nothing in the inspected sources enables those two units on Dakota (searched: all `*.bst`, `scripts/`, `files/`, `project.conf`; `common/system_files` contains exactly one static `.wants` symlink, `timers.target.wants/projectbluefin-countme.timer`). Either a preset exists in a layer I did not inspect, or Dakota's setup services genuinely do not run. Worth asking upstream rather than inferring.
2. **`jq` on Utah.** Same gap as Neptuno (no `jq` in `packages/*.toml`, no `jq` mention in `scripts/`), yet `brew-preinstall` requires it. Utah's base is Hummingbird minimal rather than Silverblue, so the transitive path is less obvious. Not verified on a booted Utah.
3. **Whether any upstream Bluefin/LTS variant auto-installs a `custom/brew`-style directory.** Not in scope here (`projectbluefin/bluefin` and `bluefin-lts` were not cloned; GitHub API rate-limited the tree check). Within the five cloned repos the answer is unambiguous: none do; only Neptuno does.
