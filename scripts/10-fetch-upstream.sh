#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_command bsdtar
require_command curl
require_command dscverify
require_command git
require_command sha256sum

debian_dir="${DOWNLOADS_DIR}/debian"
mkdir -p "${debian_dir}" "${UPSTREAM_DIR}"

fetch_file "${DEBIAN_SOURCE_BASE_URL}/${DEBIAN_DSC}" \
  "${debian_dir}/${DEBIAN_DSC}" "${DEBIAN_DSC_SHA256}"
fetch_file "${DEBIAN_SOURCE_BASE_URL}/${DEBIAN_ORIG}" \
  "${debian_dir}/${DEBIAN_ORIG}" "${DEBIAN_ORIG_SHA256}"
fetch_file "${DEBIAN_SOURCE_BASE_URL}/${DEBIAN_TAR}" \
  "${debian_dir}/${DEBIAN_TAR}" "${DEBIAN_TAR_SHA256}"

dscverify "${debian_dir}/${DEBIAN_DSC}"

checkout_commit "${CIX_KERNEL_REPO}" "${CIX_KERNEL_REF}" \
  "${UPSTREAM_DIR}/cix-linux-main"
checkout_commit "${CIX_NPU_REPO}" "${CIX_NPU_REF}" \
  "${UPSTREAM_DIR}/cix-npu-driver"
checkout_commit "${CIX_VPU_REPO}" "${CIX_VPU_REF}" \
  "${UPSTREAM_DIR}/cix-vpu-driver"

printf 'verified Debian source and pinned CIX commits\n'
