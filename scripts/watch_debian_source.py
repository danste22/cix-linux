#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare refs.env with the signed trixie-backports linux source package."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.request

ARCHIVE = "https://deb.debian.org/debian"
SUITE = "trixie-backports"
INRELEASE = f"{ARCHIVE}/dists/{SUITE}/InRelease"
SOURCES_PATH = "main/source/Sources.xz"
KEYRING = pathlib.Path("/usr/share/keyrings/debian-archive-keyring.gpg")

PIN_ORDER = (
    "DEBIAN_SOURCE_VERSION",
    "O6N_PACKAGE_VERSION",
    "DEBIAN_SOURCE_BASE_URL",
    "DEBIAN_DSC",
    "DEBIAN_DSC_SHA256",
    "DEBIAN_ORIG",
    "DEBIAN_ORIG_SHA256",
    "DEBIAN_TAR",
    "DEBIAN_TAR_SHA256",
)


def _order(char: str | None) -> int:
    if char is None:
        return 0
    if char == "~":
        return -1
    if char.isalpha():
        return ord(char)
    return ord(char) + 256


def _compare_nondigits(left: str, right: str) -> int:
    length = max(len(left), len(right))
    for index in range(length):
        left_order = _order(left[index] if index < len(left) else None)
        right_order = _order(right[index] if index < len(right) else None)
        if left_order != right_order:
            return -1 if left_order < right_order else 1
    return 0


def _compare_fragment(left: str, right: str) -> int:
    i = j = 0
    while i < len(left) or j < len(right):
        left_start, right_start = i, j
        while i < len(left) and not left[i].isdigit():
            i += 1
        while j < len(right) and not right[j].isdigit():
            j += 1
        text = _compare_nondigits(left[left_start:i], right[right_start:j])
        if text:
            return text
        left_start, right_start = i, j
        while i < len(left) and left[i].isdigit():
            i += 1
        while j < len(right) and right[j].isdigit():
            j += 1
        left_number = int(left[left_start:i] or "0")
        right_number = int(right[right_start:j] or "0")
        if left_number != right_number:
            return -1 if left_number < right_number else 1
    return 0


def compare_versions(left: str, right: str) -> int:
    def split(version: str) -> tuple[int, str, str]:
        epoch, separator, rest = version.partition(":")
        if separator == "":
            epoch, rest = "0", version
        upstream, separator, revision = rest.partition("-")
        if separator == "":
            revision = "0"
        return int(epoch), upstream, revision

    left_epoch, left_upstream, left_revision = split(left)
    right_epoch, right_upstream, right_revision = split(right)
    if left_epoch != right_epoch:
        return -1 if left_epoch < right_epoch else 1
    upstream = _compare_fragment(left_upstream, right_upstream)
    if upstream:
        return upstream
    return _compare_fragment(left_revision, right_revision)


def parse_sources(text: str) -> list[dict[str, str]]:
    records = []
    for block in text.split("\n\n"):
        if not block.startswith("Package: linux\n"):
            continue
        fields: dict[str, list[str]] = {}
        current = ""
        for line in block.splitlines():
            if line.startswith((" ", "\t")):
                fields[current].append(line.strip())
                continue
            key, _, value = line.partition(":")
            current = key
            fields[current] = [value.strip()] if value.strip() else []
        checksums = {}
        for line in fields.get("Checksums-Sha256", []):
            digest, _size, name = line.split()
            checksums[name] = digest
        version = fields["Version"][0]
        directory = fields["Directory"][0]

        def one(suffix: str) -> tuple[str, str]:
            matches = [name for name in checksums if name.endswith(suffix)]
            if len(matches) != 1:
                raise SystemExit(
                    f"linux {version} has {len(matches)} {suffix} files"
                )
            name = matches[0]
            return name, checksums[name]

        dsc_name, dsc_sha = one(".dsc")
        orig_name, orig_sha = one(".orig.tar.xz")
        tar_name, tar_sha = one(".debian.tar.xz")
        records.append(
            {
                "DEBIAN_SOURCE_VERSION": version,
                "O6N_PACKAGE_VERSION": f"{version}+o6n1",
                "DEBIAN_SOURCE_BASE_URL": f"{ARCHIVE}/{directory}",
                "DEBIAN_DSC": dsc_name,
                "DEBIAN_DSC_SHA256": dsc_sha,
                "DEBIAN_ORIG": orig_name,
                "DEBIAN_ORIG_SHA256": orig_sha,
                "DEBIAN_TAR": tar_name,
                "DEBIAN_TAR_SHA256": tar_sha,
            }
        )
    if not records:
        raise SystemExit("signed source index has no linux package")
    return records


def newest(records: list[dict[str, str]]) -> dict[str, str]:
    selected = records[0]
    for record in records[1:]:
        if (
            compare_versions(
                record["DEBIAN_SOURCE_VERSION"],
                selected["DEBIAN_SOURCE_VERSION"],
            )
            > 0
        ):
            selected = record
    return selected


