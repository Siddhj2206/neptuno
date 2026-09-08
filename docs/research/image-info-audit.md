# image-info.json Audit: pluto vs projectbluefin/bluefin

**Date:** 2026-08-29
**Scope:** Does `build/00-image-info.sh` and `/usr/share/ublue-os/image-info.json` in pluto match what bluefin does, and is the file consumed correctly?

---

## 1. Pluto's current behavior

### 1.1 Script dump: `build/00-image-info.sh` (92 lines, verbatim)

`pluto/build/00-image-info.sh:1-92`:
```bash
#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Image Info Generation
###############################################################################
# Generates /usr/share/ublue-os/image-info.json and customizes /usr/lib/os-release.
# This script is bluefin-pattern: each consumer provides its own branding.
#
# Required env vars (set as ARGs in Containerfile):
#   IMAGE_NAME          - Image name (e.g. finpilot, my-custom-os)
#   IMAGE_VENDOR        - Image vendor/owner (e.g. github username or org)
#   UBLUE_IMAGE_TAG     - Image tag/stream (e.g. stable, testing, latest)
#   BASE_IMAGE_NAME     - Base image name (e.g. hummingbird)
#   FEDORA_MAJOR_VERSION - Fedora version (e.g. 43)
#   VERSION             - Full version string (e.g. stable-43.20250531)
###############################################################################

# Branding — customize these for your image
IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-My Custom OS}"
IMAGE_LIKE="${IMAGE_LIKE:-fedora}"
HOME_URL="${HOME_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}}"
DOCUMENTATION_URL="${DOCUMENTATION_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/blob/main/README.md}"
SUPPORT_URL="${SUPPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues}"
BUG_REPORT_URL="${BUG_REPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues/new}"

# Paths
IMAGE_INFO="/usr/share/ublue-os/image-info.json"
OS_RELEASE="/usr/lib/os-release"

# Derive image flavor from name
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
	IMAGE_FLAVOR="nvidia"
else
	IMAGE_FLAVOR="main"
fi

# Image ref (used by bootc for upgrade source)
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

###############################################################################
# Write image-info.json
###############################################################################
mkdir -p /usr/share/ublue-os
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-flavor": "${IMAGE_FLAVOR}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "${UBLUE_IMAGE_TAG}",
  "base-image-name": "${BASE_IMAGE_NAME}",
  "fedora-version": "${FEDORA_MAJOR_VERSION}"
}
EOF

echo "Wrote ${IMAGE_INFO}"
echo "  image-name: ${IMAGE_NAME}"
echo "  image-flavor: ${IMAGE_FLAVOR}"
echo "  image-vendor: ${IMAGE_VENDOR}"

###############################################################################
# Customize /usr/lib/os-release
###############################################################################
# Only modify if the file exists and VARIANT_ID is not already set
if [[ -f "${OS_RELEASE}" ]] && ! grep -q "^VARIANT_ID=" "${OS_RELEASE}"; then
	# Read existing values
	if [[ -n "${VERSION:-}" ]]; then
		OS_VERSION="${VERSION}"
	else
		OS_VERSION="${UBLUE_IMAGE_TAG}"
	fi

	# Append our identity
	cat >>"${OS_RELEASE}" <<EOF

# ${IMAGE_NAME} image identity
VARIANT_ID="${IMAGE_FLAVOR}"
PRETTY_NAME="${IMAGE_PRETTY_NAME}"
NAME="${IMAGE_NAME}"
IMAGE_ID="${IMAGE_NAME}"
IMAGE_VERSION="${OS_VERSION}"
ID_LIKE="${IMAGE_LIKE}"
HOME_URL="${HOME_URL}"
DOCUMENTATION_URL="${DOCUMENTATION_URL}"
SUPPORT_URL="${SUPPORT_URL}"
BUG_REPORT_URL="${BUG_REPORT_URL}"
EOF

	echo "Customized ${OS_RELEASE}"
fi
```

**Key observations (pluto):**

* Reads 6 ARGs as env vars: `IMAGE_NAME`, `IMAGE_VENDOR`, `UBLUE_IMAGE_TAG`, `BASE_IMAGE_NAME`, `FEDORA_MAJOR_VERSION`, `VERSION` — documented in header `pluto/build/00-image-info.sh:12-18`.
* Writes to `IMAGE_INFO="/usr/share/ublue-os/image-info.json"` at `pluto/build/00-image-info.sh:29` (same path bluefin uses).
* Derives `IMAGE_FLAVOR` from `IMAGE_NAME` containing `nvidia` else `main` — `pluto/build/00-image-info.sh:33-37`.
* Builds `IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"` at `pluto/build/00-image-info.sh:40` — identical transport prefix to bluefin.
* JSON has exactly 7 keys: `image-name`, `image-flavor`, `image-vendor`, `image-ref`, `image-tag`, `base-image-name`, `fedora-version` — `pluto/build/00-image-info.sh:46-56`.
* `os-release` handling is **append-only, guarded**: only if file exists and `! grep -q "^VARIANT_ID="` — `pluto/build/00-image-info.sh:67`. Appends 10 keys including `VARIANT_ID`, `PRETTY_NAME`, `NAME`, `IMAGE_ID`, `IMAGE_VERSION`, `ID_LIKE`, `HOME_URL`, `DOCUMENTATION_URL`, `SUPPORT_URL`, `BUG_REPORT_URL`. Does **not** touch `VERSION`, `VERSION_CODENAME`, `OSTREE_VERSION`, `BUILD_ID`, `CPE_NAME`, `DEFAULT_HOSTNAME`, `ID`, nor does it strip `REDHAT_BUGZILLA_*`.
* Default branding is generic: `IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-My Custom OS}"` at `pluto/build/00-image-info.sh:21`, `HOME_URL` defaults to `https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}` etc. — not pluto-specific.
* Path `/usr/share/ublue-os/image-info.json` is **generated at build time only**; `custom/files` has no such file (`ls custom/files/usr/share/ublue-os/` returns no json, only `custom/files` tree verified via `find`).

### 1.2 Containerfile ARGs (lines 55-85)

