#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

component="${1:-}"
case "${component}" in
  npu)
    tree="${UPSTREAM_DIR}/cix-npu-driver"
    ;;
  vpu)
    tree="${UPSTREAM_DIR}/cix-vpu-driver"
    "${SCRIPT_DIR}/22-strip-vpu-firmware.sh"
    ;;
  *)
    die "usage: $0 npu|vpu"
    ;;
esac

[[ -f "${tree}/debian/control" ]] || die "missing ${component} packaging"

(
  cd "${tree}"
  DEBEMAIL="${DEBEMAIL:-build@o6n.invalid}" \
  DEBFULLNAME="${DEBFULLNAME:-O6N Kernel Builder}" \
    dch --local o6n --distribution trixie-backports \
        "Rebuild for the O6N Debian 13 repository."
  dpkg-buildpackage --build=binary --no-sign
)

destination="${ARTIFACTS_DIR}/dkms-${component}"
mkdir -p "${destination}"
find "${UPSTREAM_DIR}" -maxdepth 1 -type f \
  \( -name "cix-${component}-*.deb" -o -name '*.changes' -o -name '*.buildinfo' \) \
  -exec cp -v {} "${destination}/" \;

printf '%s artifacts: %s\n' "${component}" "${destination}"
