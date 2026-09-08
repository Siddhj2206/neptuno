#!/usr/bin/env bash
# Enroll the current user in the docker and libvirt groups.
#
# User-side of the two-hook pair (see privileged-setup.hooks.d/10-groups.sh
# for the root side). Runs at every graphical login via ublue-user-setup;
# escalates through the polkit bridge common ships (auto-YES for wheel
# members calling ublue-privileged-setup — no prompt).
#
# Follows the oem-brew pattern: prerequisites are checked BEFORE
# version-script records completion, so a failed pkexec retries next login
# instead of burning the version marker.

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

set -euo pipefail

# Already enrolled — nothing to do, no version marker needed.
if id -nG | grep -qw docker && id -nG | grep -qw libvirt; then
    exit 0
fi

# NOTE: version-script runs AFTER pkexec on purpose — a denied prompt
# retries next login instead of burning the marker (expect repeats in logs).
/usr/bin/pkexec /usr/bin/ublue-privileged-setup

version-script neptuno-groups user 1 || exit 0
