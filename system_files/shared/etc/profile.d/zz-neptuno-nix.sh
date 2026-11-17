# shellcheck shell=sh
# nix-core's nix-daemon.sh puts the Nix profiles ahead of /usr/bin. Move them
# to the end of PATH, as 60-nix.conf does for the session, so a Nix compiler
# never replaces the system's cc. The zz- prefix runs this after nix-daemon.sh.
__neptuno_keep=
__neptuno_nix=
__neptuno_ifs=$IFS
IFS=:
for __neptuno_dir in $PATH; do
	case $__neptuno_dir in
	"$HOME/.nix-profile/bin" | "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profile/bin" | /nix/var/nix/profiles/default/bin)
		case ":$__neptuno_nix:" in
		*":$__neptuno_dir:"*) ;;
		*) __neptuno_nix=${__neptuno_nix:+$__neptuno_nix:}$__neptuno_dir ;;
		esac
		;;
	*) __neptuno_keep=${__neptuno_keep:+$__neptuno_keep:}$__neptuno_dir ;;
	esac
done
IFS=$__neptuno_ifs
PATH=$__neptuno_keep${__neptuno_nix:+:$__neptuno_nix}
export PATH
unset __neptuno_keep __neptuno_nix __neptuno_ifs __neptuno_dir
