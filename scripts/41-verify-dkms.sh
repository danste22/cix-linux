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
    \( -name 'linux-headers-*arm64_*.deb' -o -name 'linux-headers-*-common_*.deb' \) \
    -print
)
mapfile -t dkms_debs < <(
  find "${ARTIFACTS_DIR}/dkms-${component}" -type f \
    -name "cix-${component}-driver-dkms_*.deb" -print
)

[[ "${#header_debs[@]}" -gt 0 ]] || die "no O6N header packages found"
[[ "${#dkms_debs[@]}" -eq 1 ]] || die "expected one ${component} DKMS package"

apt-get update -qq
apt-get install -y "${header_debs[@]}" "${dkms_debs[@]}"

kernel_version="$(
  dpkg-deb --field "${header_debs[0]}" Package \
    | sed -n 's/^linux-headers-//p'
)"
[[ -n "${kernel_version}" ]] || die "cannot derive kernel version"

dkms status | grep -F "${kernel_version}" \
  || die "DKMS did not build for ${kernel_version}"

printf 'verified %s DKMS build for %s (module not loaded)\n' \
  "${component}" "${kernel_version}"
