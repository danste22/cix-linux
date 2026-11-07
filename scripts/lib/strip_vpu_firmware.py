#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import pathlib
import re
import sys


def main(tree: pathlib.Path) -> None:
    control = tree / "debian/control"
    paragraphs = control.read_text().split("\n\n")
    output: list[str] = []

    for paragraph in paragraphs:
        if re.search(r"^Package:\s*cix-vpu-firmware\s*$", paragraph, re.MULTILINE):
            continue
        if re.search(r"^Package:\s*cix-vpu-driver-dkms\s*$", paragraph, re.MULTILINE):
            paragraph = re.sub(
                r"(?m)^ cix-vpu-firmware \(= \$\{binary:Version\}\),$",
                " cix-o6n-firmware-install,",
                paragraph,
            )
        output.append(paragraph)

    new_control = "\n\n".join(output).rstrip() + "\n"
    if "Package: cix-vpu-firmware" in new_control:
        raise SystemExit("failed to remove cix-vpu-firmware package")
    if " cix-o6n-firmware-install," not in new_control:
        raise SystemExit("failed to replace the VPU firmware dependency")
    control.write_text(new_control)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} VPU_TREE")
    main(pathlib.Path(sys.argv[1]))
