# Anaconda kickstart default embedded in the installer ISO.
# For offline/embedded ISO ( --bootc-installer-payload-ref ), this will be
# resolved from the embedded container storage. image-builder copies the
# payload ref into /var/lib/containers/storage on the ISO squashfs.
# The `bootc` kickstart command is the modern replacement for `ostreecontainer`.
#
# Keep the registry reference matching your image; for fully offline builds the
# installer will use the embedded copy and not need network. If you want a
# network fallback, keep the registry: prefix.
bootc --source-imgref registry:ghcr.io/siddhj2206/neptuno:stable-daily --target-imgref ghcr.io/siddhj2206/neptuno:stable-daily

# If you prefer to force offline-only (no network fallback) and have embedded
# via --bootc-installer-payload-ref, you can switch to:
# bootc --source-imgref containers-storage:ghcr.io/siddhj2206/neptuno:stable-daily

# NOTE: Do not add %post `bootc switch` here — the payload is already the
# installed OS. %post is only needed for thin online ISOs (iso/iso.toml).
%post --erroronfail
echo "neptuno offline installer payload installed"
%end
