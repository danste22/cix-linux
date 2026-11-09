#!/usr/bin/env python3
"""Balance an asymmetric CIX patch hunk for GNU patch compatibility."""

from pathlib import Path
import sys


EXPECTED_HEADER = (
    "@@ -4263,14 +4263,114 @@ "
    "static void alc287_fixup_lenovo_yoga_book_9i(struct hda_codec *codec,\n"
)
REWRITTEN_HEADER = (
    "@@ -4273,4 +4280,104 @@ "
    "static void alc287_fixup_lenovo_yoga_book_9i(struct hda_codec *codec,\n"
)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} PATCH")

    path = Path(sys.argv[1])
    lines = path.read_text().splitlines(keepends=True)

    matches = [index for index, line in enumerate(lines) if line == EXPECTED_HEADER]
    if len(matches) != 1:
        raise SystemExit(
            f"{path}: expected exactly one known asymmetric hunk, found {len(matches)}"
        )

    start = matches[0]
    try:
        end = next(
            index
            for index in range(start + 1, len(lines))
            if lines[index].startswith("@@ ")
            or lines[index].startswith("diff --git ")
        )
    except StopIteration as error:
        raise SystemExit(f"{path}: could not find the end of the known hunk") from error

    body = lines[start + 1 : end]
    first_add = next(
        (index for index, line in enumerate(body) if line.startswith("+")), None
    )
    last_add = next(
        (
            index
            for index in range(len(body) - 1, -1, -1)
            if body[index].startswith("+")
        ),
        None,
    )
    if first_add is None or last_add is None:
        raise SystemExit(f"{path}: known hunk contains no additions")

    prefix = body[:first_add]
    additions = body[first_add : last_add + 1]
    suffix = body[last_add + 1 :]
    if (len(prefix), len(additions), len(suffix)) != (12, 100, 2):
        raise SystemExit(
            f"{path}: unexpected known hunk shape: "
            f"{len(prefix)}/{len(additions)}/{len(suffix)}"
        )
    if not all(line.startswith(" ") for line in (*prefix, *suffix)):
        raise SystemExit(f"{path}: known hunk context is not insertion-only")

    lines[start:end] = [
        REWRITTEN_HEADER,
        *prefix[-2:],
        *additions,
        *suffix,
    ]
    path.write_text("".join(lines))


if __name__ == "__main__":
    main()
