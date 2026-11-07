#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

: "${LOCAL_REPO_GPG_KEY_ID:?set LOCAL_REPO_GPG_KEY_ID to the development key}"

repo_dir="${ARTIFACTS_DIR}/repo"
pool_dir="${repo_dir}/pool"
rm -rf "${repo_dir}"
mkdir -p "${pool_dir}"

find "${ARTIFACTS_DIR}" -type f -name '*.deb' \
  ! -path "${repo_dir}/*" -exec cp -v {} "${pool_dir}/" \;

(
  cd "${repo_dir}"
  dpkg-scanpackages --multiversion pool /dev/null > Packages
  gzip -9 --keep Packages
  apt-ftparchive release . > Release
  gpg --batch --yes --local-user "${LOCAL_REPO_GPG_KEY_ID}" \
      --armor --detach-sign --output Release.gpg Release
  gpg --batch --yes --local-user "${LOCAL_REPO_GPG_KEY_ID}" \
      --armor --clearsign --output InRelease Release
  gpg --batch --yes --export --armor "${LOCAL_REPO_GPG_KEY_ID}" \
      > o6n-local-repo.asc
)

printf 'signed local apt repository: %s\n' "${repo_dir}"
