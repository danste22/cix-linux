#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

vpu_tree="${UPSTREAM_DIR}/cix-vpu-driver"
[[ -d "${vpu_tree}/debian" ]] || die "fetch the pinned VPU source first"

rm -rf "${vpu_tree}/firmware-binaries"
rm -f \
  "${vpu_tree}/debian/cix-vpu-firmware.install" \
  "${vpu_tree}/debian/cix-vpu-firmware.lintian-overrides"

python3 "${SCRIPT_DIR}/lib/strip_vpu_firmware.py" "${vpu_tree}"

! grep -Rqs 'firmware-binaries\|Package: cix-vpu-firmware' \
  "${vpu_tree}/debian" \
  || die "VPU firmware packaging references remain"

printf 'removed VPU firmware bytes and redirected the DKMS dependency\n'
