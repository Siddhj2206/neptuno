export IMAGE_NAME := env("IMAGE_NAME", "neptuno")
export IMAGE_VENDOR := env("IMAGE_VENDOR", env("GITHUB_REPOSITORY_OWNER", "siddhj2206"))
export PODMAN := env("PODMAN", "podman")
export bib_image := env("BIB_IMAGE", "ghcr.io/osbuild/bootc-image-builder:latest@sha256:5e99d31c1e4d7a3f89e8d8d19dfb9e86be8572e7c8c7d61a1a0988e5b1989861")
export chunkah := env("CHUNKAH", "quay.io/coreos/chunkah:v0.7.1@sha256:71e593421c5de7dcc7c8c5c50e98d3bac572055a76f399f61a491d123c20a523")
export bcvk_version := env("BCVK_VERSION", "0.22.0")
export image_builder := env("IMAGE_BUILDER", "ghcr.io/osbuild/image-builder-cli:latest@sha256:84da35257bdec0627c05cf305a9d698dbcc502b758fa1f7a6bd3afebab8436fe")
export vm_ram := env("VM_RAM", "8192")
export vm_cpus := env("VM_CPUS", "4")

[private]
default:
    @just --list

# Check Justfile formatting
[group('Check')]
check:
    just --unstable --fmt --check -f Justfile
    just --unstable --fmt --check -f system_files/shared/usr/share/neptuno/justfile

# Rewrite Justfile formatting in place
[group('Check')]
fix:
    just --unstable --fmt -f Justfile
    just --unstable --fmt -f system_files/shared/usr/share/neptuno/justfile

# Every shell script in the repo: *.sh plus extensionless files with a sh/bash shebang
[private]
shell-sources:
    #!/usr/bin/bash
    set -euo pipefail
    { git ls-files --cached --others --exclude-standard '*.sh' build/scripts/render-niri-skel
      git ls-files --cached --others --exclude-standard system_files | while read -r f; do
          [[ "${f}" == *.* ]] && continue
          if head -n1 "${f}" | grep -Eq '^#!.*/(ba)?sh'; then echo "${f}"; fi
      done; } | sort -u

# Shellcheck every shell script
[group('Check')]
lint:
    #!/usr/bin/bash
    set -euo pipefail
    mapfile -t sources < <(just shell-sources)
    printf 'Shellchecking %s scripts\n' "${#sources[@]}"
    shellcheck "${sources[@]}"

# Run the bats suites (no image, no VM)
[group('Check')]
test-unit:
    #!/usr/bin/bash
    set -euo pipefail
    command -v bats >/dev/null || { echo "bats not found" >&2; exit 1; }
    mapfile -t files < <(find tests -type f -name '*_test.bats' | sort)
    bats --print-output-on-failure "${files[@]}"

# Check every Flatpak in flatpaks/ exists on Flathub
[group('Check')]
validate-flatpaks:
    bash build/validate-flatpaks.sh flatpaks

