# System Files — image root mirror

Everything in this directory is rsynced **directly to `/`** during the build
(`build/10-build.sh`), mirroring how `@ublue-os/brew` and `@projectbluefin/common`
ship their overlays. It is the home for *system-level* files the image bakes:
greetd config, PAM, systemd units/presets/wants, gsettings schema overrides.

Layout = verbatim image paths (`etc/…`, `usr/…` — no `custom/files` prefix):

```
custom/files/
├── etc/greetd/
│   ├── config.toml            # greetd -> dms-greeter -> niri session
│   └── niri/config.kdl        # greeter-only niri baseline
├── usr/lib/systemd/system/
│   └── flatpak-theming.service  # first-boot: override + mask commands
├── usr/lib/systemd/user-preset/
│   └── 90-pluto-dms.preset    # DMS user unit preset
├── usr/lib/systemd/user/
│   └── niri.service.wants/dms.service   # symlink -> DMS autostart
└── usr/share/glib-2.0/schemas/
    └── zz0-pluto-theme.gschema.override # GTK theme defaults
```

## Rules

- **System-level only.** User-level defaults (`~/.config/…`) go in
  `custom/config/` (→ `/etc/skel`), not here.
- Layout must be an exact mirror of `/` — `etc/` and `usr/` subtrees only.
- Symlinks are preserved as-is (e.g. the DMS wants symlink); targets must be
  absolute paths. A target that dangles in git is expected when it ships via
  RPM at build time (dms.service arrives with the COPR package).
- Scripts (40-niri.sh) still do the *dynamic* parts: enabling units,
  `glib-compile-schemas`, `set-default graphical.target`.
