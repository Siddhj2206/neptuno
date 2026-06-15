# neptuno

neptuno is a custom bootc image built on Universal Blue's [`bluefin-dx:stable`](https://github.com/ublue-os/bluefin) base. It keeps the multi-stage layering model from the Bluefin ecosystem, then adds a DMS/Niri desktop stack, a small set of build-time CLI packages, gaming essentials, and ASUS laptop tooling for a more opinionated daily-driver image.

> Be the one who moves, not the one who is moved.

## What Makes neptuno Different?

Here are the main ways neptuno differs from the upstream base image.

### Base Image

- **Base image**: `ghcr.io/ublue-os/bluefin-dx:stable`
- **Build model**: Multi-stage bootc image with OCI-imported resources from `@projectbluefin/common` and `@ublue-os/brew`
- **Package strategy**: `dnf5` for build-time system changes, Homebrew for user-installed CLI tools, Flatpak for optional GUI apps

### Added Packages (Build-time)

- **Core CLI tools**: `chromium`, `git`, `gum`, `dnf-plugins-core`, `make`, `unzip`, `libwayland-server`, `golang-bin`
- **DMS / Niri desktop stack** (via COPR — `avengemedia/danklinux`, `avengemedia/dms`, `yalter/niri`): `niri`, `quickshell-git`, `matugen`, `dgop`, `dsearch`, `cava`, `khal`, `ghostty`, `dms`
- **DMS supporting packages**: `xdg-desktop-portal-gtk`, `accountsservice`, `xwayland-satellite`, `adw-gtk3-theme`, `qt6ct`, `qt6-qtmultimedia`
- **Gaming**: `steam`, `gamescope`, `mangohud`
- **ASUS laptop tooling** (via COPR — `lukenukem/asus-linux`): `asusctl`, `supergfxctl`, `asusctl-rog-gui`

### Runtime Applications

- **Homebrew** (`custom/brew/default.Brewfile`): `bat`, `eza`, `fd`, `rg`, `gh`, `git`, `starship`, `zoxide`, `htop`, `tmux`
- **Flatpak** (`custom/flatpaks/default.preinstall`): the finpilot default catalog is shipped but every entry is commented out — no Flatpaks are preinstalled on first boot. Uncomment lines to enable.
- **ujust** (`custom/ujust/`): the standard finpilot examples are shipped commented out. An `install-dms-config` recipe is provided to copy the bundled DMS/Niri/Ghostty configs from `/etc/skel/.config/` into the user's home directory.

### Configuration Changes

- `podman.socket` is enabled
- The DMS session is wired up via `systemctl --global add-wants niri.service dms`, with `dsearch` and `niri` enabled globally
- Skeleton config files for Niri, Ghostty, and a DMS environment drop-in are copied to `/etc/skel/.config/` at build time
- A daily scheduled build is configured via cron in `build-image.yml`

*Last updated: 2026-06-15*

> This section is what tells users how the image differs from the base. Update it whenever you add, remove, or reconfigure packages, apps, or system services.

## Quick Start

### 1. Create Your Repository

Click "Use this template" to create a new repository from this template.

### 2. Rename the Project

If you fork this and rename `neptuno` to your own image, update these 6 files:

1. `Containerfile` (`# Name:` comment and `ARG IMAGE_NAME`): `# Name: your-repo-name`
2. `Justfile` (`export IMAGE_NAME := env("IMAGE_NAME", ...)` and `REPO_ORG`): your values
3. `README.md` (title): `# your-repo-name`
4. `artifacthub-repo.yml` (`repositoryID`): `repositoryID: your-repo-name`
5. `custom/ujust/README.md` (bootc switch example): `localhost/your-repo-name:stable`
6. `.github/workflows/clean.yml` (`packages`): `packages: your-repo-name`

### 3. Enable GitHub Actions

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically.

### 4. Enable Renovate (Required)

Renovate automatically updates dependencies and GitHub Actions (including workflow files). This template uses a self-hosted Renovate runner via `projectbluefin/actions`.

**One-time setup:**

1. Go to GitHub → Settings → Developer settings → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token (classic)**
3. Set a note like `renovate-neptuno`
4. Select scopes: **`repo`** (full control) and **`workflow`** (update workflows)
5. Click **Generate token** and copy the value
6. Go to your repository → Settings → Secrets and variables → Actions
7. Add a new secret: **`RENOVATE_TOKEN`** (paste the token value)
8. Enable **Settings → General → Pull Requests → Allow auto-merge** so Renovate can merge low-risk updates after checks pass
9. **Configure branch protection for `main`** (required for automerge to work):
   - Go to Settings → Branches → Add rule
   - Set **Branch name pattern** to `main`
   - Enable **"Require a pull request before merging"**
   - Enable **"Require status checks to pass before merging"**
   - Add `validate` as a required status check
   - Enable **"Require branches to be up to date before merging"** (recommended)

Renovate will run every 6 hours and on config changes. It pins GitHub Actions to SHAs and updates tracked image digests automatically.

### 5. Customize Your Image

The base image is `ghcr.io/ublue-os/bluefin-dx:stable` and is pinned by SHA in `Containerfile` (Renovate keeps it up to date). neptuno layers additional desktop, gaming, and laptop tooling on top via numbered build scripts:

- `build/10-build.sh` — copy Bluefin config, copy custom files, install general CLI tools, enable `podman.socket`
- `build/20-dms.sh` — install the DMS/Niri desktop stack from COPR
- `build/30-gaming.sh` — install Steam, Gamescope, MangoHud
- `build/40-asus.sh` — install ASUS laptop tooling from COPR

