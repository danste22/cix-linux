#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Print the public OBS status of linux-cix."""

from __future__ import annotations

import argparse
import json
import pathlib
import urllib.request
import xml.etree.ElementTree as ET

STATUS_URL = (
    "https://build.opensuse.org/public/build/"
    "home:danste22:o6n-debian-13/backports/aarch64/linux-cix/_status"
)


def status(url: str = STATUS_URL) -> tuple[str, str]:
    with urllib.request.urlopen(url, timeout=60) as response:
        document = ET.fromstring(response.read())
    details = document.findtext("details") or ""
    code = document.attrib.get("code", "")
    if not code:
        raise SystemExit("OBS status has no code")
    return code, details.strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--json-output", type=pathlib.Path)
    args = parser.parse_args()
    code, details = status()
    if args.output is not None:
        with args.output.open("a", encoding="utf-8") as handle:
            handle.write(f"code={code}\n")
    if args.json_output is not None:
        args.json_output.write_text(json.dumps({"code": code, "details": details}))
    print(f"code={code}")


if __name__ == "__main__":
    main()
