#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import pathlib
import re
import sys


def remove_flavours(text: str, names: set[str]) -> str:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    index = 0

    while index < len(lines):
        if lines[index].strip() != "[[flavour]]":
            output.append(lines[index])
            index += 1
            continue

        block = [lines[index]]
        index += 1
        while index < len(lines):
            stripped = lines[index].strip()
            starts_new_table = (
                stripped.startswith("[")
                and not stripped.startswith("[flavour.")
            )
            if starts_new_table:
                break
            block.append(lines[index])
            index += 1

        block_text = "".join(block)
        match = re.search(
            r"^name\s*=\s*['\"]([^'\"]+)['\"]",
            block_text,
            re.MULTILINE,
        )
        if not match or match.group(1) not in names:
            output.extend(block)

    return "".join(output)


def main(source_tree: pathlib.Path) -> None:
    arm64 = source_tree / "debian/config/arm64/defines.toml"
    global_defines = source_tree / "debian/config/defines.toml"

    arm64_text = remove_flavours(
        arm64.read_text(),
        {"cloud-arm64", "arm64-16k", "rt-arm64", "test"},
    )
    arm64_text = re.sub(
        r"^enable_signed\s*=\s*true\s*$",
        "enable_signed = false",
        arm64_text,
        flags=re.MULTILINE,
    )
    arm64.write_text(arm64_text)

    global_text = global_defines.read_text()
    release_pattern = re.compile(
        r"(\[\[debianrelease\]\]\n"
        r"name_regex\s*=\s*'trixie-backports'\n)"
        r"(.*?)(?=^\[\[debianrelease\]\]|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = release_pattern.search(global_text)
    if not match:
        raise SystemExit("trixie-backports release block not found")

    block = match.group(0)
    block = re.sub(
        r"^abi_suffix\s*=.*$",
        "abi_suffix = '+deb13o6n'",
        block,
        flags=re.MULTILINE,
    )
    block = re.sub(
        r"^revision_regex\s*=.*$",
        r"revision_regex = '\\d+(\\.\\d+)?(\\+deb14u\\d+)?~bpo13\\+\\d+\\+o6n\\d+'",
        block,
        flags=re.MULTILINE,
    )
    global_defines.write_text(
        global_text[: match.start()] + block + global_text[match.end() :]
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} SOURCE_TREE")
    main(pathlib.Path(sys.argv[1]))