To add packages, edit the relevant `build/NN-*.sh` script. To add user-installable CLI tools, add a `brew "..."` line to `custom/brew/*.Brewfile`. To add a GUI app, add a `[Flatpak Preinstall ...]` block to `custom/flatpaks/*.preinstall`.

### 6. Development Workflow

All changes should be made via pull requests:

1. Open a pull request on GitHub with the change you want.
2. The PR will automatically trigger:
   - Build validation
   - Brewfile, Flatpak, Justfile, and shellcheck validation
   - Test image build
3. Once checks pass, merge the PR
4. Merging triggers publishes a `:stable` image

### 7. Deploy Your Image

Switch an existing bootc system to neptuno:

```bash
sudo bootc switch ghcr.io/siddhj2206/neptuno:stable
sudo systemctl reboot
```

## Image Signing (Enabled)

neptuno images are signed using **keyless OIDC signing** via Cosign and GitHub Actions. The `Sign and publish` step in `.github/workflows/build-image.yml` is already uncommented — no setup is required. The signature is created using GitHub's OIDC token via Fulcio, and a build provenance attestation is attached to the image.

Verify a signed image with:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/siddhj2206/neptuno/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/siddhj2206/neptuno:stable
```

## Image Rechunking (Enabled)

The `Rechunk image` step in `.github/workflows/build-image.yml` is enabled. It uses [`chunkah`](https://github.com/coreos/chunkah) to reorganize OCI layers without rpm-ostree, reducing update sizes by 5-10× and improving download resumability.

For optimal OTA deltas, also add `bootc-build/apply-pkg-intervals` before the rechunk step and create a `.github/workflows/pkg-cadence.yml` workflow that calls `projectbluefin/actions/.github/workflows/reusable-pkg-cadence.yml@v1`.

## What's Included

### Build System

- Automated builds via GitHub Actions on every commit, plus a daily scheduled build
- Self-hosted Renovate for automated dependency updates
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow — test changes before merging to main
  - PRs build and validate before merge
  - `main` branch builds `:stable` images
- Validates your files on pull requests so you never break a build:
  - Brewfile, Justfile, ShellCheck, Renovate config, and Flatpak app IDs on Flathub
- Production-grade features already enabled:
  - Container signing with keyless OIDC
  - Image rechunking for smaller OTA deltas

### Homebrew Integration

- Pre-configured Brewfiles for easy package installation and customization
- Users install packages at runtime with `brew bundle` or premade `ujust` commands
- See [custom/brew/README.md](custom/brew/README.md) for details

### Flatpak Support

- `custom/flatpaks/default.preinstall` ships the finpilot default catalog commented out
- Uncomment entries to ship GUI apps on first boot
- See [custom/flatpaks/README.md](custom/flatpaks/README.md) for details

### ujust Commands

- `custom/ujust/custom-apps.just` and `custom/ujust/custom-system.just` ship the finpilot examples commented out
- An `install-dms-config` recipe copies the bundled DMS/Niri/Ghostty configs from `/etc/skel/.config/` to the user's home
- See [custom/ujust/README.md](custom/ujust/README.md) for details

### Build Scripts

- Modular numbered scripts (10-, 20-, 30-, 40-) run in order from the Containerfile
- Helper functions for safe COPR usage in `build/copr-helpers.sh`
- See [build/README.md](build/README.md) for details

## Detailed Guides

- [Build Scripts](build/README.md) - Build-time customization
- [Homebrew/Brewfiles](custom/brew/README.md) - Runtime package management
- [Flatpak Preinstall](custom/flatpaks/README.md) - GUI application setup
- [ujust Commands](custom/ujust/README.md) - User convenience commands

## Architecture

neptuno follows the **multi-stage build architecture** from `@projectbluefin/distroless`, as documented in the [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/).

### Multi-Stage Build Pattern

**Stage 1: Context (ctx)** - Combines resources from multiple sources:

- Local build scripts (`/build`)
- Local custom files (`/custom`)
- **@projectbluefin/common** - Desktop configuration shared with Aurora (includes branding/artwork content)
- **@ublue-os/brew** - Homebrew integration

**Stage 2: Base Image**

- `ghcr.io/ublue-os/bluefin-dx:stable@sha256:...` (the active base, pinned by Renovate)

### Benefits of This Architecture

- **Modularity**: Compose your image from reusable OCI containers
- **Maintainability**: Update shared components independently
- **Reproducibility**: Renovate automatically updates OCI tags to SHA digests
- **Consistency**: Share components across Bluefin, Aurora, and custom images

### OCI Container Resources

The template imports files from these OCI containers at build time:

```dockerfile
COPY --from=ghcr.io/projectbluefin/common:latest /system_files /oci/common
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /oci/brew
```

Build scripts can access these files at:

- `/ctx/oci/common/` - Shared desktop configuration (branding/artwork content lives inside `common`)
- `/ctx/oci/brew/` - Homebrew integration files

**Note**: Renovate automatically updates `:latest` tags to SHA digests for reproducible builds.

## Local Testing

Test your changes before pushing:

```bash
just build              # Build container image
just build-qcow2        # Build VM disk image
just run-vm-qcow2       # Test in browser-based VM
```

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion](https://github.com/bootc-dev/bootc/discussions)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [Bluefin Documentation](https://docs.projectbluefin.io/)
- [bootc Documentation](https://containers.github.io/bootc/)

## Security

This image ships with production security features enabled by default:

- Image signing with keyless OIDC cosign for cryptographic verification
- Image rechunking for smaller, more resumable OTA updates
- Automated security updates via Renovate
- Build provenance tracking via SLSA attestation

Users can verify signed images with the `cosign verify` snippet under "Image Signing (Enabled)" above.
