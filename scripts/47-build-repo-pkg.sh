#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

package_source="${SRC_DIR}/cix-o6n-repo"
rm -rf "${package_source}"
mkdir -p "${package_source}"
rsync -a "${PROJECT_ROOT}/packaging/cix-o6n-repo/" "${package_source}/"

(
  cd "${package_source}"
  dpkg-buildpackage --build=binary --no-sign
)

destination="${ARTIFACTS_DIR}/repo-package"
mkdir -p "${destination}"
find "${SRC_DIR}" -maxdepth 1 -type f \
  \( -name 'cix-o6n-repo_*.deb' \
     -o -name 'cix-o6n-repo_*.changes' \
     -o -name 'cix-o6n-repo_*.buildinfo' \) \
  -exec cp -v {} "${destination}/" \;

printf 'repository package artifacts: %s\n' "${destination}"
