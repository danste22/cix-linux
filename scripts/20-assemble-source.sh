#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_command dch
require_command bsdtar
require_command dpkg-source
require_command python3
require_command quilt

debian_dir="${DOWNLOADS_DIR}/debian"
source_tree="${SRC_DIR}/linux"
extract_tree="${SRC_DIR}/.linux-extract"
cix_tree="${UPSTREAM_DIR}/cix-linux-main"
patch_source="${cix_tree}/${CIX_KERNEL_PATCH_DIR}"

require_file "${debian_dir}/${DEBIAN_DSC}"
require_file "${debian_dir}/${DEBIAN_ORIG}"
require_file "${debian_dir}/${DEBIAN_TAR}"
[[ -d "${patch_source}" ]] || die "missing CIX patch directory: ${patch_source}"

rm -rf "${source_tree}" "${extract_tree}"
mkdir -p "${extract_tree}"

# GNU tar's directory inode check fails on Docker Desktop bind mounts. libarchive
# does not depend on stable synthetic inode numbers and writes to the same
# project-local filesystem.
bsdtar -C "${extract_tree}" -xf "${debian_dir}/${DEBIAN_ORIG}"
mapfile -t extracted_dirs < <(
  find "${extract_tree}" -mindepth 1 -maxdepth 1 -type d -print
)
[[ "${#extracted_dirs[@]}" -eq 1 ]] \
  || die "expected one directory in the Debian orig tarball"
mv "${extracted_dirs[0]}" "${source_tree}"
rm -rf "${extract_tree}"

bsdtar -C "${source_tree}" -xf "${debian_dir}/${DEBIAN_TAR}"
dpkg-source --before-build "${source_tree}"

mkdir -p "${source_tree}/debian/patches/cix"
mapfile -t cix_patches < <(find "${patch_source}" -maxdepth 1 -type f -name '*.patch' -print | sort)
[[ "${#cix_patches[@]}" -gt 0 ]] || die "no CIX patches found"

for patch in "${cix_patches[@]}"; do
  name="cix/$(basename "${patch}")"
  cp "${patch}" "${source_tree}/debian/patches/${name}"
  if [[ "$(basename "${patch}")" == \
        "0013-DPTSW-26459-sound-hda-rework-cix-ipbloq-based-on-mai.patch" ]]; then
    # GNU patch treats this upstream hunk's 12+2 asymmetric context as an
    # end-of-file match. Keep the same change with balanced 2+2 context.
    python3 "${SCRIPT_DIR}/lib/rewrite-cix-0013-context.py" \
      "${source_tree}/debian/patches/${name}"
  fi
  printf '%s\n' "${name}" >> "${source_tree}/debian/patches/series"
done

local_patch_dir="${PROJECT_ROOT}/patches/o6n"
if [[ -d "${local_patch_dir}" ]]; then
  mkdir -p "${source_tree}/debian/patches/o6n"
  mapfile -t local_patches < <(
    find "${local_patch_dir}" -maxdepth 1 -type f -name '*.patch' -print | sort
  )
  for patch in "${local_patches[@]}"; do
    name="o6n/$(basename "${patch}")"
    cp "${patch}" "${source_tree}/debian/patches/${name}"
    printf '%s\n' "${name}" >> "${source_tree}/debian/patches/series"
  done
fi

(
  cd "${source_tree}"
  QUILT_PATCHES=debian/patches quilt push --quiltrc - -a --fuzz=0
  DEBEMAIL="${DEBEMAIL:-build@o6n.invalid}" \
  DEBFULLNAME="${DEBFULLNAME:-O6N Kernel Builder}" \
    dch --newversion "${O6N_PACKAGE_VERSION}" \
        --force-distribution \
        --distribution trixie-backports \
        "Add the O6N CIX patch stack and packaging."
)

printf 'assembled source: %s\n' "${source_tree}"
