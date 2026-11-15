# neptuno

A personal Fedora bootc desktop image: Fedora `base-atomic` 45 with the niri
compositor and DankMaterialShell, for Intel and AMD machines (not NVIDIA).
GUI apps come from Flathub, user CLI packages from Nix (`nx`), and the OS
updates as one signed image.

> Be the one who moves, not the one who is moved.

The plan of record, including every package decision, is
[doc/product.md](doc/product.md).

## Install

From any Fedora Atomic or bootc system:

```bash
sudo bootc switch ghcr.io/siddhj2206/neptuno:latest
sudo systemctl reboot
```

Or build the offline installer ISO (`just build-iso` locally, or the `ISO`
workflow) and install from USB.

## Updates

- The OS stages a new image daily in the background and never reboots by
  itself; you get a notification when one is waiting.
- `topgrade` updates everything at once. `sudo bootc upgrade` needs no password
  for members of `wheel`.
- `sudo bootc rollback` returns to the previous deployment;
  `sudo bootc switch ghcr.io/siddhj2206/neptuno:45.YYYYMMDD` pins any of the
  last 30 builds. Each build's
  [release](https://github.com/Siddhj2206/neptuno/releases) lists the packages
  that changed.
- `neptuno` (a `just` front end) has `info`, `changelog`, `verify`,
  `config-diff`, `refresh-config` and `devbox`.

## How it is built and released

| | |
|---|---|
| Pull request | Static checks, plus a full build, rechunk, content tests and an ephemeral VM boot. Nothing is published. |
| Merge to `main`, and daily | The same, then the digest is signed (keyless cosign), verified and tagged `:latest` and `:45.YYYYMMDD`. |
| Dependencies | Renovate pins every image and action by digest; non-major updates automerge only when that full pipeline is green. |

Updates are verified in CI, not on the device: the laptop pulls over
`ostree-unverified-image`, and `neptuno verify` checks the booted digest's
signature on demand. doc/product.md section 11 explains why.

```bash
cosign verify ghcr.io/siddhj2206/neptuno:latest \
  --certificate-identity https://github.com/Siddhj2206/neptuno/.github/workflows/build.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Local development

```bash
just lint check test-unit   # static checks and the bats suite
just build                  # build localhost/neptuno:latest
just rechunk                # chunkah + bootc container lint
just test-image             # image content tests
just build-qcow2 run-vm     # a test disk (user neptuno/neptuno) in QEMU
just build-iso              # the offline installer ISO
```

Agents: start with [AGENTS.md](AGENTS.md).
