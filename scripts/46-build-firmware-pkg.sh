#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

package_source="${SRC_DIR}/cix-o6n-firmware-install"
rm -rf "${package_source}"
mkdir -p "${package_source}"
cp -a "${PROJECT_ROOT}/packaging/cix-o6n-firmware-install/." "${package_source}/"
cp "${PROJECT_ROOT}/firmware/manifest.txt" "${package_source}/"
cp "${PROJECT_ROOT}/firmware/README.firmware.txt" "${package_source}/"

(
  cd "${package_source}"
  dpkg-buildpackage --build=binary --no-sign
)

destination="${ARTIFACTS_DIR}/firmware-package"
mkdir -p "${destination}"
shopt -s nullglob
packages=(
  "${SRC_DIR}"/cix-o6n-firmware-install_*.deb
  "${SRC_DIR}"/cix-o6n-firmware-install_*.changes
  "${SRC_DIR}"/cix-o6n-firmware-install_*.buildinfo
)
(( ${#packages[@]} > 0 )) || die "firmware package build produced no packages"
cp -v "${packages[@]}" "${destination}/"

printf 'firmware package artifacts: %s\n' "${destination}"
