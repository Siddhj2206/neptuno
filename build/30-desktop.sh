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
# Puts pam_fprintd into system-auth, which the DMS lock screen, sudo and run0
# include. The password keeps working alongside it.
authselect enable-feature with-fingerprint
authselect current | grep -q with-fingerprint
# ...except at the greeter. /etc/pam.d/greetd (system_files/desktop) takes auth
# from password-auth, so the first login always uses the password and pam_oo7
# can unlock the login keyring with it. Fail if either side has drifted.
grep -Eq '^auth +substack +password-auth' /etc/pam.d/greetd || {
	echo "ERROR: /etc/pam.d/greetd must take auth from password-auth" >&2
	exit 1
}
grep -Eq '^-?auth .*pam_oo7\.so' /etc/pam.d/greetd || {
	echo "ERROR: /etc/pam.d/greetd lost its pam_oo7 auth line" >&2
	exit 1
}
if grep -q pam_fprintd /etc/pam.d/password-auth; then
	echo "ERROR: password-auth has pam_fprintd; greetd would skip the password" >&2
	exit 1
fi
echo "::endgroup::"
