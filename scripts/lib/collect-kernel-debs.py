#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import io
import lzma
import pathlib
import shutil
import subprocess
import sys
import tarfile


def control_fields(deb: pathlib.Path) -> dict[str, str]:
    raw = subprocess.check_output(["ar", "p", str(deb), "control.tar.xz"])
    archive = tarfile.open(fileobj=io.BytesIO(lzma.decompress(raw)))
    text = archive.extractfile("./control").read().decode()
    fields: dict[str, str] = {}
    key = ""
    for line in text.splitlines():
        if line.startswith(" ") and key:
            fields[key] += " " + line.strip()
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key] = value.strip()
    return fields


def main(root: pathlib.Path) -> None:
    artifacts = root / "artifacts/kernel"
    debs = sorted(artifacts.glob("*.deb"))
    if not debs:
        raise SystemExit(f"no kernel debs in {artifacts}")
    lines: list[str] = []
    for deb in debs:
        shutil.copy2(deb, root.parent / deb.name)
        fields = control_fields(deb)
        section = fields.get("Section", "kernel")
        priority = fields.get("Priority", "optional")
        lines.append(f"{deb.name} {section} {priority}")
    (root / "debian/files").write_text("".join(f"{line}\n" for line in lines))
    print(f"collected {len(debs)} kernel debs")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} PROJECT_ROOT")
    main(pathlib.Path(sys.argv[1]))