`pluto/Containerfile:59-72`:
```dockerfile
ARG IMAGE_NAME="pluto"
ARG IMAGE_VENDOR="Siddhj2206"
ARG UBLUE_IMAGE_TAG="stable"
# BASE_IMAGE_NAME / FEDORA_MAJOR_VERSION mirror the Hummingbird bootc-os base:
# the base (rolling :latest) carries Fedora-44-era content — the pulp repo
# tracks F44 versions (dnf5 5.4.x, gcc 16, fedora-gpg-keys 44) — but its
# os-release VERSION_ID is the hum build number, so it cannot
# self-report a Fedora releasever. FEDORA_MAJOR_VERSION IS the releasever
# (/etc/dnf/vars/releasever at build): single source of truth for pluto's
# Fedora stream, used by the added fedora repos and by COPRs. Bump it when
# the base rolls to the next Fedora stream.
ARG BASE_IMAGE_NAME="hummingbird"
ARG FEDORA_MAJOR_VERSION="44"
ARG VERSION=""
```

Plus invocation at `pluto/Containerfile:83-86`:
```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh
```

* `IMAGE_NAME="pluto"` — lowercase, correct per `ghcr.io` conventions. Matches workflow lowercasing (`pluto/.github/workflows/build-image.yml:65`: `echo "IMAGE_NAME=${IMAGE_NAME,,}"`).
* `IMAGE_VENDOR="Siddhj2206"` — **mixed-case** in Containerfile default. At runtime the workflow lowercases it (`build-image.yml:64-65`: `IMAGE_NAME=${IMAGE_NAME,,}` and `IMAGE_REGISTRY=${IMAGE_REGISTRY,,}` but `IMAGE_VENDOR` itself is **not** explicitly lowercased — it inherits from `github.repository_owner` which is already lowercase on GitHub, and `Justfile:131` uses `${IMAGE_VENDOR:-${REPO_ORG}}` where `REPO_ORG` is lowercased via `GITHUB_REPOSITORY_OWNER`). So the default is cosmetically wrong but functionally corrected in CI; local `just build` without env would produce `Siddhj2206` which violates container registry lowercase requirement.
* `BASE_IMAGE_NAME="hummingbird"` / `FEDORA_MAJOR_VERSION="44"` — pluto-specific; bluefin uses `silverblue`/`44`. This is intentional given pluto's Hummingbird base (`Containerfile:55`: `FROM quay.io/hummingbird-community/bootc-os:latest@sha256:ad50d...`) vs bluefin's `quay.io/fedora-ostree-desktops/silverblue:44`.
* `VERSION=""` — empty default, populated by `Justfile:106-126` via `fedora_version=$(grep -E '^ARG FEDORA_MAJOR_VERSION=' Containerfile ...)` and `ver="${fedora_version}.$(date +%Y%m%d)"` or `"${tag}-${fedora_version}.$(date +%Y%m%d)"`.

### 1.3 Additional pluto files that touch image-info / os-release

* `pluto/custom/ujust/custom-system.just:193-197` — `changelogs` recipe reads `IMAGE_INFO_FILE="${IMAGE_INFO_FILE:-/usr/share/ublue-os/image-info.json}"` and `TAG="$(jq -r '.["image-tag"]' < "${IMAGE_INFO_FILE}")"` plus `DATE="$(grep -oP "OSTREE_VERSION=.*\d{2}\.\K\d{8}[.0-9]*" /etc/os-release ...)"` — mirrors bluefin's `changelog.just` but hardcodes `REPO="siddhj2206/pluto"` (`custom-system.just:195`) and correct for pluto.
* `pluto/build/10-build.sh` — overlays `common/shared` (which ships `ublue-image-info.sh`) but does **not** itself touch image-info.

---

## 2. Bluefin's behavior

### 2.1 Script dump: `build_files/base/00-image-info.sh` (76 lines, verbatim)

`bluefin/build_files/base/00-image-info.sh:1-76` (cloned to `/tmp/opencode/bluefin`):
```bash
#!/usr/bin/env bash

echo "::group:: ===$(basename "$0")==="

set -xeuo pipefail

IMAGE_PRETTY_NAME="Bluefin"
IMAGE_LIKE="fedora"
HOME_URL="https://projectbluefin.io"
DOCUMENTATION_URL="https://docs.projectbluefin.io"
SUPPORT_URL="https://github.com/projectbluefin/bluefin/issues/"
BUG_SUPPORT_URL="https://github.com/projectbluefin/bluefin/issues/"
CODE_NAME="Deinonychus"
VERSION="${VERSION:-00.00000000}"

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/$IMAGE_VENDOR/$IMAGE_NAME"

# Image Flavor
image_flavor="main"
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
  image_flavor="nvidia"
fi

cat >$IMAGE_INFO <<EOF
{
  "image-name": "$IMAGE_NAME",
  "image-flavor": "$image_flavor",
  "image-vendor": "$IMAGE_VENDOR",
  "image-ref": "$IMAGE_REF",
  "image-tag":"$UBLUE_IMAGE_TAG",
  "base-image-name": "$BASE_IMAGE_NAME",
  "fedora-version": "$FEDORA_MAJOR_VERSION"
}
EOF

# OS Release File
sed -i "s|^VARIANT_ID=.*|VARIANT_ID=$IMAGE_NAME|" /usr/lib/os-release
sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${IMAGE_PRETTY_NAME} (Version: ${VERSION})\"|" /usr/lib/os-release
sed -i "s|^NAME=.*|NAME=\"$IMAGE_PRETTY_NAME\"|" /usr/lib/os-release
sed -i "s|^HOME_URL=.*|HOME_URL=\"$HOME_URL\"|" /usr/lib/os-release
sed -i "s|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL=\"$DOCUMENTATION_URL\"|" /usr/lib/os-release
sed -i "s|^SUPPORT_URL=.*|SUPPORT_URL=\"$SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"$BUG_SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^CPE_NAME=\"cpe:/o:fedoraproject:fedora|CPE_NAME=\"cpe:/o:universal-blue:${IMAGE_PRETTY_NAME,}|" /usr/lib/os-release
sed -i "s|^DEFAULT_HOSTNAME=.*|DEFAULT_HOSTNAME=\"${IMAGE_PRETTY_NAME,}\"|" /usr/lib/os-release
sed -i "s|^ID=fedora|ID=${IMAGE_PRETTY_NAME,}\nID_LIKE=\"${IMAGE_LIKE}\"|" /usr/lib/os-release
sed -i "/^REDHAT_BUGZILLA_PRODUCT=/d; /^REDHAT_BUGZILLA_PRODUCT_VERSION=/d; /^REDHAT_SUPPORT_PRODUCT=/d; /^REDHAT_SUPPORT_PRODUCT_VERSION=/d" /usr/lib/os-release
sed -i "s|^VERSION_CODENAME=.*|VERSION_CODENAME=\"$CODE_NAME\"|" /usr/lib/os-release
sed -i "s|^VERSION=.*|VERSION=\"${VERSION} (${BASE_IMAGE_NAME^})\"|" /usr/lib/os-release
sed -i "s|^OSTREE_VERSION=.*|OSTREE_VERSION=\'${VERSION}\'|" /usr/lib/os-release

if [[ -n "${SHA_HEAD_SHORT:-}" ]]; then
  echo "BUILD_ID=\"$SHA_HEAD_SHORT\"" >>/usr/lib/os-release
fi

# Added in systemd 249.
# https://www.freedesktop.org/software/systemd/man/latest/os-release.html#IMAGE_ID=
echo "IMAGE_ID=\"${IMAGE_NAME}\"" >> /usr/lib/os-release
echo "IMAGE_VERSION=\"${VERSION}\"" >> /usr/lib/os-release

# Fix issues caused by ID no longer being fedora
sed -i "s|^EFIDIR=.*|EFIDIR=\"fedora\"|" /usr/sbin/grub2-switch-to-blscfg

# Ship placeholder values — refreshed at runtime by bluefin-stats-refresh.timer
echo "…" > /usr/share/ublue-os/fastfetch-user-count
echo "…" > /usr/share/ublue-os/bazaar-install-count

# Add Mutter kms-modifiers for nvidia builds.
# This must run in Stage 2 (after system_files rsync) — the gschema override
# file is only available after the system_files overlay.
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
    sed -i "/experimental-features/ s/\]/, 'kms-modifiers'&/" /usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override
fi

echo "::endgroup::"
```

