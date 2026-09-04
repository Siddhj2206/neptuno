# Build Scripts

The image build is a single monolithic `RUN /ctx/build/build.sh` in the Containerfile. `build.sh` executes the numbered step scripts in `steps/` in a fixed order.

## Layout

```
build/
├── build.sh            # Orchestrator — runs each step in order (see Containerfile)
└── steps/
    ├── 00-image-info.sh  # Write image-info/metadata (name, tag, vendor)
    ├── copr-helpers.sh   # Shared helpers: copr_install_isolated (auto-disables COPRs)
    ├── 10-build.sh       # Copy Bluefin config, custom files, Brewfiles/Flatpaks/ujust, podman.socket
    ├── 20-base.sh        # Remove Fedora cruft, CLI tools, codecs, COPR packages, systemd units
    ├── 30-dx.sh          # Docker CE, libvirt/QEMU, perf tooling
    ├── 40-dms.sh         # DMS/Niri desktop stack from COPR
    ├── 50-cleanup.sh     # Remove build leftovers
    ├── 50-gaming.sh      # NOT wired into build.sh — intentionally unconnected (see TODO.md G11)
    ├── 60-initramfs.sh   # Regenerate initramfs via dracut (bluefin pattern)
    ├── clean-stage.sh    # Final stage cleanup (/opt symlink swap)
    ├── validate-repos.sh # Fail the build if any third-party repo is left enabled (bluefin pattern)
    └── 70-tests.sh       # In-image smoke tests: key packages, negativo codecs, unwanted removals, unit enables
```

Steps are executed by explicit calls in `build/build.sh`, not by globbing — to add a step, create the script **and** add a line to `build/build.sh` (and keep the numbered naming convention: `NN-name.sh`).

## Conventions

- Scripts run as root during build; build context is mounted at `/ctx`
- Use `dnf5` exclusively for package management (never `dnf`, `yum`, or `rpm-ostree`)
- Always pass `-y` for non-interactive installs
- Any COPR enabled during a step must be disabled before the step ends (`copr_install_isolated` handles this)
- Source shared functions from `steps/copr-helpers.sh` rather than duplicating them

### Script Template

```bash
#!/usr/bin/bash

set -euox pipefail

echo "Running custom setup..."
# Your commands here
```

### Best Practices

- **Use descriptive names**: `50-gaming.sh` is better than `50-stuff.sh`
- **One purpose per script**: easier to debug and reorder
- **Clean up after yourself**: remove temporary files and disable temporary repos
- **Test incrementally**: add one step at a time and test builds

### Disabling a Step

Comment out its invocation in `build/build.sh` (see `50-gaming.sh` for an example of an unwired step). Do not rely on removing execute permission — `build.sh` calls steps explicitly.
