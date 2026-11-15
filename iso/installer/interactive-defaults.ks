# Installs Neptuno from the copy embedded in the ISO (image-builder
# --bootc-installer-payload-ref puts it in the installer's containers-storage),
# so the install needs no network and the image is on the ISO once. The target
# ref is what `bootc upgrade` follows afterwards. The Containerfile replaces
# @PAYLOAD@ with its PAYLOAD build argument.
#
# Known Fedora 45 Anaconda gaps with this payload (tested 2026-11-15):
# - the first user's home directory is not created; neptuno-ensure-homes.service
#   creates it from /etc/skel on first boot;
# - the chosen timezone and hostname are not kept; set them after install
#   (`timedatectl set-timezone`, `hostnamectl hostname`).
# `ostreecontainer --transport=containers-storage` was tried instead and fails
# after the deploy (its systemd-tmpfiles step exits 73 on the composefs root).
bootc --source-imgref containers-storage:@PAYLOAD@ --target-imgref @PAYLOAD@
