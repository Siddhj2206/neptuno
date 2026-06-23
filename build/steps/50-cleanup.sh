#!/usr/bin/bash

set -eoux pipefail

echo "::group:: Remove kernel source and headers"
rm -rf /usr/src
echo "::endgroup::"

echo "::group:: Remove orphan kernel modules"
for kver_dir in /usr/lib/modules/*/; do
	kver=$(basename "${kver_dir}")
	if ! rpm -q "kernel-core-${kver}" &>/dev/null; then
		echo "Removing orphan /usr/lib/modules/${kver} (no matching kernel-core RPM)"
		rm -rf "${kver_dir}"
	fi
done
echo "::endgroup::"
