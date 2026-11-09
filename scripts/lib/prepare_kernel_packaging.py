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


def install_o6n_templates(source_tree: pathlib.Path) -> None:
    overlay = pathlib.Path(__file__).resolve().parents[2] / "overlay/debian/templates"
    destination = source_tree / "debian/templates"
    for template in sorted(overlay.glob("o6n-*.control.j2")):
        destination.joinpath(template.name).write_text(template.read_text())


def install_o6n_metapackages(source_tree: pathlib.Path) -> None:
    gencontrol = source_tree / "debian/bin/gencontrol.py"
    text = gencontrol.read_text()
    marker = "bundle.add('o6n-image.meta'"
    if marker in text:
        return
    needle = """        if do_meta:
            packages_own.extend(bundle_signed.add('base.meta', ruleid, makeflags, vars, arch=arch))
            packages_own.extend(bundle_signed.add('image.meta', ruleid, makeflags, vars, arch=arch))
            packages_own.extend(
                bundle_signed.add('headers.meta', ruleid, makeflags, vars, arch=arch))
            packages_own.extend(
                bundle_signed.add('image-dbg.meta', ruleid, makeflags, vars, arch=arch))
"""
    insert = needle + """
        else:
            packages_own.extend(
                self.bundle.add('o6n-image.meta', ruleid, makeflags, vars, arch=arch))
            packages_own.extend(
                self.bundle.add('o6n-headers.meta', ruleid, makeflags, vars, arch=arch))
"""
    if needle not in text:
        raise SystemExit("kernel gencontrol meta hook not found")
    gencontrol.write_text(text.replace(needle, insert, 1))


def disable_debug_package(source_tree: pathlib.Path) -> None:
    control = source_tree / "debian/templates/image-dbg.control.in"
    text = control.read_text()
    old = "Build-Profiles: <!pkg.linux.nokernel !pkg.linux.nokerneldbg !pkg.linux.quick>"
    new = "Build-Profiles: <pkg.linux.quick>"
    if old not in text and new not in text:
        raise SystemExit("image-dbg build profile line not found")
    control.write_text(text.replace(old, new, 1))


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
    arm64_text = arm64_text.replace("is_default = true", "is_default = false", 1)
    arm64_text = arm64_text.replace("installer = true", "installer = false", 1)
    arm64.write_text(arm64_text)
    install_o6n_templates(source_tree)
    install_o6n_metapackages(source_tree)
    disable_debug_package(source_tree)

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
    global_text = (
        global_text[: match.start()] + block + global_text[match.end() :]
    )
    if "\n[packages]\n" not in global_text:
        global_text += (
            "\n[packages]\n"
            "docs = false\n"
            "libc_dev = false\n"
            "meta = false\n"
            "source = false\n"
            "tools_unversioned = false\n"
        )
    global_defines.write_text(global_text)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} SOURCE_TREE")
    main(pathlib.Path(sys.argv[1]))
