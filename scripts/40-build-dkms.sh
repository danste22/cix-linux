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

if [[ "${component}" == "vpu" ]]; then
  rules="${tree}/debian/rules"
  if ! grep -q '^override_dh_auto_clean:' "${rules}"; then
    cat >> "${rules}" <<'EOF'

override_dh_auto_clean:
	# Upstream clean calls kbuild for `uname -r`. This package only ships
	# DKMS source; the module is built later against the O6N headers.
	true
EOF
  fi
fi

current_version="$(dpkg-parsechangelog -l "${tree}/debian/changelog" -S Version)"
if [[ ! "${current_version}" =~ o6n[0-9]+$ ]]; then
  (
    cd "${tree}"
    DEBEMAIL="${DEBEMAIL:-build@o6n.invalid}" \
    DEBFULLNAME="${DEBFULLNAME:-O6N Kernel Builder}" \
      dch --local o6n --distribution trixie-backports \
          "Rebuild for the O6N Debian 13 repository."
  )
fi

(
  cd "${tree}"
  dpkg-buildpackage --build=binary --no-sign
)

destination="${ARTIFACTS_DIR}/dkms-${component}"
mkdir -p "${destination}"
shopt -s nullglob
packages=(
  "${UPSTREAM_DIR}"/cix-${component}-*.deb
  "${UPSTREAM_DIR}"/cix-${component}_*.changes
  "${UPSTREAM_DIR}"/cix-${component}_*.buildinfo
)
(( ${#packages[@]} > 0 )) || die "no ${component} packages were produced"
cp -v "${packages[@]}" "${destination}/"

printf '%s artifacts: %s\n' "${component}" "${destination}"
