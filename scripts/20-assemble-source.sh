#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_command dch
require_command dpkg-source
require_command quilt

debian_dir="${DOWNLOADS_DIR}/debian"
source_tree="${SRC_DIR}/linux"
cix_tree="${UPSTREAM_DIR}/cix-linux-main"
patch_source="${cix_tree}/${CIX_KERNEL_PATCH_DIR}"

require_file "${debian_dir}/${DEBIAN_DSC}"
[[ -d "${patch_source}" ]] || die "missing CIX patch directory: ${patch_source}"

rm -rf "${source_tree}"
mkdir -p "${SRC_DIR}"
dpkg-source -x "${debian_dir}/${DEBIAN_DSC}" "${source_tree}"

mkdir -p "${source_tree}/debian/patches/cix"
mapfile -t cix_patches < <(find "${patch_source}" -maxdepth 1 -type f -name '*.patch' -print | sort)
[[ "${#cix_patches[@]}" -gt 0 ]] || die "no CIX patches found"

for patch in "${cix_patches[@]}"; do
  name="cix/$(basename "${patch}")"
  cp "${patch}" "${source_tree}/debian/patches/${name}"
  printf '%s\n' "${name}" >> "${source_tree}/debian/patches/series"
done

(
  cd "${source_tree}"
  QUILT_PATCHES=debian/patches quilt push --quiltrc - -a --fuzz=0
  DEBEMAIL="${DEBEMAIL:-build@o6n.invalid}" \
  DEBFULLNAME="${DEBFULLNAME:-O6N Kernel Builder}" \
    dch --newversion "${O6N_PACKAGE_VERSION}" \
        --distribution trixie-backports \
        "Add the O6N CIX patch stack and packaging."
)

printf 'assembled source: %s\n' "${source_tree}"