def read_pins(text: str) -> dict[str, str]:
    pins = {}
    for key in PIN_ORDER:
        match = re.search(rf"^{key}='([^']*)'$", text, re.MULTILINE)
        if match is None:
            raise SystemExit(f"refs.env lacks {key}")
        pins[key] = match.group(1)
    return pins


def apply_pins(text: str, pins: dict[str, str]) -> str:
    for key in PIN_ORDER:
        text, count = re.subn(
            rf"^{key}='[^']*'$",
            f"{key}='{pins[key]}'",
            text,
            count=1,
            flags=re.MULTILINE,
        )
        if count != 1:
            raise SystemExit(f"refs.env lacks {key}")
    return text


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def signed_sources() -> str:
    if not KEYRING.is_file():
        raise SystemExit(f"Debian archive keyring is not at {KEYRING}")
    with tempfile.TemporaryDirectory() as temporary:
        inrelease = pathlib.Path(temporary) / "InRelease"
        inrelease.write_bytes(fetch(INRELEASE))
        verified = subprocess.run(
            ["gpgv", "--keyring", str(KEYRING), str(inrelease)],
            check=False,
            capture_output=True,
            text=True,
        )
        if verified.returncode != 0:
            sys.stderr.write(verified.stderr)
            raise SystemExit("trixie-backports InRelease signature check failed")
        digest = size = None
        for line in inrelease.read_text().splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[2] == SOURCES_PATH:
                digest, size = parts[0], int(parts[1])
        if digest is None or size is None:
            raise SystemExit(f"InRelease lacks {SOURCES_PATH}")
        payload = fetch(f"{ARCHIVE}/dists/{SUITE}/{SOURCES_PATH}")
        if len(payload) != size or hashlib.sha256(payload).hexdigest() != digest:
            raise SystemExit("Sources.xz does not match the signed InRelease")
        return subprocess.check_output(["xz", "-dc"], input=payload).decode()


def pins_differ(current: dict[str, str], published: dict[str, str]) -> bool:
    return any(current[key] != published[key] for key in PIN_ORDER)


def self_test() -> None:
    assert compare_versions("7.2.12-1~bpo13+1", "7.2.11-1~bpo13+1") > 0
    assert compare_versions("7.2.12-1~bpo13+1", "7.2.9-1~bpo13+1") > 0
    assert compare_versions("7.0.4-1~bpo13+1", "6.19.14-1~bpo13+1") > 0
    assert compare_versions("1~~", "1~") < 0
    assert compare_versions("1~", "1") < 0
    assert compare_versions("1a", "1+") < 0
    assert compare_versions("1.0-1~bpo13+1", "1.0-1") < 0
    assert compare_versions("1.0~bpo", "1.0") < 0
    older = (
        "Package: linux\n"
        "Version: 7.2.11-1~bpo13+1\n"
        "Checksums-Sha256:\n"
        " aaa 1 linux_7.2.11-1~bpo13+1.dsc\n"
        " bbb 2 linux_7.2.11.orig.tar.xz\n"
        " ccc 3 linux_7.2.11-1~bpo13+1.debian.tar.xz\n"
        "Directory: pool/main/l/linux\n"
    )
    newer = older.replace("7.2.11", "7.2.12")
    selected = newest(parse_sources(f"{older}\n{newer}"))
    assert selected["DEBIAN_SOURCE_VERSION"] == "7.2.12-1~bpo13+1"
    assert selected["O6N_PACKAGE_VERSION"] == "7.2.12-1~bpo13+1+o6n1"
    assert selected["DEBIAN_DSC_SHA256"] == "aaa"
    original = "DEBIAN_SOURCE_VERSION='old'\nCIX_KERNEL_REF='keep'\n"
    for key in PIN_ORDER[1:]:
        original += f"{key}='old'\n"
    updated = apply_pins(original, {key: f"new-{key}" for key in PIN_ORDER})
    assert "CIX_KERNEL_REF='keep'" in updated
    assert "DEBIAN_SOURCE_VERSION='new-DEBIAN_SOURCE_VERSION'" in updated
    assert read_pins(updated)["DEBIAN_TAR"] == "new-DEBIAN_TAR"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--refs", type=pathlib.Path)
    parser.add_argument("--sources-file", type=pathlib.Path)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("self-test passed")
        return
    if args.refs is None:
        raise SystemExit("--refs is required")
    text = args.refs.read_text()
    current = read_pins(text)
    if args.sources_file is not None:
        source_text = args.sources_file.read_text()
    else:
        source_text = signed_sources()
    published = newest(parse_sources(source_text))
    changed = pins_differ(current, published)
    version = published["DEBIAN_SOURCE_VERSION"]
    result = f"changed={'true' if changed else 'false'}\nversion={version}\n"
    if args.output is not None:
        with args.output.open("a", encoding="utf-8") as handle:
            handle.write(result)
    sys.stdout.write(result)
    if changed and args.write:
        args.refs.write_text(apply_pins(text, published))


if __name__ == "__main__":
    main()
