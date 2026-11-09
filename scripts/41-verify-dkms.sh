#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

component="${1:-}"
[[ "${component}" == "npu" || "${component}" == "vpu" ]] \
  || die "usage: $0 npu|vpu"

mapfile -t header_debs < <(
  find "${ARTIFACTS_DIR}/kernel" -type f \
    \( -name 'linux-base-[0-9]*+deb13o6n*-arm64_*.deb' \
       -o -name 'linux-headers-[0-9]*+deb13o6n*-arm64_*.deb' \
       -o -name 'linux-headers-*+deb13o6n*-common_*.deb' \
       -o -name 'linux-kbuild-*+deb13o6n*_*.deb' \) \
       ! -name '*-dbgsym_*.deb' \
    -print | LC_ALL=C sort
)
mapfile -t dkms_debs < <(
  find "${ARTIFACTS_DIR}/dkms-${component}" -type f \
    -name "cix-${component}-driver-dkms_*.deb" -print
)

[[ "$(printf '%s\n' "${header_debs[@]}" | grep -c '/linux-headers-[0-9].*-arm64_')" -eq 1 ]] \
  || die "expected one versioned O6N arm64 headers package"
[[ "$(printf '%s\n' "${header_debs[@]}" | grep -c '/linux-headers-.*-common_')" -eq 1 ]] \
  || die "expected linux-headers-*-common"
[[ "$(printf '%s\n' "${header_debs[@]}" | grep -c '/linux-kbuild-')" -eq 1 ]] \
  || die "expected linux-kbuild"
[[ "$(printf '%s\n' "${header_debs[@]}" | grep -c '/linux-base-[0-9]')" -eq 1 ]] \
  || die "expected the versioned linux-base package"
[[ "${#dkms_debs[@]}" -eq 1 ]] || die "expected one ${component} DKMS package"

extra_debs=()
if [[ "${component}" == "vpu" ]]; then
  mapfile -t extra_debs < <(
    find "${ARTIFACTS_DIR}/firmware-package" -type f \
      -name 'cix-o6n-firmware-install_*.deb' -print
  )
  [[ "${#extra_debs[@]}" -eq 1 ]] \
    || die "build cix-o6n-firmware-install before verifying the VPU DKMS package"
  cat > /etc/apt/sources.list.d/o6n-backports.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
EOF
fi

apt-get update -qq
apt-get install -y "${header_debs[@]}" "${extra_debs[@]}" "${dkms_debs[@]}"

versioned_headers="$(printf '%s\n' "${header_debs[@]}" | grep -E '/linux-headers-[0-9].*-arm64_' | head -n 1)"
[[ -n "${versioned_headers}" ]] || die "no versioned O6N header package found"
kernel_version="$(
  dpkg-deb --field "${versioned_headers}" Package \
    | sed -n 's/^linux-headers-//p'
)"
[[ -n "${kernel_version}" ]] || die "cannot derive kernel version"

dkms status | grep -F "${kernel_version}" \
  || die "DKMS did not build for ${kernel_version}"

printf 'verified %s DKMS build for %s (module not loaded)\n' \
  "${component}" "${kernel_version}"
