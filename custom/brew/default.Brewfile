# neptuno — default brew preinstalls (auto-installed at first login).
#
# Every Brewfile in this directory is copied to
# /usr/share/ublue-os/homebrew/preinstall.d/ and applied automatically by
# brew-preinstall.service (content-addressed by hash — edit to re-apply).
#
# htop, fzf, glow and starship also appear in common's system-cli.Brewfile.
# They are redeclared on purpose: this file is the fork's complete contract, so
# dropping one from common does not silently remove it here. brew-preinstall
# collects packages across every Brewfile and deduplicates them.
#
# Policy: only USER tools live here. System tools (build-time, systemd
# services, first boot before brew, desktop integration) stay in the base
# image (build/packages/*.toml) — e.g. ghostty is native on purpose
# (niri.toml, from the danklinux COPR).
#
# All entries verified in Homebrew core with Linux bottles, 2026-08-29
# (host-proven set: every formula runs on the neptuno host today).

# --- CLI tools (ported from the neptuno host brew set) -----------------------
brew "htop"         # interactive process viewer
brew "fzf"          # fuzzy finder
brew "glow"         # markdown pager (used by the `changelogs` ujust recipe)
brew "zenity"       # GTK dialogs for scripts

# --- core dev/terminal stack (uncommented + expanded from template) ---------
brew "starship"     # shell prompt
brew "btop"         # system monitor
brew "gh"           # GitHub CLI
brew "lazygit"      # git TUI
brew "bun"
brew "uv"
brew "neovim"
brew "eza"          # modern ls
brew "bat"          # modern cat
brew "fd"           # modern find
brew "ripgrep"      # modern grep
brew "zoxide"       # smart cd
brew "atuin"        # shell history