# Build the image as localhost/<IMAGE_NAME>:latest
[group('Image')]
build:
    #!/usr/bin/bash
    set -euo pipefail
    base_tag="$(sed -nE 's|^FROM [^ ]*base-atomic:([0-9]+)@.*|\1|p' Containerfile)"
    [[ -n "${base_tag}" ]] || { echo "ERROR: cannot read the base tag from Containerfile" >&2; exit 1; }
    args=(
        --build-arg "IMAGE_NAME=${IMAGE_NAME}"
        --build-arg "IMAGE_VENDOR=${IMAGE_VENDOR}"
        --build-arg "VERSION=${VERSION:-${base_tag}.$(date -u +%Y%m%d)}"
        --build-arg "IMAGE_CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    )
    [[ -z "$(git status --porcelain)" ]] && args+=(--build-arg "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    # A NOTIFY_SOCKET inherited from a systemd user session is bind-mounted into
    # /run and fails bootc lint's nonempty-run check.
    unset NOTIFY_SOCKET
    ${PODMAN} build "${args[@]}" --pull=newer --tag "localhost/${IMAGE_NAME}:latest" .

# Rechunk localhost/<IMAGE_NAME>:latest in place, then lint it
[group('Image')]
rechunk:
    #!/usr/bin/bash
    set -euo pipefail
    image="localhost/${IMAGE_NAME}:latest"
    # One RUN layer holds every RPM we add (about 2 GB). chunkah splits the
    # image into content-based layers (one per package group, at most 96):
    # smaller update downloads, and the ISO installer can stage each layer in
    # RAM. --prune /sysroot/ drops the base's OSTree repo, which bootc does not
    # need in a container image, and the ostree labels go with it.
    work="$(mktemp -d -p /var/tmp neptuno-chunkah.XXXXXX)"
    trap 'rm -rf "${work}"' EXIT
    ${PODMAN} inspect "${image}" > "${work}/config.json"
    ${PODMAN} run --rm --mount="type=image,src=${image},dest=/chunkah" \
        -v "${work}:/run/out:Z" "${chunkah}" build \
        --config /run/out/config.json --prune /sysroot/ --max-layers 96 \
        --label ostree.commit- --label ostree.final-diffid- \
        --output oci:/run/out/image
    id="$(${PODMAN} pull -q "oci:${work}/image")"
    ${PODMAN} tag "${id}" "${image}"
    ${PODMAN} image prune -f >/dev/null
    ${PODMAN} run --rm "${image}" bootc container lint --fatal-warnings
    ${PODMAN} image inspect "${image}" --format '{{{{len .RootFS.Layers}} layers'

# Run the image content tests (packages, repos, units, configs) against the local image
[group('Image')]
test-image image=("localhost/" + IMAGE_NAME + ":latest"):
    ${PODMAN} run --rm --network=none -v "${PWD}:/src:ro,z" "{{ image }}" /src/tests/image/check.sh

# Boot the local image in an ephemeral VM (bcvk, no disk image) and check systemd reaches running
[group('Image')]
test-boot image=("localhost/" + IMAGE_NAME + ":latest"):
    #!/usr/bin/bash
    set -euo pipefail
    command -v bcvk >/dev/null || { echo "bcvk not found (https://github.com/bootc-dev/bcvk)" >&2; exit 1; }
    # The image keeps sshd off (doc/product.md D2); bcvk talks to the VM over
    # SSH, so the test VM alone starts it from the kernel command line.
    state="$(bcvk ephemeral run-ssh --memory 4G --karg systemd.wants=sshd.service "{{ image }}" \
        'systemctl is-system-running --wait; systemctl --failed --no-legend --plain' | tr -d '\r' || true)"
    echo "${state}"
    [[ "$(head -n1 <<<"${state}")" == running ]]

# Copy the local image into root's storage, where the disk and ISO builders read it
[private]
root-copy target=("localhost/" + IMAGE_NAME + ":latest"):
    ${PODMAN} save --format oci-archive "localhost/${IMAGE_NAME}:latest" | sudo podman load
    sudo podman tag "localhost/${IMAGE_NAME}:latest" "{{ target }}"

# Build a qcow2 test disk (test user: neptuno/neptuno) into output/, from the rechunked image
[group('VM')]
build-qcow2: rechunk root-copy
    #!/usr/bin/bash
    set -euo pipefail
    mkdir -p output
    sudo podman run --rm --privileged --net=host \
        --security-opt label=type:unconfined_t \
        -v "${PWD}/iso/disk.toml:/config.toml:ro" \
        -v "${PWD}/output:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "${bib_image}" --type qcow2 --use-librepo=True --rootfs=btrfs "localhost/${IMAGE_NAME}:latest"
    sudo chown -R "$(id -u):$(id -g)" output

# Build the offline installer ISO from the local image (it installs, then updates from ghcr.io/<vendor>/<name>:latest)
[group('VM')]
build-iso: rechunk (root-copy "ghcr.io/" + IMAGE_VENDOR + "/" + IMAGE_NAME + ":latest") (iso "ghcr.io/" + IMAGE_VENDOR + "/" + IMAGE_NAME + ":latest")

# Build the installer ISO into output/iso around a payload image already in root's storage
[group('VM')]
iso payload:
    #!/usr/bin/bash
    set -euo pipefail
    # The payload keeps its registry name: the kickstart installs it from the
    # ISO's containers-storage, and bootc then follows the same ref for updates.
    sudo podman build --pull=newer --build-arg "PAYLOAD={{ payload }}" \
        --tag localhost/neptuno-installer:latest iso/installer
    sudo rm -rf output/iso && mkdir -p output/iso
    sudo podman run --rm --privileged --net=host \
        --security-opt label=type:unconfined_t \
        -v "${PWD}/output/iso:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "${image_builder}" build --output-dir /output \
        --bootc-ref localhost/neptuno-installer:latest \
        --bootc-installer-payload-ref "{{ payload }}" \
        --bootc-default-fs btrfs generic-iso
    sudo chown -R "$(id -u):$(id -g)" output

# Boot output/qcow2/disk.qcow2 with KVM (ssh on 127.0.0.1:2222)
[group('VM')]
run-vm:
    #!/usr/bin/bash
    set -euo pipefail
    disk=output/qcow2/disk.qcow2
    [[ -f "${disk}" ]] || { echo "ERROR: ${disk} not found; run: just build-qcow2" >&2; exit 1; }
    code=""; vars_src=""
    for d in /usr/share/edk2/ovmf /usr/share/OVMF; do
        [[ -z "${code}" && -f "${d}/OVMF_CODE.fd" ]] && code="${d}/OVMF_CODE.fd" && vars_src="${d}/OVMF_VARS.fd"
    done
    [[ -n "${code}" ]] || { echo "ERROR: OVMF not found (install edk2-ovmf)" >&2; exit 1; }
    vars="$(mktemp --suffix=.fd)"; trap 'rm -f "${vars}"' EXIT
    cp "${vars_src}" "${vars}"
    qemu-system-x86_64 -machine q35 -accel kvm -cpu host -smp "${vm_cpus}" -m "${vm_ram}" \
        -device virtio-vga -device virtio-keyboard -device virtio-mouse \
        -device virtio-net-pci,netdev=n0 -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
        -drive "if=pflash,format=raw,readonly=on,file=${code}" -drive "if=pflash,format=raw,file=${vars}" \
        -drive "file=${disk},if=virtio,format=qcow2" -display gtk

# Remove build outputs
[group('Image')]
clean:
    rm -rf output _build*
