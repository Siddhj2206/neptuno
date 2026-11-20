# Neptuno interactive defaults. Each tool is optional (install with `nx add`),
# so every hook is guarded and a missing tool costs nothing.
# The zz- prefix matters: fish sources vendor_conf.d in name order, and this
# must run after nx.fish puts nx's tools on PATH, or every `command -q` below
# fails for tools installed with nx.

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
