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
    make --jobs="${jobs}" -f debian/rules.gen \
      binary-arch_arm64_none_arm64 \
      binary-arch_arm64_kbuild \
      binary-indep_none_headers-common
)

mkdir -p "${ARTIFACTS_DIR}/kernel"
# src/ is a case-sensitive APFS volume. find stats macOS metadata dirs
# (.Trashes, .fseventsd, .Spotlight-V100) that disappear inside the
# container and returns 1. Copy the package globs instead.
shopt -s nullglob
packages=(
  "${SRC_DIR}"/*.deb
  "${SRC_DIR}"/*.changes
  "${SRC_DIR}"/*.buildinfo
)
(( ${#packages[@]} > 0 )) || die "kernel build produced no packages in ${SRC_DIR}"
cp -v "${packages[@]}" "${ARTIFACTS_DIR}/kernel/"
rm -f "${ARTIFACTS_DIR}/kernel"/linux-image-*-dbg_*.deb \
      "${ARTIFACTS_DIR}/kernel"/*-dbgsym_*.deb \
      "${ARTIFACTS_DIR}/kernel"/*.udeb \
      "${ARTIFACTS_DIR}/kernel"/linux-image-arm64_*.deb \
      "${ARTIFACTS_DIR}/kernel"/linux-headers-arm64_*.deb \
      "${ARTIFACTS_DIR}/kernel"/linux-base-arm64_*.deb \
      "${ARTIFACTS_DIR}/kernel"/linux-bpf-dev_*.deb \
      "${ARTIFACTS_DIR}/kernel"/linux-libc-dev_*.deb
forbidden="$(
  find "${ARTIFACTS_DIR}/kernel" -maxdepth 1 -type f \( \
    -name 'linux-image-arm64_*.deb' -o \
    -name 'linux-headers-arm64_*.deb' -o \
    -name 'linux-base-arm64_*.deb' -o \
    -name 'linux-bpf-dev_*.deb' -o \
    -name 'linux-libc-dev_*.deb' -o \
    -name '*.udeb' -o \
    -name 'linux-image-*-dbg_*.deb' \
  \) -print
)"
if [[ -n "${forbidden}" ]]; then
  printf 'refusing to publish colliding kernel packages:\n%s\n' "${forbidden}" >&2
  exit 1
fi
printf 'kernel artifacts: %s\n' "${ARTIFACTS_DIR}/kernel"
