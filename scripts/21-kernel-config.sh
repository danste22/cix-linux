#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

source_tree="${SRC_DIR}/linux"
delta="${PROJECT_ROOT}/config/cix-7.2-delta.config"

[[ -d "${source_tree}/debian" ]] || die "assemble the source tree first"
require_file "${delta}"
grep -Eq '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set)' "${delta}" \
  || die "CIX config delta is still a scaffold; derive it at Gate 3"

python3 "${SCRIPT_DIR}/lib/prepare_kernel_packaging.py" "${source_tree}"

mkdir -p "${source_tree}/debian/config.local/arm64"
cp "${delta}" "${source_tree}/debian/config.local/arm64/config"

(
  cd "${source_tree}"
  make -f debian/rules debian/control-real
)

printf 'prepared arm64-only unsigned O6N kernel config\n'
