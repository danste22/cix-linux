#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mapfile -t shell_files < <(
  find "${PROJECT_ROOT}/scripts" \
       "${PROJECT_ROOT}/packaging" \
       -type f \( -name '*.sh' -o -name 'postinst' -o -name 'postrm' \
                       -o -name 'cix-o6n-firmware-fetch' \) -print
)
for file in "${shell_files[@]}"; do
  bash -n "${file}"
done

python3 - "${PROJECT_ROOT}" <<'PY'
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in root.rglob("*.py"):
    ast.parse(path.read_text(), filename=str(path))

manifest = root / "firmware/manifest.txt"
entries = [
    line for line in manifest.read_text().splitlines()
    if line and not line.startswith("#")
]
if len(entries) != 17:
    raise SystemExit(f"expected 17 firmware entries, got {len(entries)}")
for line in entries:
    path, digest, url = line.split("|")
    if "/" in path or len(digest) != 64 or not url.startswith("https://"):
        raise SystemExit(f"invalid manifest entry: {line}")
PY

if find "${PROJECT_ROOT}" -type f \
     \( -name '*.fwb' -o -name 'dsp_fw.bin' -o -name 'mali_csffw.bin' \) \
     -print -quit | grep -q .; then
  printf 'firmware bytes must not be committed\n' >&2
  exit 1
fi

fingerprint="$(
  gpg --show-keys --with-colons \
    "${PROJECT_ROOT}/packaging/cix-o6n-repo/o6n-debian-13.asc" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }'
)"
[[ "${fingerprint}" == '153DA5670563C43055B82A208F66A7C1646CC2EA' ]] \
  || { printf 'unexpected OBS key fingerprint: %s\n' "${fingerprint}" >&2; exit 1; }

if command -v docker >/dev/null 2>&1; then
  docker compose --env-file "${PROJECT_ROOT}/refs.env" \
    -f "${PROJECT_ROOT}/compose.yaml" config --quiet
fi

printf 'Gate 2 scaffold validation passed\n'