**Key observations (bluefin):**

* Same 7-key JSON schema, same path `IMAGE_INFO="/usr/share/ublue-os/image-info.json"` (`bluefin/build_files/base/00-image-info.sh:16`) — **no schema divergence**.
* Flavor derivation identical: `nvidia` substring → `nvidia` else `main` (`bluefin/build_files/base/00-image-info.sh:20-23`).
* `IMAGE_REF` also `ostree-image-signed:docker://ghcr.io/$IMAGE_VENDOR/$IMAGE_NAME` (`bluefin/build_files/base/00-image-info.sh:17`).
* Hardcoded branding: `IMAGE_PRETTY_NAME="Bluefin"` (`:7`), URLs to `projectbluefin.io`/`github.com/projectbluefin/bluefin`, `CODE_NAME="Deinonychus"` (`:13`), `VERSION="${VERSION:-00.00000000}"` (`:14`).
* **os-release is mutated in-place via `sed -i`**, not appended. It **replaces** existing keys (`VARIANT_ID`, `PRETTY_NAME`, `NAME`, `HOME_URL`, `DOCUMENTATION_URL`, `SUPPORT_URL`, `BUG_REPORT_URL`, `CPE_NAME`, `DEFAULT_HOSTNAME`, `ID`/`ID_LIKE`, `VERSION_CODENAME`, `VERSION`, `OSTREE_VERSION`) and **appends** `BUILD_ID`, `IMAGE_ID`, `IMAGE_VERSION`. It also strips `REDHAT_BUGZILLA_*` and fixes `EFIDIR` in grub2.
* Sets `VARIANT_ID=$IMAGE_NAME` (e.g. `bluefin`, not flavor) — `bluefin/build_files/base/00-image-info.sh:38`. Pluto sets `VARIANT_ID="${IMAGE_FLAVOR}"` (`main`).
* Sets `PRETTY_NAME` to `"Bluefin (Version: ${VERSION})"` — `bluefin/build_files/base/00-image-info.sh:39`. Pluto sets it to bare `${IMAGE_PRETTY_NAME}` without version.
* Also sets `VERSION="${VERSION} (${BASE_IMAGE_NAME^})"` (e.g. `41.20250601 (Silverblue)`) and `OSTREE_VERSION='${VERSION}'` — bluefin `00-image-info.sh:50-51`.
* Also writes `BUILD_ID` from `SHA_HEAD_SHORT` — bluefin `:53-55`.

### 2.2 Containerfile ARGs (bluefin)

`bluefin/Containerfile:1-6` (global) and `bluefin/Containerfile:55-63` / `109-123` (per-stage):
```dockerfile
ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG BASE_IMAGE="quay.io/fedora-ostree-desktops/silverblue"
ARG BASE_IMAGE_REF="${BASE_IMAGE}:${FEDORA_MAJOR_VERSION}"
...
ARG IMAGE_NAME="bluefin"
ARG IMAGE_VENDOR="projectbluefin"
ARG UBLUE_IMAGE_TAG="stable"
ARG SHA_HEAD_SHORT="dedbeef"
ARG VERSION=""
```

* `BASE_IMAGE_NAME="silverblue"` vs pluto's `hummingbird` — intentional base difference.
* `IMAGE_VENDOR="projectbluefin"` is **already lowercase** — pluto's default `Siddhj2206` is not.
* Bluefin declares `SHA_HEAD_SHORT` and `VERSION` as build ARGs and propagates them to `00-image-info.sh`; pluto declares `VERSION` but not `SHA_HEAD_SHORT` or `CODE_NAME`/`IMAGE_PRETTY_NAME` as ARGs.

### 2.3 Common repo (projectbluefin/common)

`common` **does not generate** `image-info.json`; it **consumes** it. Checked via `grep -r "image-info"` in `/tmp/opencode/common` — only hits are in `system_files/shared/usr/bin/ublue-image-info.sh` and tests/workflow mentions.

---

## 3. Consumption points (where `image-info.json` is read)

