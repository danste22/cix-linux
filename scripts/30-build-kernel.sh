#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

source_tree="${SRC_DIR}/linux"
[[ -f "${source_tree}/debian/control" ]] || die "prepare the kernel config first"

jobs="${DEBIAN_KERNEL_JOBS:-$(nproc)}"
(
  cd "${source_tree}"
  DEB_BUILD_OPTIONS="parallel=${jobs} terse" \
  DEBIAN_KERNEL_JOBS="${jobs}" \
    make -f debian/rules binary-arch_arm64_none_arm64
)

mkdir -p "${ARTIFACTS_DIR}/kernel"
find "${SRC_DIR}" -maxdepth 1 -type f \
  \( -name '*.deb' -o -name '*.changes' -o -name '*.buildinfo' \) \
  -exec cp -v {} "${ARTIFACTS_DIR}/kernel/" \;

find "${ARTIFACTS_DIR}/kernel" -type f -name 'linux-image-*-dbg_*.deb' -delete
printf 'kernel artifacts: %s\n' "${ARTIFACTS_DIR}/kernel"
