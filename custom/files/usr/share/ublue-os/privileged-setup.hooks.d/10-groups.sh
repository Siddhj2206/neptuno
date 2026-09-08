#!/usr/bin/env bash
# Root side of group enrollment: ensure the docker and libvirt groups exist
# and add every human user to them.
#
# Triggered by user-setup.hooks.d/30-groups.sh via pkexec
# ublue-privileged-setup (common's polkit bridge). Naturally idempotent —
# no version-gating needed. Group entries that the image RPMs did not
# create are appended from /usr/lib/group (bluefin pattern).

set -euo pipefail

append_group() {
    local g="$1"
    if ! grep -q "^${g}:" /etc/group 2>/dev/null; then
        grep "^${g}:" /usr/lib/group 2>/dev/null | tee -a /etc/group >/dev/null || true
    fi
}

for g in docker libvirt; do
    append_group "${g}"
done

mapfile -t USERS < <(awk -F: '$3 >= 1000 && $3 < 65534 { print $1 }' /etc/passwd)
for u in "${USERS[@]}"; do
    usermod -aG docker,libvirt "${u}" 2>/dev/null || true
done
