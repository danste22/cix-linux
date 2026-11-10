#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect one accepted linux-cix version from the public OBS repository."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request

REPO_URL = (
    "https://download.opensuse.org/repositories/"
    "home:/danste22:/o6n-debian-13/backports/"
)
LOG_URL = (
    "https://build.opensuse.org/public/build/"
    "home:danste22:o6n-debian-13/backports/aarch64/linux-cix/_log?nostream=1"
)
KEY_FINGERPRINT = "153DA5670563C43055B82A208F66A7C1646CC2EA"
VERSION_RE = re.compile(r"^[0-9][A-Za-z0-9.+:~-]*\+o6n[0-9]+$")
PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
KEY_PATH = PROJECT_ROOT / "packaging/cix-o6n-repo/o6n-debian-13.asc"
MANIFEST_PATH = PROJECT_ROOT / "firmware/manifest.txt"


def firmware_names() -> set[str]:
    names = {"mali_csffw.bin"}
    for line in MANIFEST_PATH.read_text().splitlines():
        if line and not line.startswith("#"):
            names.add(line.split("|", 1)[0])
    return names


def contains_firmware(path: str, names: set[str]) -> bool:
    base = path.rstrip("/").rsplit("/", 1)[-1]
    return base in names or base.endswith(".fwb")


def parse_fields(text: str) -> list[dict[str, object]]:
    records = []
    for block in text.split("\n\n"):
        if ":" not in block:
            continue
        fields: dict[str, object] = {}
        current = ""
        for line in block.splitlines():
            if line.startswith((" ", "\t")):
                existing = fields.get(current, [])
                if not isinstance(existing, list):
                    existing = [existing] if existing else []
                existing.append(line.strip())
                fields[current] = existing
                continue
            key, _, value = line.partition(":")
            current = key
            fields[key] = value.strip()
        records.append(fields)
    return records


def release_hashes(text: str) -> dict[str, str]:
    hashes = {}
    in_sha256 = False
    for line in text.splitlines():
        if line.startswith("SHA256:"):
            in_sha256 = True
            continue
        if in_sha256 and line and not line.startswith(" "):
            break
        if in_sha256:
            digest, _size, name = line.split()
            hashes[name] = digest
    return hashes


def source_files(records: list[dict[str, object]], version: str) -> list[tuple[str, str, int]]:
    selected = [
        record
        for record in records
        if record.get("Package") == "linux-cix" and record.get("Version") == version
    ]
    if len(selected) != 1:
        raise SystemExit(f"signed Sources index has {len(selected)} linux-cix {version}")
    files = []
    for line in selected[0].get("Checksums-Sha256", []):
        if not isinstance(line, str):
            continue
        digest, size, name = line.split()
        files.append((name, digest, int(size)))
    wanted = {
        f"linux-cix_{version}.dsc",
        f"linux-cix_{version}.debian.tar.xz",
    }
    orig = [item for item in files if item[0].endswith((".orig.tar.gz", ".orig.tar.xz"))]
    if len(orig) != 1 or any(name not in {item[0] for item in files} for name in wanted):
        raise SystemExit(f"linux-cix {version} source file list is incomplete")
    return [item for item in files if item[0] in wanted or item in orig]


def binary_files(records: list[dict[str, object]], version: str) -> list[tuple[str, str, int]]:
    files = []
    for record in records:
        if record.get("Version") != version:
            continue
        filename = str(record.get("Filename", ""))
        digest = str(record.get("SHA256", ""))
        size = str(record.get("Size", ""))
        if "/" not in filename or filename.startswith("/") or ".." in filename.split("/"):
            raise SystemExit(f"unexpected package filename: {filename}")
        if not filename.endswith(".deb") or len(digest) != 64 or not size.isdigit():
            raise SystemExit(f"incomplete package record for {filename}")
        files.append((filename, digest, int(size)))
    names = {path.rsplit("/", 1)[-1] for path, _digest, _size in files}
    if not any(name.startswith("linux-image-o6n-arm64_") for name in names):
        raise SystemExit(f"repository has no linux-image-o6n-arm64 {version}")
    if not any(name.startswith("linux-headers-o6n-arm64_") for name in names):
        raise SystemExit(f"repository has no linux-headers-o6n-arm64 {version}")
    return files


