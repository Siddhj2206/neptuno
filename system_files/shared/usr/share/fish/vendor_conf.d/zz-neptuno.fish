# Neptuno interactive defaults. Each tool is optional (install with `nx add`),
# so every hook is guarded and a missing tool costs nothing.
# The zz- prefix matters: fish sources vendor_conf.d in name order, and this
# must run after nix.fish puts ~/.nix-profile/bin on PATH, or every
# `command -q` below fails for tools installed with nx.

# nix.fish prepends the Nix profiles. Move them after the system, as
# 60-nix.conf does for the session, so a Nix compiler never replaces the
# system's cc. Runs for every fish, not only interactive ones.
set -l __neptuno_nix $HOME/.nix-profile/bin (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo $HOME/.local/state)/nix/profile/bin /nix/var/nix/profiles/default/bin
set -l __neptuno_found
for dir in $__neptuno_nix
    if contains -- $dir $fish_user_paths $PATH
        set -a __neptuno_found $dir
    end
    while set -l i (contains -i -- $dir $fish_user_paths)
        set -e fish_user_paths[$i]
    end
    while set -l i (contains -i -- $dir $PATH)
        set -e PATH[$i]
    end
end
set -gx PATH $PATH $__neptuno_found

status is-interactive; or exit

# No "Welcome to fish" banner. A user who wants one sets fish_greeting
# themselves; a universal value is left alone.
set -q fish_greeting; or set -g fish_greeting

command -q starship; and starship init fish | source
command -q zoxide; and zoxide init fish | source
command -q atuin; and atuin init fish | source

if command -q eza
    alias ls 'eza --group-directories-first'
    alias ll 'eza -l --group-directories-first --git'
    alias la 'eza -la --group-directories-first --git'
end
