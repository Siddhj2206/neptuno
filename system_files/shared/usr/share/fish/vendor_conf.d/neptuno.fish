# Neptuno interactive defaults. Each tool is optional (install with `nx add`),
# so every hook is guarded and a missing tool costs nothing.
status is-interactive; or exit

command -q starship; and starship init fish | source
command -q zoxide; and zoxide init fish | source
command -q atuin; and atuin init fish | source

if command -q eza
    alias ls 'eza --group-directories-first'
    alias ll 'eza -l --group-directories-first --git'
    alias la 'eza -la --group-directories-first --git'
end