def download(url: str, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=180) as response:
        with destination.open("wb") as handle:
            shutil.copyfileobj(response, handle)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_release(directory: pathlib.Path) -> dict[str, str]:
    key_text = KEY_PATH.read_text()
    if KEY_FINGERPRINT not in key_text.replace(" ", ""):
        shown = subprocess.run(
            ["gpg", "--show-keys", "--with-colons", str(KEY_PATH)],
            check=False,
            capture_output=True,
            text=True,
        )
        fingerprint = next(
            (
                line.split(":")[9]
                for line in shown.stdout.splitlines()
                if line.startswith("fpr:")
            ),
            "",
        )
        if fingerprint != KEY_FINGERPRINT:
            raise SystemExit(f"unexpected OBS key fingerprint: {fingerprint}")
    dearmored = directory / "obs-key.gpg"
    subprocess.run(
        ["gpg", "--batch", "--dearmor", "--output", str(dearmored), str(KEY_PATH)],
        check=True,
        capture_output=True,
    )
    verified = subprocess.run(
        [
            "gpgv",
            "--keyring",
            str(dearmored),
            str(directory / "Release.gpg"),
            str(directory / "Release"),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if verified.returncode != 0 or KEY_FINGERPRINT not in verified.stderr.replace(" ", ""):
        sys.stderr.write(verified.stderr)
        raise SystemExit("OBS Release signature check failed")
    dearmored.unlink()
    return release_hashes((directory / "Release").read_text())


def scan_tar(path: pathlib.Path, names: set[str], depth: int = 0) -> list[str]:
    hits = []
    mode = "r|xz" if path.name.endswith(".xz") else "r|gz"
    with tarfile.open(path, mode) as archive:
        for member in archive:
            if not member.isfile():
                continue
            if contains_firmware(member.name, names):
                hits.append(member.name)
                continue
            if depth >= 2:
                continue
            nested = member.name.endswith((".tar.gz", ".tgz", ".tar.xz", ".deb"))
            if not nested:
                continue
            extracted = archive.extractfile(member)
            if extracted is None:
                continue
            with tempfile.NamedTemporaryFile(suffix=pathlib.Path(member.name).suffix) as temporary:
                shutil.copyfileobj(extracted, temporary)
                temporary.flush()
                nested_path = pathlib.Path(temporary.name)
                if member.name.endswith(".deb"):
                    hits.extend(
                        f"{member.name}!{hit}"
                        for hit in scan_deb(nested_path, names)
                    )
                else:
                    hits.extend(
                        f"{member.name}!{hit}"
                        for hit in scan_tar(nested_path, names, depth + 1)
                    )
    return hits


def scan_deb(path: pathlib.Path, names: set[str]) -> list[str]:
    data = path.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise SystemExit(f"{path.name} is not a deb")
    offset = 8
    payload = None
    payload_name = ""
    while offset + 60 <= len(data):
        header = data[offset : offset + 60]
        name = header[0:16].decode().strip()
        size = int(header[48:58].decode().strip() or "0")
        offset += 60
        chunk = data[offset : offset + size]
        offset += size + (size % 2)
        if name.startswith("data.tar"):
            payload = chunk
            payload_name = name
    if payload is None:
        raise SystemExit(f"{path.name} has no data.tar")
    suffix = "".join(pathlib.Path(payload_name).suffixes)
    with tempfile.NamedTemporaryFile(suffix=suffix or ".tar") as temporary:
        temporary.write(payload)
        temporary.flush()
        nested = pathlib.Path(temporary.name)
        if payload_name.endswith((".gz", ".xz")):
            return scan_tar(nested, names, depth=2)
        if payload_name.endswith(".tar"):
            with tarfile.open(nested, "r|") as archive:
                return [
                    member.name
                    for member in archive
                    if member.isfile() and contains_firmware(member.name, names)
                ]
    raise SystemExit(f"{path.name} uses {payload_name}, which this archive cannot prove clean")


def collect(version: str, output: pathlib.Path) -> None:
    if VERSION_RE.fullmatch(version) is None:
        raise SystemExit(f"not an O6N package version: {version}")
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    download(REPO_URL + "Release", output / "Release")
    download(REPO_URL + "Release.gpg", output / "Release.gpg")
    hashes = verify_release(output)
    for name in ("Packages", "Sources"):
        download(REPO_URL + name, output / name)
        digest = sha256(output / name)
        if hashes.get(name) != digest:
            raise SystemExit(f"{name} does not match the signed Release")
    packages = binary_files(parse_fields((output / "Packages").read_text()), version)
    sources = source_files(parse_fields((output / "Sources").read_text()), version)
    kept: list[pathlib.Path] = []
    withheld: list[str] = []
    names = firmware_names()
    for filename, digest, size in packages:
        destination = output / pathlib.Path(filename).name
        download(REPO_URL + filename, destination)
        if destination.stat().st_size != size or sha256(destination) != digest:
            raise SystemExit(f"checksum mismatch for {filename}")
        hits = scan_deb(destination, names)
        if hits:
            raise SystemExit(f"{destination.name} contains firmware: {hits[0]}")
        kept.append(destination)
    for filename, digest, size in sources:
        destination = output / filename
        download(REPO_URL + filename, destination)
        if destination.stat().st_size != size or sha256(destination) != digest:
            raise SystemExit(f"checksum mismatch for {filename}")
        hits = []
        if filename.endswith((".tar.gz", ".tar.xz")):
            hits = scan_tar(destination, names)
        if hits:
            withheld.append(
                f"{filename} sha256:{digest} reason: contains firmware ({hits[0]})"
            )
            destination.unlink()
            continue
        kept.append(destination)
    log_path = output / f"linux-cix_{version}.buildlog"
    download(LOG_URL, log_path)
    log_text = log_path.read_text(errors="replace")
    if f"linux-cix_{version}.dsc" not in log_text:
        raise SystemExit("build log does not name this package version")
    kept.append(log_path)
    for leftover in ("Release", "Release.gpg", "Packages", "Sources"):
        (output / leftover).unlink()
    sums = output / "SHA256SUMS"
    lines = [f"{sha256(path)}  {path.name}" for path in sorted(kept, key=lambda item: item.name)]
    sums.write_text("\n".join(lines) + "\n")
    notes = [
        f"linux-cix {version}",
        "",
        "These files are the accepted OBS build of this version.",
        "OBS remains the apt repository. This release is the rollback copy.",
        "",
        "SHA256SUMS covers the files in this release.",
    ]
    if withheld:
        notes.extend(["", "Withheld because the file contains firmware bytes:"])
        notes.extend(withheld)
    else:
        notes.extend(["", "Every downloaded source file is included."])
    (output / "RELEASE.txt").write_text("\n".join(notes) + "\n")


def tag_name(version: str) -> str:
    if VERSION_RE.fullmatch(version) is None:
        raise SystemExit(f"not an O6N package version: {version}")
    # Git rejects '~' in a ref. Debian maps that character to '_'.
    return f"o6n-{version.replace('~', '_')}"


def github_request(method: str, url: str, token: str, payload: dict | None = None, data: bytes | None = None, content_type: str | None = None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
    }
    body = data
    if payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    if content_type is not None:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        if exc.code == 404:
            return exc.code, {}
        raise SystemExit(f"GitHub {method} {url} failed: {exc.code} {detail}") from exc


def publish(directory: pathlib.Path, version: str, repository: str, token: str) -> None:
    tag = tag_name(version)
    encoded = urllib.parse.quote(tag, safe="")
    status, _existing = github_request(
        "GET",
        f"https://api.github.com/repos/{repository}/releases/tags/{encoded}",
        token,
    )
    if status != 404:
        raise SystemExit(f"release {tag} already exists")
    ref_status, _ref = github_request(
        "GET",
        f"https://api.github.com/repos/{repository}/git/ref/tags/{encoded}",
        token,
    )
    if ref_status != 404:
        raise SystemExit(f"tag {tag} already exists")
    status, release = github_request(
        "POST",
        f"https://api.github.com/repos/{repository}/releases",
        token,
        {
            "tag_name": tag,
            "target_commitish": "main",
            "name": f"linux-cix {version}",
            "body": (directory / "RELEASE.txt").read_text(),
            "draft": True,
        },
    )
    release_id = release["id"]
    try:
        for path in sorted(directory.iterdir()):
            if not path.is_file():
                continue
            name = urllib.parse.quote(path.name)
            github_request(
                "POST",
                "https://uploads.github.com/repos/"
                f"{repository}/releases/{release_id}/assets?name={name}",
                token,
                data=path.read_bytes(),
                content_type="application/octet-stream",
            )
        github_request(
            "PATCH",
            f"https://api.github.com/repos/{repository}/releases/{release_id}",
            token,
            {"draft": False},
        )
    except BaseException:
        for url in (
            f"https://api.github.com/repos/{repository}/releases/{release_id}",
            f"https://api.github.com/repos/{repository}/git/refs/tags/{encoded}",
        ):
            try:
                github_request("DELETE", url, token)
            except SystemExit:
                pass
        raise


def self_test() -> None:
    assert VERSION_RE.fullmatch("7.2.12-1~bpo13+1+o6n1")
    assert VERSION_RE.fullmatch("../etc") is None
    assert tag_name("7.2.12-1~bpo13+1+o6n1") == "o6n-7.2.12-1_bpo13+1+o6n1"
    assert "~" not in tag_name("7.2.12-1~bpo13+1+o6n1")
    names = {"av1dec.fwb"}
    assert contains_firmware("firmware-binaries/av1dec.fwb", names)
    assert not contains_firmware("driver/if/mvx_firmware.c", names)
    packages = binary_files(
        parse_fields(
            "Package: linux-image-o6n-arm64\n"
            "Version: 7.2.12-1~bpo13+1+o6n1\n"
            "Filename: arm64/linux-image-o6n-arm64_7.2.12-1~bpo13+1+o6n1_arm64.deb\n"
            "Size: 10\n"
            "SHA256: " + "a" * 64 + "\n\n"
            "Package: linux-headers-o6n-arm64\n"
            "Version: 7.2.12-1~bpo13+1+o6n1\n"
            "Filename: arm64/linux-headers-o6n-arm64_7.2.12-1~bpo13+1+o6n1_arm64.deb\n"
            "Size: 11\n"
            "SHA256: " + "b" * 64 + "\n\n"
            "Package: cix-npu-driver-dkms\n"
            "Version: 6.2.0-1o6n1\n"
            "Filename: all/cix-npu-driver-dkms_6.2.0-1o6n1_all.deb\n"
            "Size: 12\n"
            "SHA256: " + "c" * 64 + "\n"
        ),
        "7.2.12-1~bpo13+1+o6n1",
    )
    assert len(packages) == 2
    sources = source_files(
        parse_fields(
            "Package: linux-cix\n"
            "Version: 7.2.12-1~bpo13+1+o6n1\n"
            "Checksums-Sha256:\n"
            " aaa 1 linux-cix_7.2.12-1~bpo13+1+o6n1.dsc\n"
            " bbb 2 linux-cix_7.2.12.orig.tar.gz\n"
            " ccc 3 linux-cix_7.2.12-1~bpo13+1+o6n1.debian.tar.xz\n"
        ),
        "7.2.12-1~bpo13+1+o6n1",
    )
    assert [item[0] for item in sources] == [
        "linux-cix_7.2.12-1~bpo13+1+o6n1.dsc",
        "linux-cix_7.2.12.orig.tar.gz",
        "linux-cix_7.2.12-1~bpo13+1+o6n1.debian.tar.xz",
    ]
    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        inner = root / "inner.tar.gz"
        with tarfile.open(inner, "w:gz") as archive:
            payload = root / "av1dec.fwb"
            payload.write_bytes(b"firmware")
            archive.add(payload, arcname="firmware-binaries/av1dec.fwb")
        outer = root / "outer.tar.gz"
        with tarfile.open(outer, "w:gz") as archive:
            archive.add(inner, arcname="upstream/cix-vpu-driver.tar.gz")
        hits = scan_tar(outer, names)
        assert hits and hits[0].endswith("av1dec.fwb")
        clean = root / "clean.tar.gz"
        with tarfile.open(clean, "w:gz") as archive:
            readme = root / "README"
            readme.write_text("source\n")
            archive.add(readme, arcname="README")
        assert scan_tar(clean, names) == []
        member = root / "data.tar.gz"
        with tarfile.open(member, "w:gz") as archive:
            blob = root / "blob.fwb"
            blob.write_bytes(b"firmware")
            archive.add(blob, arcname="usr/lib/firmware/av1dec.fwb")
        member_bytes = member.read_bytes()
        header = (
            b"data.tar.gz".ljust(16)
            + b"0".ljust(12)
            + b"0".ljust(6)
            + b"0".ljust(6)
            + b"644".ljust(8)
            + str(len(member_bytes)).encode().ljust(10)
            + b"`\n"
        )
        deb = root / "package.deb"
        deb.write_bytes(b"!<arch>\n" + header + member_bytes)
        assert scan_deb(deb, names)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version")
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("self-test passed")
        return
    if args.version is None or args.output is None:
        raise SystemExit("--version and --output are required")
    collect(args.version, args.output)
    print((args.output / "RELEASE.txt").read_text())
    if args.publish:
        publish(
            args.output,
            args.version,
            os.environ["REPOSITORY"],
            os.environ["GH_TOKEN"],
        )


if __name__ == "__main__":
    main()
