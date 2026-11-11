#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare the pinned CIX firmware commit with cix_p1_k6.6_master."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import urllib.request

BRANCH = "cix_p1_k6.6_master"
REPO = "cixtech/cix_proprietary__cix_proprietary"
COMMIT_URL = f"https://api.github.com/repos/{REPO}/commits/{BRANCH}"
PIN_RE = re.compile(r"^CIX_FIRMWARE_COMMIT='([0-9a-f]{40})'$", re.MULTILINE)


def read_pin(text: str) -> str:
    match = PIN_RE.search(text)
    if match is None:
        raise SystemExit("refs.env lacks CIX_FIRMWARE_COMMIT")
    return match.group(1)


def read_manifest(text: str) -> list[tuple[str, str, str]]:
    entries = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        name, digest, url = line.split("|")
        if "/" in name or len(digest) != 64 or not url.startswith("https://"):
            raise SystemExit(f"invalid manifest entry: {line}")
        entries.append((name, digest, url))
    if len(entries) != 17:
        raise SystemExit(f"expected 17 firmware entries, got {len(entries)}")
    return entries


def require_pin(entries: list[tuple[str, str, str]], pin: str) -> None:
    needle = f"/{pin}/"
    for name, _digest, url in entries:
        if needle not in url:
            raise SystemExit(f"{name} is not pinned to {pin}")


def url_at(url: str, pin: str, commit: str) -> str:
    needle = f"/{pin}/"
    if needle not in url:
        raise SystemExit(f"URL lacks pinned commit: {url}")
    return url.replace(needle, f"/{commit}/", 1)


def classify(pin: str, head: str, changed: list[dict[str, str]]) -> str:
    if pin == head:
        return "current"
    if changed:
        return "firmware-changed"
    return "branch-moved"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "cix-linux-firmware-watch",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def branch_head() -> str:
    payload = json.loads(fetch(COMMIT_URL))
    sha = payload.get("sha", "")
    if len(sha) != 40:
        raise SystemExit("firmware branch head is not a commit")
    return sha


def changed_files(
    entries: list[tuple[str, str, str]], pin: str, head: str
) -> list[dict[str, str]]:
    changed = []
    for name, digest, url in entries:
        payload = fetch(url_at(url, pin, head))
        actual = hashlib.sha256(payload).hexdigest()
        if actual != digest:
            changed.append(
                {
                    "name": name,
                    "pinned_sha256": digest,
                    "head_sha256": actual,
                }
            )
    return changed


def report(refs: pathlib.Path, manifest: pathlib.Path) -> dict[str, object]:
    pin = read_pin(refs.read_text())
    entries = read_manifest(manifest.read_text())
    require_pin(entries, pin)
    head = branch_head()
    changed = [] if head == pin else changed_files(entries, pin, head)
    return {
        "state": classify(pin, head, changed),
        "pinned": pin,
        "head": head,
        "changed_files": changed,
    }


def self_test() -> None:
    pin = "6260fd1a596a6135a198f0f220e6ed70f3210532"
    head = "a" * 40
    url = (
        "https://raw.githubusercontent.com/cixtech/cix_proprietary__cix_proprietary/"
        f"{pin}/cix_proprietary-debs/cix-vpu-umd/usr/lib/firmware/av1dec.fwb"
    )
    assert url_at(url, pin, head).endswith(f"/{head}/cix_proprietary-debs/cix-vpu-umd/usr/lib/firmware/av1dec.fwb")
    assert classify(pin, pin, []) == "current"
    assert classify(pin, head, []) == "branch-moved"
    assert classify(pin, head, [{"name": "av1dec.fwb"}]) == "firmware-changed"
    text = "\n".join(
        f"file{index}.fwb|{'ab' * 32}|https://example.invalid/{pin}/file{index}.fwb"
        for index in range(16)
    )
    text = f"dsp_fw.bin|{'cd' * 32}|https://example.invalid/{pin}/dsp_fw.bin\n" + text
    entries = read_manifest(text)
    require_pin(entries, pin)
    try:
        require_pin(entries, "b" * 40)
    except SystemExit:
        return
    raise SystemExit("manifest pin check did not fail")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--refs", type=pathlib.Path)
    parser.add_argument("--manifest", type=pathlib.Path)
    parser.add_argument("--json-output", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("self-test passed")
        return
    if args.refs is None or args.manifest is None:
        raise SystemExit("--refs and --manifest are required")
    result = report(args.refs, args.manifest)
    encoded = json.dumps(result, indent=2) + "\n"
    if args.json_output is not None:
        args.json_output.write_text(encoded)
    print(f"state={result['state']}")
    print(f"pinned={result['pinned']}")
    print(f"head={result['head']}")


if __name__ == "__main__":
    main()
