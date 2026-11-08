#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/refs.env"

mkdir -p \
  "${PROJECT_ROOT}/downloads" \
  "${CIX_BUILD_ROOT}/artifacts" \
  "${CIX_BUILD_ROOT}/keys" \
  "${CIX_BUILD_ROOT}/src" \
  "${CIX_BUILD_ROOT}/upstream"

printf 'workspace ready: %s\n' "${CIX_BUILD_ROOT}"
