#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

GNUPGHOME="${GNUPGHOME:-/workspace/keys}"
[[ -d "${GNUPGHOME}" ]] || die "set GNUPGHOME to the development key directory"

# gpg-agent creates a Unix socket in its home. Docker Desktop cannot serve
# that socket from a macOS bind mount, so sign from a container-local copy.
sign_home="$(mktemp -d /tmp/o6n-gpg.XXXXXX)"
chmod 700 "${sign_home}"
cp -a "${GNUPGHOME}/." "${sign_home}/"
find "${sign_home}" -type s -delete
printf 'allow-loopback-pinentry\n' > "${sign_home}/gpg-agent.conf"
chmod 600 "${sign_home}/gpg-agent.conf"

if [[ -z "${LOCAL_REPO_GPG_KEY_ID:-}" ]]; then
  mapfile -t primary_fprs < <(
    gpg --batch --homedir "${sign_home}" --list-secret-keys --with-colons \
      | awk -F: '
          $1 == "sec" || $1 == "sec#" { want = 1; next }
          $1 == "fpr" && want { print $10; want = 0; next }
          { want = 0 }
        '
  )
  [[ "${#primary_fprs[@]}" -eq 1 ]] \
    || die "set LOCAL_REPO_GPG_KEY_ID; found ${#primary_fprs[@]} secret keys"
  LOCAL_REPO_GPG_KEY_ID="${primary_fprs[0]}"
fi

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
  gpg --batch --yes --pinentry-mode loopback --passphrase '' \
      --homedir "${sign_home}" --local-user "${LOCAL_REPO_GPG_KEY_ID}" \
      --armor --detach-sign --output Release.gpg Release
  gpg --batch --yes --pinentry-mode loopback --passphrase '' \
      --homedir "${sign_home}" --local-user "${LOCAL_REPO_GPG_KEY_ID}" \
      --armor --clearsign --output InRelease Release
  gpg --batch --yes --homedir "${sign_home}" \
      --export --armor "${LOCAL_REPO_GPG_KEY_ID}" \
      > o6n-local-repo.asc
)
rm -rf "${sign_home}"

printf 'signed local apt repository: %s\n' "${repo_dir}"
