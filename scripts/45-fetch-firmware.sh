#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

manifest="${PROJECT_ROOT}/firmware/manifest.txt"
destination="${DOWNLOADS_DIR}/firmware"
staging="${destination}.staging"

require_file "${manifest}"
rm -rf "${staging}"
mkdir -p "${staging}"

count=0
while IFS='|' read -r path sha256 url; do
  [[ -z "${path}" || "${path}" == \#* ]] && continue
  [[ "${path}" != */* && "${path}" != "." && "${path}" != ".." ]] \
    || die "unsafe firmware destination: ${path}"
  [[ "${sha256}" =~ ^[0-9a-f]{64}$ ]] || die "invalid sha256 for ${path}"
  [[ "${url}" == https://* ]] || die "non-HTTPS firmware URL for ${path}"
  fetch_file "${url}" "${staging}/${path}" "${sha256}"
  count=$((count + 1))
done < "${manifest}"

[[ "${count}" -eq 17 ]] || die "expected 17 firmware files, got ${count}"

rm -rf "${destination}"
mv "${staging}" "${destination}"
printf 'verified %d firmware files in %s\n' "${count}" "${destination}"
