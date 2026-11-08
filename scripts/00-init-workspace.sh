#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/refs.env"

mkdir -p \
  "${PROJECT_ROOT}/artifacts" \
  "${PROJECT_ROOT}/build" \
  "${PROJECT_ROOT}/ccache" \
  "${PROJECT_ROOT}/downloads" \
  "${PROJECT_ROOT}/keys" \
  "${PROJECT_ROOT}/logs" \
  "${PROJECT_ROOT}/src" \
  "${PROJECT_ROOT}/tmp" \
  "${PROJECT_ROOT}/upstream"

printf 'workspace ready: %s\n' "${PROJECT_ROOT}"