| Consumer | File:line | Keys read | Purpose | Notes vs pluto |
|---|---|---|---|---|
| `ublue-image-info.sh` (fastfetch title) | `common/system_files/shared/usr/bin/ublue-image-info.sh:4-6` | `image-name`, `image-tag` | Prints `pluto:stable 🔐/🔓` in fastfetch `title` module (`common/system_files/bluefin/usr/share/ublue-os/fastfetch.jsonc:22-24`: `"text": "/usr/bin/ublue-image-info.sh"`) | Ships via `common/shared` overlay in pluto (`pluto/build/10-build.sh` rsyncs `/ctx/oci/common/shared/ /`). Works unchanged — only needs those two keys, which pluto provides correctly. Fallback to `bootc status --json` for tag override (`ublue-image-info.sh:11-15`) handles promotion-retagged digests. |
| `ublue-fastfetch` wrapper | `common/system_files/shared/usr/bin/ublue-fastfetch:8-22` | indirect (via `ublue-bling-fastfetch` + config) | Dispatches `fastfetch --config ... --color ...` | No direct image-info read, but displays `ublue-image-info.sh` output via fastfetch.jsonc. |
| `changelog.just` (bctl fallback) | `common/system_files/bluefin/usr/share/ublue-os/just/changelog.just:11-15` | `image-tag`, `image-name` | Selects GitHub release repo (`bluefin` vs `bluefin-lts` vs `dakota`) and fetches `TAG-DATE` from Releases API; uses `DATE` from `OSTREE_VERSION` in `/etc/os-release` | Pluto ships equivalent at `pluto/custom/ujust/custom-system.just:193-197` hardcoding `REPO="siddhj2206/pluto"` — correct fork for pluto. Relies on `OSTREE_VERSION` existing; pluto's `os-release` sets `IMAGE_VERSION` but **does not set `OSTREE_VERSION`** (bluefin does at `:51`). So pluto's `DATE` extraction may fail if base lacks it. |
| `toggle-testing` just recipe | `common/system_files/bluefin/usr/share/ublue-os/just/system.just:248-252` | `image-tag`, `image-ref` | Computes `IMAGE_PATH` from `image-ref`, toggles `stable`↔`testing` via `bootc switch` | Not shipped by pluto (`custom-system.just` doesn't copy bluefin justfiles beyond `00-entry.just`). No breakage, but pluto lacks this capability unless re-added. |
| `21-container-native-iso.sh` | `bluefin/build_files/base/21-container-native-iso.sh:8-14` | `image-ref` | Derives `INSTALL_IMAGE="${IMAGE_REF}:stable"` for anaconda `ostreecontainer` kickstart + Titanoboa ISO `iso.yaml` | Pluto does not ship an ISO builder; if added, would need same file. No current consumer, but schema correct if needed. |
| `fastfetch-user-count` / `bazaar-install-count` placeholders | `bluefin/build_files/base/00-image-info.sh:66-67` | — | Placed after image-info for fastfetch modules (`fastfetch.jsonc:48-60`: `cat /usr/share/ublue-os/fastfetch-user-count` etc.) | Pluto does **not** create these placeholder files and doesn't ship `fastfetch.jsonc` from common/bluefin. If pluto ever ships fastfetch, these will be missing and fastfetch modules will error. Not currently consumed because pluto doesn't include `common/system_files/bluefin` fastfetch config. |
| `bluefin-stats-refresh.timer` | `bluefin/system_files/shared/usr/lib/systemd/system/bluefin-stats-refresh.service:2` (referenced in `17-cleanup.sh` comments) | — | Refreshes the two `…-count` files at runtime | Same note as above — not present in pluto; no consumption. |
| Tests | `common/tests/test_ublue_image_info.bats:1-100`, `common/tests/test_changelog.bats`, `common/tests/test_ublue_fastfetch.bats` | `image-name`, `image-tag` (mocked) | CI validation of `ublue-image-info.sh` behavior | Validates pluto's downstream file indirectly if pluto ever runs common tests. |
| `issue templates` / `ujust report` | `bluefin/.github/ISSUE_TEMPLATE/bug-report.yml:38` + `common` justfiles | via `ujust report` (not directly image-info) | Asks user to paste `ujust report` gist URL (which includes `rpm-ostree status` and `bootc status`) | Pluto's template at `pluto/.github/ISSUE_TEMPLATE/bug-report.yml` already mirrors this. |

**Summary:** The only **hard** consumers that pluto actually ships are `ublue-image-info.sh` (fastfetch) and the ported `changelogs` recipe. Both read only `image-name`/`image-tag`/`image-ref`, which pluto provides correctly. The ISO and `toggle-testing` consumers are bluefin-only and not shipped in pluto — no immediate breakage, but the schema must stay compatible if pluto ever enables them.

---

## 4. Comparison table: field by field

| Field | Bluefin value (example) | Pluto value (example) | Path correct? | Content correct per template conventions? | Verdict |
|---|---|---|---|---|---|
| `image-name` | `"bluefin"` (`bluefin/build_files/base/00-image-info.sh:27`, `Containerfile:58`) | `"pluto"` (`pluto/build/00-image-info.sh:48`, `Containerfile:59`) | ✅ same key, same path `/usr/share/ublue-os/image-info.json` | ✅ Correct: must match `IMAGE_NAME` ARG and `ghcr.io/…/pluto` repo. Pluto uses `pluto` consistently (`Justfile:1`, `Containerfile:59`, `artifacthub-repo.yml` etc.). | **Correct** |
| `image-flavor` | `"main"` or `"nvidia"` (`bluefin/build_files/base/00-image-info.sh:20-23`, `Containerfile:62` `IMAGE_FLAVOR=""` unused) | `"main"` or `"nvidia"` (`pluto/build/00-image-info.sh:33-37`) | ✅ | ✅ Correct: derived from `IMAGE_NAME =~ nvidia`. Bluefin also does this; same semantics. | **Correct** |
| `image-vendor` | `"projectbluefin"` (`bluefin/Containerfile:59`, lowercased) | `"Siddhj2206"` default (`pluto/Containerfile:60`) → lowercased at CI (`build-image.yml:64-65` lowercases `IMAGE_NAME`/`IMAGE_REGISTRY` but via `GITHUB_REPOSITORY_OWNER` which is already lower; `Justfile:131` uses fallback `REPO_ORG="projectbluefin"` lower). Runtime on GHCR will be `siddhj2206`. | ✅ key exists, but **default value has wrong case**. `ghcr.io` requires lowercase; Containerfile default `Siddhj2206` violates `docker`/`podman` lowercase convention and will produce `ostree-image-signed:docker://ghcr.io/Siddhj2206/pluto` if built locally without env. Bluefin's default is already lowercase. | **Minor defect — lower case the default** to `siddhj2206` or wire through `${IMAGE_VENDOR,,}` in script. Workflow masks it in CI, but local `just build` is broken-case. |
| `image-ref` | `"ostree-image-signed:docker://ghcr.io/projectbluefin/bluefin"` (`bluefin/build_files/base/00-image-info.sh:17`) | `"ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"` (`pluto/build/00-image-info.sh:40`) | ✅ | ✅ Correct transport + registry pattern. Caveat inherits `image-vendor` case issue. Also bluefin hardcodes `projectbluefin`, pluto parameterizes — correct for template. | **Correct (modulo vendor case)** |
| `image-tag` | `"stable"` (or `gts`, `latest`, `stable-daily`) (`bluefin/Containerfile:61`) | `"stable"` (`pluto/Containerfile:61`) | ✅ | ✅ Correct. Must match `UBLUE_IMAGE_TAG` ARG which is fed from `DEFAULT_TAG`/`TAG_STREAM` in `build-image.yml:78-84` (`stable-testing` on `main`, `stable` on `stable`). `Justfile:132` correctly wires `UBLUE_IMAGE_TAG=${tag}` (`:132`). | **Correct** |
| `base-image-name` | `"silverblue"` (`bluefin/Containerfile:56`) | `"hummingbird"` (`pluto/Containerfile:70`) | ✅ | ✅ Correct: must name the **actual base** (`quay.io/hummingbird-community/bootc-os` for pluto vs `quay.io/fedora-ostree-desktops/silverblue` for bluefin). Pluto's comment at `Containerfile:62-69` documents this. | **Correct, intentional divergence** |
| `fedora-version` | `"44"` (`bluefin/Containerfile:57`) | `"44"` (`pluto/Containerfile:71`) | ✅ | ✅ Correct: single source of truth for `$releasever` (`Containerfile:92-111` writes `/etc/dnf/vars/releasever`). String value, not int — matches bluefin's quoted string. Pluto's `44` matches `FEDORA_MAJOR_VERSION` and pulp repo versions (`dnf5 5.4.x, gcc 16`). | **Correct** |
| *Missing fields?* | Bluefin JSON has exactly the 7 above — no extra keys. | Pluto JSON also has exactly those 7. No missing/extra keys. | — | No extra fields needed; `common` tests only assert `image-name` + `image-tag` (`test_ublue_image_info.bats:write_image_info_fixture`). | **No missing fields** |
| JSON path | `/usr/share/ublue-os/image-info.json` (`bluefin/.../00-image-info.sh:16`) | Same (`pluto/build/00-image-info.sh:29`) | ✅ | ✅ Required by `common` consumers (`ublue-image-info.sh:4` defaults to same). | **Correct** |
| JSON formatting | `cat >$IMAGE_INFO <<EOF` with **no space** before `"image-tag":"$UBLUE_IMAGE_TAG"` (`bluefin:32`) — still valid JSON. | `cat >"${IMAGE_INFO}" <<EOF` with **space** (`pluto:52`) — more canonical. | ✅ | Both parse with `jq`; no functional difference. Pluto's quoting (`"${VAR}"`) is slightly more robust. | **Equivalent, pluto slightly better** |

**Example outputs:**

Bluefin (stable build, `VERSION=43.20250601`, `SHA_HEAD_SHORT=abc1234`):
```json
{
  "image-name": "bluefin",
  "image-flavor": "main",
  "image-vendor": "projectbluefin",
  "image-ref": "ostree-image-signed:docker://ghcr.io/projectbluefin/bluefin",
  "image-tag":"stable",
  "base-image-name": "silverblue",
  "fedora-version": "44"
}
```

Pluto (stable build, `VERSION=44.20250829` via `Justfile:106`):
```json
{
  "image-name": "pluto",
  "image-flavor": "main",
  "image-vendor": "Siddhj2206",
  "image-ref": "ostree-image-signed:docker://ghcr.io/Siddhj2206/pluto",
  "image-tag": "stable",
  "base-image-name": "hummingbird",
  "fedora-version": "44"
}
```
(Actual `image-vendor` at GHCR will be `siddhj2206` after workflow lowercasing; see defect above.)

---

## 5. `os-release` comparison (where the real divergence lives)

| `os-release` key | Bluefin behavior (`build_files/base/00-image-info.sh:38-60`) | Pluto behavior (`build/00-image-info.sh:67-88`) | Is pluto correct? |
|---|---|---|---|
| `VARIANT_ID` | `sed -i "s|^VARIANT_ID=.*|VARIANT_ID=$IMAGE_NAME|"` (`:38`) → `VARIANT_ID=bluefin` | `cat >>` `VARIANT_ID="${IMAGE_FLAVOR}"` (`:79`) → `VARIANT_ID=main` (or `nvidia`), only if no `VARIANT_ID` already exists | **Divergent.** Bluefin uses image name (identifies the *image*); pluto uses flavor (identifies *variant*). systemd spec says `VARIANT_ID` is “a lower-case string … identifying a specific variant or edition of the operating system” — both are defensible, but bluefin's pattern (name) is what `ublue` tooling expects. Tooling that keys off `VARIANT_ID=bluefin` will not match `VARIANT_ID=main`. Recommend aligning to bluefin: `VARIANT_ID="${IMAGE_NAME}"` (or lowercased). |
| `PRETTY_NAME` | `PRETTY_NAME="Bluefin (Version: ${VERSION})"` (`:39`) — includes version | `PRETTY_NAME="${IMAGE_PRETTY_NAME}"` (`:80`) — bare `"My Custom OS"` unless overridden | **Generic default is wrong.** Should be `Pluto` (or `Pluto (Version: ${VERSION})` to match bluefin). Currently pluto advertises `My Custom OS` if no `IMAGE_PRETTY_NAME` env is set (workflow/Justfile never set it). Also missing version suffix that bluefin and fastfetch's `os` module (`fastfetch.jsonc:26-29` `"type":"os","format":"{pretty-name}"`) displays. |
| `NAME` | `NAME="Bluefin"` (`:40`) | `NAME="${IMAGE_NAME}"` (`:81`) → `NAME="pluto"` | ✅ Correct (lowercase `pluto` matches `ID`), but bluefin uses pretty form (`Bluefin`). Either is fine; `NAME` is human-readable OS name. Pluto's is consistent with `IMAGE_NAME`. |
| `ID` / `ID_LIKE` | `sed -i "s|^ID=fedora|ID=${IMAGE_PRETTY_NAME,}\nID_LIKE=\"${IMAGE_LIKE}\"|"` (`:47`) → `ID=bluefin` + `ID_LIKE="fedora"` | `ID_LIKE="${IMAGE_LIKE}"` appended (`:84`) — **does not change `ID`**; leaves `ID=fedora` (or whatever hummingbird base ships). | **Incomplete.** Bluefin remaps `ID` so `ID=bluefin` (lowercased pretty name) and forces `ID_LIKE=fedora` for compat. Pluto leaves `ID` as base's value, which breaks `grep -q "^ID=fedora"` checks like `common/system_files/shared/usr/share/ublue-os/system-setup.hooks.d/10-framework.sh:43` (not fatal) but means `ID` doesn't identify pluto. The subsequent `EFIDIR=fedora` fix in bluefin (`:63`) is there because `ID` is no longer `fedora`; pluto doesn't need it if it keeps `ID=fedora`. Both are internally consistent, but if pluto ever sets `ID=pluto` it needs the grub fix. Currently correct *given* the append strategy, but documents a deliberate bluefin divergence. |
| `VERSION` / `VERSION_CODENAME` / `OSTREE_VERSION` / `BUILD_ID` | Sets `VERSION="${VERSION} (${BASE_IMAGE_NAME^})"` (`:50`), `VERSION_CODENAME="Deinonychus"` (`:49`), `OSTREE_VERSION='${VERSION}'` (`:51`), `BUILD_ID="$SHA_HEAD_SHORT"` (`:54`), `CPE_NAME` (`:45`), `DEFAULT_HOSTNAME` (`:46`), strips `REDHAT_*` (`:48`) | **Appends none of these**. Only sets `IMAGE_VERSION="${OS_VERSION}"` (`:83`) where `OS_VERSION` is `${VERSION:-$UBLUE_IMAGE_TAG}`. | **Missing fields that downstream expects.** `OSTREE_VERSION` is used by `changelogs` recipe (`custom-system.just:197`: `grep -oP "OSTREE_VERSION=.*\d{2}\.\K\d{8}[.0-9]*" /etc/os-release`) to fetch the correct GitHub Release tag. If the base `os-release` lacks `OSTREE_VERSION`, `DATE` will be empty and `changelogs` will fall back to `latest`. Not fatal, but degraded. `VERSION` with `(Hummingbird)` would be more informative than bare `${IMAGE_PRETTY_NAME}`. `CPE_NAME`/`REDHAT_*` stripping is Fedora-specific cleanup — optional for Hummingbird but matches bluefin hygiene. |
| `IMAGE_ID` / `IMAGE_VERSION` | `IMAGE_ID="${IMAGE_NAME}"` (`:59`) + `IMAGE_VERSION="${VERSION}"` (`:60`) via `>>` append, plus `BUILD_ID` | `IMAGE_ID="${IMAGE_NAME}"` (`:82`) + `IMAGE_VERSION="${OS_VERSION}"` (`:83`) via `>>` append | ✅ **Correct** — both set the systemd `IMAGE_ID`/`IMAGE_VERSION` keys (added in systemd 249, per comment `:58`). Pluto correctly uses `OS_VERSION` (`VERSION` or `UBLUE_IMAGE_TAG` fallback). |
| `HOME_URL` / `DOCUMENTATION_URL` / `SUPPORT_URL` / `BUG_REPORT_URL` | Overwrites in place to `projectbluefin.io` / `docs.projectbluefin.io` / `github.com/projectbluefin/bluefin/issues` (`:41-44`) | Appends to `github.com/${IMAGE_VENDOR}/${IMAGE_NAME}` defaults (`:85-88`) — evaluates to `github.com/Siddhj2206/pluto` or lowercased at CI | ✅ Correct for template. More generic but appropriate for a fork. If `IMAGE_VENDOR` is mixed-case, URLs will have mixed-case owner — ideally lowercased. |
| `CPE_NAME` / `DEFAULT_HOSTNAME` | Remapped to `cpe:/o:universal-blue:bluefin` and `bluefin` (`:45-46`) | Not touched | Optional. Only matters for `CPE_NAME` consumers and hostname default. Not required for pluto to boot, but bluefin pattern does it. |
| Guard condition | Unconditional `sed -i` (always overwrites) | `if [[ -f "${OS_RELEASE}" ]] && ! grep -q "^VARIANT_ID=" "${OS_RELEASE}"` (`:67`) — skips if `VARIANT_ID` already set | **Different intent.** Bluefin always force-brands (base is `fedora` Silverblue, so overwrite is required). Pluto appends only once to avoid double-append on rebuilds. For Hummingbird base which has **no `VARIANT_ID`** (verified: hummingbird `os-release` `VERSION_ID` is the hum build number, not Fedora), the guard is effectively always true on first build, so it works. But if base ever adds `VARIANT_ID`, pluto will silently not brand. Bluefin's unconditional overwrite is more robust. Recommend removing guard or making it `grep -q "^VARIANT_ID=${IMAGE_NAME}"` with overwrite. |

**Why pluto's append-only strategy exists (and is arguably correct for Hummingbird):**
`pluto/Containerfile:62-69` explains the Hummingbird base's `os-release` is not Fedora-standard (`VERSION_ID` is the hum build number, not `44`). Bluefin's `sed -i "s|^VARIANT_ID=.*|..."` assumes `VARIANT_ID` exists; Hummingbird's may not, so `sed` would be a no-op. Appending is safer for a base that lacks those keys. However, bluefin's script runs **after** `rsync system_files/shared` (in Stage 2 `Containerfile:83-86` overlay), so its `sed` targets are guaranteed to exist from the base. Pluto runs `00-image-info.sh` **before** `10-build.sh` (`Containerfile:83-86` vs `117-122`), and Hummingbird's `os-release` may not have `VARIANT_ID` to replace — so append is pragmatic. The guard should still be improved.

---

## 6. Verdict: is pluto correct? What should change?

### 6.1 Overall

**`image-info.json` itself is correct.** Pluto writes the exact 7-key schema bluefin writes, to the correct path, with correct semantics for 6 of 7 fields. The file will be consumed correctly by `common`'s `ublue-image-info.sh` (fastfetch) and by the ported `changelogs` recipe. No missing fields, no wrong path, correct `ostree-image-signed` transport. Promotion, `bootc upgrade`, and `fastfetch` will work.

**`os-release` branding is template-correct but bluefin-divergent in 4 small ways.** None are fatal for boot, but they reduce polish and break one downstream assumption (`OSTREE_VERSION`).

### 6.2 Required fixes (defects that should change)

| # | Defect | Evidence | Fix | Severity |
|---|---|---|---|---|
| 1 | **`IMAGE_VENDOR` default has wrong case** (`Siddhj2206`) | `pluto/Containerfile:60` `ARG IMAGE_VENDOR="Siddhj2206"` vs bluefin `Containerfile:59` `ARG IMAGE_VENDOR="projectbluefin"` (lower) and `ghcr.io` lowercase requirement; workflow lowercases `IMAGE_NAME` but not `IMAGE_VENDOR` default | Change to `ARG IMAGE_VENDOR="siddhj2206"` (all lower). Optionally make `build/00-image-info.sh:40` use `"${IMAGE_VENDOR,,}"` to self-heal. | **Medium** — breaks local `just build` without env; CI masks it via `github.repository_owner` (already lower). |
| 2 | **`IMAGE_PRETTY_NAME` defaults to `"My Custom OS"`** | `pluto/build/00-image-info.sh:21` `IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-My Custom OS}"` vs bluefin `:7` `IMAGE_PRETTY_NAME="Bluefin"` and no env ever sets it (`Justfile`/`build-image.yml` don't pass `IMAGE_PRETTY_NAME`) | Set default to `"Pluto"` (or `"Pluto (Version: ${VERSION})"`-style via os-release). At minimum: `IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Pluto}"`. | **Medium** — `PRETTY_NAME` and `NAME` currently advertise generic junk; fastfetch `os` module will show `My Custom OS`. |
| 3 | **`VARIANT_ID` set to flavor (`main`) not name (`pluto`)** | `pluto/build/00-image-info.sh:79` `VARIANT_ID="${IMAGE_FLAVOR}"` vs bluefin `:38` `VARIANT_ID=$IMAGE_NAME` | Align to bluefin: `VARIANT_ID="${IMAGE_NAME}"` (or `"${IMAGE_NAME,,}"`). If you need flavor distinction, use `VARIANT_ID="${IMAGE_NAME}-${IMAGE_FLAVOR}"` but don't keep bare `main`. | **Low-Medium** — `VARIANT_ID=main` is collision-prone (`main` is not unique to pluto); any tool filtering by `VARIANT_ID=pluto` will miss. |
| 4 | **Missing `OSTREE_VERSION` / `VERSION` in `os-release`** breaks `ujust changelogs` date extraction | `pluto/build/00-image-info.sh:69-83` never sets `VERSION`/`OSTREE_VERSION` vs bluefin `:50-51` `VERSION="${VERSION} (${BASE_IMAGE_NAME^})"` / `OSTREE_VERSION='${VERSION}'`; consumer is `pluto/custom/ujust/custom-system.just:197` `grep -oP "OSTREE_VERSION=.*\d{2}\.\K\d{8}[.0-9]*" /etc/os-release` | Add `VERSION` and `OSTREE_VERSION` handling: if `VERSION` is non-empty, set `VERSION="${VERSION} (${BASE_IMAGE_NAME^})"` and `OSTREE_VERSION='${VERSION}'` (or at least `OSTREE_VERSION`). Could also set `VERSION_CODENAME` (optional). | **Low** — `changelogs` degrades to `latest` fallback, not fatal. But parity with bluefin is one line. |

### 6.3 Optional polish (nice-to-have for full bluefin parity)

* **Set `ID=pluto` + `ID_LIKE=fedora` + `CPE_NAME`/`DEFAULT_HOSTNAME`** like bluefin `:45-47` if you want `ID` to identify pluto. Currently you keep base's `ID` (likely `fedora` or `hummingbird`). Both are defensible, but if you change `ID`, you must also add bluefin's grub fix (`:63` `sed -i "s|^EFIDIR=.*|EFIDIR=\"fedora\"|" /usr/sbin/grub2-switch-to-blscfg`) to keep `grub2-switch-to-blscfg` working.
* **Ship `fastfetch-user-count`/`bazaar-install-count` placeholders** (`bluefin/.../00-image-info.sh:66-67` `echo "…" > /usr/share/ublue-os/{fastfetch-user-count,bazaar-install-count}`) if you ever ship `common`'s `fastfetch.jsonc` from `common/system_files/bluefin`. Currently pluto doesn't, so not needed.
* **Consider propagating `SHA_HEAD_SHORT`/`CODE_NAME` via Containerfile ARGs** (`bluefin/Containerfile:109-110` `ARG SHA_HEAD_SHORT`/`ARG VERSION`) to populate `BUILD_ID`/`VERSION_CODENAME`. Not templated, only for release traceability.
* **Make `os-release` mutation unconditional** (remove `! grep -q "^VARIANT_ID="` guard at `pluto/build/00-image-info.sh:67`) or change to overwrite semantics with `sed -i` for keys that exist and `>>` for keys that don't, matching bluefin's idempotence without double-append risk.

### 6.4 What is already correct and should not change

* **JSON schema, path, and `image-ref` transport** — exact match to bluefin and to `common`'s expectations (`common/tests/test_ublue_image_info.bats` mocks only `image-name`/`image-tag`; any extra keys are tolerated). Citation: `pluto/build/00-image-info.sh:29` vs `bluefin/build_files/base/00-image-info.sh:16`; both `/usr/share/ublue-os/image-info.json`.
* **`BASE_IMAGE_NAME` / `FEDORA_MAJOR_VERSION` wiring** — correctly diverge to `hummingbird`/`44` and are correctly wired to `Containerfile:92-111` (`printf '%s\n' "${FEDORA_MAJOR_VERSION}" > /etc/dnf/vars/releasever`) and to `dnf5` repo files. Don't change back to `silverblue`.
* **`image-tag` / `UBLUE_IMAGE_TAG` plumbing** — `Containerfile:61` `ARG UBLUE_IMAGE_TAG="stable"`, `Justfile:132` `UBLUE_IMAGE_TAG=${tag}`, `build-image.yml:78-84` `TAG_STREAM` logic — all correctly produce `pluto:stable` and `pluto:stable-testing` tags matching bluefin's two-stream model.
* **`HOME_URL`/`DOCUMENTATION_URL`/`SUPPORT_URL` templating** to `github.com/${IMAGE_VENDOR}/${IMAGE_NAME}` — correct for a fork (bluefin hardcodes `projectbluefin.io`).
* **Flavor derivation** — `nvidia` substring check is identical in both scripts and matches bluefin's actual variant handling.

---

## 7. File:line citation index

| Claim | File:line |
|---|---|
| Pluto script header + required env vars | `pluto/build/00-image-info.sh:12-18` |
| Pluto branding defaults (`My Custom OS`) | `pluto/build/00-image-info.sh:21-26` |
| Pluto `IMAGE_INFO` path | `pluto/build/00-image-info.sh:29` |
| Pluto flavor derivation | `pluto/build/00-image-info.sh:33-37` |
| Pluto `IMAGE_REF` | `pluto/build/00-image-info.sh:40` |
| Pluto JSON write (7 keys) | `pluto/build/00-image-info.sh:46-56` |
| Pluto `os-release` guard + append | `pluto/build/00-image-info.sh:67-88` |
| Pluto `VARIANT_ID` = flavor | `pluto/build/00-image-info.sh:79` |
| Pluto `PRETTY_NAME` without version | `pluto/build/00-image-info.sh:80` |
| Pluto Containerfile `IMAGE_NAME`/`IMAGE_VENDOR`/`UBLUE_IMAGE_TAG` | `pluto/Containerfile:59-61` |
| Pluto `BASE_IMAGE_NAME`/`FEDORA_MAJOR_VERSION` | `pluto/Containerfile:70-71` |
| Pluto `VERSION` empty default | `pluto/Containerfile:72` |
| Pluto `00-image-info.sh` invocation before `10-build.sh` | `pluto/Containerfile:83-86` vs `:117-122` |
| Pluto Containerfile hummingbird base | `pluto/Containerfile:55` |
| Pluto workflow lowercases `IMAGE_NAME` | `pluto/.github/workflows/build-image.yml:65` |
| Pluto workflow `IMAGE_VENDOR` from `github.repository_owner` | `pluto/.github/workflows/build-image.yml:35` |
| Pluto `Justfile` `VERSION` generation | `pluto/Justfile:98-126` |
| Pluto `Justfile` wires `IMAGE_VENDOR`/`IMAGE_NAME`/`UBLUE_IMAGE_TAG` | `pluto/Justfile:130-132` |
| Pluto custom `changelogs` reads `image-tag` + `OSTREE_VERSION` | `pluto/custom/ujust/custom-system.just:193-197` |
| Bluefin script branding (`Bluefin`, `Deinonychus`) | `bluefin/build_files/base/00-image-info.sh:7-13` |
| Bluefin `VERSION` default | `bluefin/build_files/base/00-image-info.sh:14` |
| Bluefin `IMAGE_INFO` path | `bluefin/build_files/base/00-image-info.sh:16` |
| Bluefin `IMAGE_REF` | `bluefin/build_files/base/00-image-info.sh:17` |
| Bluefin flavor derivation | `bluefin/build_files/base/00-image-info.sh:20-23` |
| Bluefin JSON write | `bluefin/build_files/base/00-image-info.sh:25-35` |
| Bluefin `os-release` `VARIANT_ID=IMAGE_NAME` | `bluefin/build_files/base/00-image-info.sh:38` |
| Bluefin `PRETTY_NAME` with version | `bluefin/build_files/base/00-image-info.sh:39` |
| Bluefin `ID` remap + `ID_LIKE` | `bluefin/build_files/base/00-image-info.sh:47` |
| Bluefin `CPE_NAME`/`DEFAULT_HOSTNAME`/`REDHAT_*` stripping | `bluefin/build_files/base/00-image-info.sh:45-48` |
| Bluefin `VERSION`/`OSTREE_VERSION`/`BUILD_ID`/`IMAGE_ID`/`IMAGE_VERSION` | `bluefin/build_files/base/00-image-info.sh:49-60` |
| Bluefin `EFIDIR` grub fix | `bluefin/build_files/base/00-image-info.sh:63` |
| Bluefin placeholders for fastfetch | `bluefin/build_files/base/00-image-info.sh:66-67` |
| Bluefin Containerfile global ARGs | `bluefin/Containerfile:1-10` |
| Bluefin Containerfile per-stage `IMAGE_VENDOR` | `bluefin/Containerfile:59` |
| Common `ublue-image-info.sh` reads `image-name`/`image-tag` | `common/system_files/shared/usr/bin/ublue-image-info.sh:4-6` |
| Common fastfetch config consumes `ublue-image-info.sh` | `common/system_files/bluefin/usr/share/ublue-os/fastfetch.jsonc:22-24` |
| Common `changelog.just` reads `image-tag`/`image-name` | `common/system_files/bluefin/usr/share/ublue-os/just/changelog.just:11-15` |
| Common `system.just` `toggle-testing` reads `image-tag`/`image-ref` | `common/system_files/bluefin/usr/share/ublue-os/just/system.just:248-252` |
| Bluefin ISO builder reads `image-ref` | `bluefin/build_files/base/21-container-native-iso.sh:8-14` |
| Pluto `custom/files` has no `image-info.json` | `pluto/custom/files` tree (verified via `find` — no json) |

---

*Generated by local audit against `/tmp/opencode/bluefin` (depth 1 clone 2026-08-28) and `/tmp/opencode/common` (depth 1 clone 2026-08-28) vs `/var/home/sid/Documents/Projects/pluto` HEAD.*
