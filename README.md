# neptuno

neptuno is a custom bootc image built on Universal Blue's `bluefin-dx` base. It keeps the multi-stage layering model from the Bluefin ecosystem, then adds a DMS/Niri desktop stack, a small set of build-time CLI packages, and gaming essentials for a more opinionated daily-driver image.

> Be the one who moves, not the one who is moved.

## What Makes neptuno Different?

Here are the main ways neptuno differs from the upstream base image.

### Base Image

- **Base image**: `ghcr.io/ublue-os/bluefin-dx:latest`
- **Build model**: Multi-stage bootc image with OCI-imported resources from `@projectbluefin/common` and `@ublue-os/brew`
- **Package strategy**: `dnf5` for build-time system changes, Homebrew for user-installed CLI tools, Flatpak for optional GUI apps

### Added Packages (Build-time)

- **Core tools**: `git`, `gum`, `dnf-plugins-core`, `make`, `unzip`, `libwayland-server`, `golang-bin`
- **Desktop stack**: `niri`, `quickshell`, `matugen`, `dgop`, `dsearch`, `cava`, `khal`, `ghostty`, `dms`
- **Supporting packages**: `xdg-desktop-portal-gtk`, `accountsservice`, `xwayland-satellite`, `adw-gtk3-theme`, `qt6ct`, `qt6-qtmultimedia`
- **Gaming packages**: `steam`, `gamescope`, `mangohud`

### Runtime Applications

- **Homebrew**: Default Brewfile includes `bat`, `eza`, `fd`, `rg`, `gh`, `git`, `starship`, `zoxide`, `htop`, and `tmux`
- **Flatpak**: `custom/flatpaks/default.preinstall` is still a template-style catalog; all entries are currently commented out, so no Flatpaks are preinstalled by default
- **ujust**: Custom commands can be layered in through `custom/ujust/`

### Configuration Changes

- Copies shared Bluefin just recipes from `@projectbluefin/common`
- Enables `podman.socket`
- Installs the DMS session stack from COPR repositories and disables those repos after install
- Adds a gaming layer with Steam, Gamescope, and MangoHud

*Last updated: 2026-03-26*

## What's Included

### Build System

- GitHub Actions workflows for builds, validation, cleanup, and Renovate updates
- Pull request validation for shell scripts, Brewfiles, Flatpaks, Justfiles, and Renovate config
- Multi-stage `Containerfile` that mounts local `build/` and `custom/` content into the image build

### Build Scripts

- `build/10-build.sh` installs shared packages, copies custom files, and enables services
- `build/20-dms.sh` adds the DMS/Niri session stack and related packages
- `build/30-gaming.sh` adds gaming-focused packages
- `build/copr-helpers.sh` contains the reusable COPR helper patterns

### Runtime Customization

- `custom/brew/` for Homebrew bundles
- `custom/flatpaks/` for post-first-boot Flatpak installs
- `custom/ujust/` for user-facing helper commands
- `custom/config/` for skeleton config copied into `/etc/skel/.config/`

## Build And Test Locally

Build the image locally:

```bash
just build
```

Build a QCOW2 image and boot it in a VM:

```bash
just build-qcow2
just run-vm-qcow2
```

Run the common local workflow end to end:

```bash
just build && just build-qcow2 && just run-vm-qcow2
```

If you prefer ISO-based testing, use the commands defined in `Justfile` for the ISO workflow.

## Deploy

Switch an existing bootc system to the published image:

```bash
sudo bootc switch ghcr.io/<owner>/neptuno:stable
sudo systemctl reboot
```

Replace `<owner>` with the GitHub or registry namespace that publishes your build.

## Optional: Enable Image Signing

Signing is disabled by default so first builds can succeed immediately. When you are ready for production, enable cosign-based signing in GitHub Actions.

1. Generate a key pair:

```bash
cosign generate-key-pair
```

2. Keep `cosign.key` secret and commit the matching `cosign.pub`
3. Add the private key to GitHub Actions secrets as `SIGNING_SECRET`
4. Enable the signing steps in `.github/workflows/build.yml`

Never commit `cosign.key`.

## Production Notes

- **Signing**: Recommended for production images
- **SBOM attestation**: Available in the build workflow, but depends on signing
- **Rechunking**: Optional optimization if you want smaller and more efficient bootc updates
- **Branch flow**: Treat `main` as the production branch that publishes stable images

To verify a signed image:

```bash
cosign verify --key cosign.pub ghcr.io/<owner>/neptuno:stable
```

## Architecture

neptuno follows the same multi-stage pattern used by the Bluefin ecosystem.

### Context Stage

The `ctx` stage combines:

- local build scripts from `build/`
- local runtime customization files from `custom/`
- shared system files from `ghcr.io/projectbluefin/common:latest`
- Homebrew integration files from `ghcr.io/ublue-os/brew:latest`

### Final Image Stage

The final stage starts from `ghcr.io/ublue-os/bluefin-dx:latest` and runs the numbered build scripts in order:

1. `build/10-build.sh`
2. `build/20-dms.sh`
3. `build/30-gaming.sh`

This keeps custom logic modular and makes it easier to reason about desktop, tooling, and gaming changes separately.

## Detailed Guides

- [Build Scripts](build/README.md)
- [Homebrew / Brewfiles](custom/brew/README.md)
- [Flatpak Preinstall](custom/flatpaks/README.md)
- [ujust Commands](custom/ujust/README.md)

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussions](https://github.com/bootc-dev/bootc/discussions)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [Bluefin Documentation](https://docs.projectbluefin.io/)
- [bootc Documentation](https://containers.github.io/bootc/)
