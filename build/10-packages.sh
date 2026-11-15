#!/usr/bin/env bash
# Every RPM change in one phase, driven by build/packages/*.toml.
#
# Packages come before the filesystem overlay so editing system_files/ (the
# common change) reuses this cached layer. The enablement snapshot is taken
# first, so 90-cleanup.sh catches anything an RPM scriptlet enables.
set -euo pipefail

PACKAGES=/ctx/build/packages
# shellcheck source=/dev/null
source /ctx/build/scripts/package-lib.sh

echo "::group:: Snapshot enabled units"
/ctx/build/scripts/systemd-units snapshot /var/tmp/neptuno-units.before
echo "::endgroup::"

echo "::group:: Remove unused base packages"
remove_fedora_section "${PACKAGES}/removals.toml" "removals"
echo "::endgroup::"

echo "::group:: Install Fedora packages"
# One transaction across every manifest, so dnf resolves the whole set once.
fedora_packages=()
for manifest in "${PACKAGES}"/{base,desktop,devlibs,hardware}.toml; do
	readarray -t -O "${#fedora_packages[@]}" fedora_packages < <("${READ_PKGS}" "${manifest}" fedora)
done
dnf5 install -y "${fedora_packages[@]}"
assert_packages_present "Fedora packages" "${fedora_packages[@]}"
echo "::endgroup::"

echo "::group:: Install COPR packages"
install_copr_sections "${PACKAGES}/base.toml"
install_copr_sections "${PACKAGES}/desktop.toml"
install_copr_sections "${PACKAGES}/hardware.toml"
echo "::endgroup::"

echo "::group:: Install Tailscale"
install_third_party_repo_section "${PACKAGES}/base.toml" "third-party:tailscale-stable" "Tailscale"
echo "::endgroup::"

echo "::group:: Guard against unwanted power daemons"
# tuned-ppd is the only power policy (doc/product.md 17.3).
assert_packages_absent "competing power daemons" power-profiles-daemon tlp auto-cpufreq
# D15: quickshell-git only, never alongside the stable build.
assert_packages_absent "stable quickshell" quickshell
echo "::endgroup::"
