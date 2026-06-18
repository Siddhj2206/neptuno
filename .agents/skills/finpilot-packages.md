---
name: finpilot-packages
description: >-
  Decision tree for where packages go: dnf5 (build-time, baked into image),
  Homebrew (runtime CLI tools), Flatpak (runtime GUI apps).
  Use when asked to add or remove a package.
metadata:
  context7-sources: []
---

# finpilot Packages

## When to Use

- Adding a new package to the image
- Moving a package between build-time and runtime
- Removing a package
- Deciding between dnf5, Brew, or Flatpak

## When NOT to Use

- Editing the Containerfile or Justfile — see `finpilot-build.md`
- Editing Brewfiles, Flatpak files, or ujust — see `finpilot-custom.md`
- Debugging a build failure — see `finpilot-troubleshooting.md`

## Decision Tree

```
What kind of package?
│
├─ System service, kernel module, or low-level library?
│   → dnf5 (build-time, baked into image)
│   → Location: build/steps/10-build.sh
│
├─ CLI tool for users?
│   ├─ Needs to survive `rpm-ostree update` / always available?
│   │   → dnf5 (build-time)
│   ├─ User-installable, updates frequently?
│   │   → Homebrew (runtime)
│   │   → Location: custom/brew/*.Brewfile
│
├─ GUI application?
│   → Flatpak (runtime, preinstalled on first boot)
│   → Location: custom/flatpaks/*.preinstall
│
└─ COPR repository?
    → Use copr_install_isolated() in build/steps/*.sh
    → ALWAYS disable after install
```

## Quick Reference

| Criterion | dnf5 (Build-time) | Brew (Runtime) | Flatpak (Runtime) |
|---|---|---|---|
| Baked into image | Yes | No | No |
| Available offline | Yes | No | No |
| Survives rebase | Yes | No (reinstall) | Yes (data in /var) |
| GUI apps | No | No | Yes |
| CLI tools | Yes | Yes | No |
| System services | Yes | No | No |
| Kernel modules | Yes | No | No |
| Update frequency | Low (image rebase) | User-controlled | User-controlled |

## Adding dnf5 Packages

```bash
# In build/steps/10-build.sh
dnf5 install -y package-name

# From COPR - always use isolated pattern
source /ctx/build/copr-helpers.sh
copr_install_isolated "owner/repo" package-name
```

**Rules:**
- Always `dnf5 install -y` (never `dnf`, `yum`, `rpm-ostree`)
- COPR: use `copr_install_isolated` — it auto-disables after install
- Group related installs together for cache efficiency

## Adding Homebrew Packages

```ruby
# In custom/brew/default.Brewfile
brew "bat"        # cat with syntax highlighting
brew "eza"        # Modern replacement for ls
brew "ripgrep"    # Faster grep
brew "fd"         # Simple alternative to find

# Taps and casks
tap "homebrew/cask"
cask "font-fira-code-nerd-font"
```

**Rules:**
- Ruby syntax (`.Brewfile`)
- Users install via `ujust install-*`
- Not baked into the image

## Adding Flatpak Applications

```ini
# In custom/flatpaks/default.preinstall
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable
```

**Rules:**
- INI format with `[Flatpak Preinstall APP_ID]`
- Always validate the app ID exists on Flathub before adding
- Always specify `Branch=stable`
- Installed on first boot (requires internet)

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll install it via dnf5 — it's easier." | Not if it's a user CLI tool that changes frequently. Brew is better for those. |
| "Flatpak is overkill for this tiny CLI tool." | Flatpak is for GUI apps only. CLI → dnf5 or Brew. |
| "I'll just add the COPR repo and leave it enabled." | COPR repos persist if not disabled, causing update conflicts. Use `copr_install_isolated`. |

## Red Flags

- `dnf`, `yum`, or `rpm-ostree` instead of `dnf5`
- COPR left enabled after package install
- GUI app installed via dnf5 instead of Flatpak
- Brewfile package that doesn't exist on Homebrew
- Flatpak app ID not validated against Flathub

## Verification

- [ ] Package type matches the decision tree?
- [ ] dnf5 used with `-y` flag?
- [ ] COPR disabled after use?
- [ ] Flatpak ID verified on Flathub?
- [ ] Brewfile syntax checked with `brew bundle check`?
