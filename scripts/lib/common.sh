#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/refs.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/refs.env"
fi

DOWNLOADS_DIR="${DOWNLOADS_DIR:-${PROJECT_ROOT}/downloads}"
SRC_DIR="${SRC_DIR:-${PROJECT_ROOT}/src}"
UPSTREAM_DIR="${UPSTREAM_DIR:-${PROJECT_ROOT}/upstream}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_file() {
  [[ -f "$1" ]] || die "required file not found: $1"
}

fetch_file() {
  local url="$1" destination="$2" sha256="$3"
  mkdir -p "$(dirname "${destination}")"
  if [[ -f "${destination}" ]] \
     && printf '%s  %s\n' "${sha256}" "${destination}" \
          | sha256sum --check --status -; then
    printf 'reusing verified file: %s\n' "${destination}"
    return
  fi
  curl --fail --location --retry 3 --output "${destination}.part" "${url}"
  printf '%s  %s\n' "${sha256}" "${destination}.part" | sha256sum --check -
  mv "${destination}.part" "${destination}"
}

checkout_commit() {
  local repository="$1" commit="$2" destination="$3"
  local stamp="${destination}/.o6n-commit"
  local archive="${destination}.tar.gz"
  if [[ -d "${destination}/.git" ]] \
     && [[ "$(git -C "${destination}" rev-parse HEAD 2>/dev/null)" == "${commit}" ]]; then
    printf 'reusing pinned checkout: %s @ %s\n' "${destination}" "${commit}"
    return
  fi
  if [[ -f "${stamp}" ]] && [[ "$(cat "${stamp}")" == "${commit}" ]]; then
    printf 'reusing pinned archive: %s @ %s\n' "${destination}" "${commit}"
    return
  fi
  if [[ -f "${archive}" ]]; then
    rm -rf "${destination}"
    mkdir -p "${destination}"
    bsdtar -C "${destination}" --strip-components=1 -xf "${archive}"
    printf '%s\n' "${commit}" > "${stamp}"
    printf 'unpacked pinned archive: %s\n' "${archive}"
    return
  fi
  rm -rf "${destination}"
  git init --quiet "${destination}"
  git -C "${destination}" remote add origin "${repository}"
  git -C "${destination}" fetch --quiet --depth 1 origin "${commit}"
  git -C "${destination}" checkout --quiet --detach FETCH_HEAD
  [[ "$(git -C "${destination}" rev-parse HEAD)" == "${commit}" ]] \
    || die "commit mismatch for ${repository}"
}
