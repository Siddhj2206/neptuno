#!/usr/bin/env bash
# Desktop wiring that is a build step rather than a shipped file: greeter
# checks, the hidden Settings entry, schemas and the fingerprint PAM feature.
set -euo pipefail

echo "::group:: Greeter"
# The greetd config (system_files/desktop) names the user the greeter runs as.
# That user comes from a package's sysusers.d, so a rename upstream would leave
# greetd unable to start. Fail the build instead.
greeter_user="$(sed -n 's/^user *= *"\(.*\)"/\1/p' /etc/greetd/config.toml | head -n1)"
[[ -n "${greeter_user}" ]] || {
	echo "ERROR: /etc/greetd/config.toml names no user" >&2
	exit 1
}
grep -Eq "^u!? +${greeter_user} " /usr/lib/sysusers.d/*.conf || {
	echo "ERROR: greeter user '${greeter_user}' is not defined in any sysusers.d file" >&2
	exit 1
}
command -v dms-greeter >/dev/null || {
	echo "ERROR: dms-greeter is not installed" >&2
	exit 1
}
systemctl set-default graphical.target
echo "::endgroup::"

echo "::group:: Hide the GNOME Settings launcher entry"
# gnome-control-center is here only for niri global shortcuts (doc/product.md
# 6.2). Most panels do nothing outside GNOME Shell, so keep it out of the DMS
# launcher; `XDG_CURRENT_DESKTOP=gnome gnome-control-center` still runs it.
settings_desktop=/usr/share/applications/org.gnome.Settings.desktop
grep -q '^NoDisplay=true' "${settings_desktop}" ||
	sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' "${settings_desktop}"
grep -q '^NoDisplay=true' "${settings_desktop}"
echo "::endgroup::"

echo "::group:: Niri defaults template in the skel config"
/ctx/build/scripts/render-niri-skel /usr/share/neptuno/niri/base.kdl /etc/skel/.config/niri/config.kdl
echo "::endgroup::"

echo "::group:: Compile schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas
echo "::endgroup::"

echo "::group:: Fingerprint login (D12)"
# Puts pam_fprintd into system-auth, which greetd, the DMS lock screen, sudo
# and run0 include. The password keeps working alongside it.
authselect enable-feature with-fingerprint
authselect current | grep -q with-fingerprint
echo "::endgroup::"
