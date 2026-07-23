#!/usr/bin/env python3
"""Lab Option D: skip seal_system_volume in iOS 16.4 restored_external.

Proven on iPhone12,3 (d421ap) 16.4 / 20E247 restore ramdisk:
  offset 0x37114  cbz w19, +0x5c (f3 02 00 34) → b +0x5c (17 00 00 14)

That forces the "Skipping sealing system volume" arm (allow-root-hash-mismatch)
so restore mode does not die on cross-version root hash / seal checks.

Falls back to a string-anchored CBZ search if the fixed offset does not match
(other boards / nearby 16.4 builds).
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

RE_OFFSET = 0x37114
RE_PRE = bytes.fromhex("f3020034")
RE_POST = bytes.fromhex("17000014")  # B #0x5c (same displacement as the CBZ)

# CBZ Wt, label — imm19==0x17 (displacement +0x5c) is common for this handler.
CBZ_W19_PLUS_5C = bytes.fromhex("f3020034")


def patch_fixed(data: bytearray) -> int:
    if data[RE_OFFSET : RE_OFFSET + 4] != RE_PRE:
        raise ValueError(
            f"fixed offset 0x{RE_OFFSET:x} has "
            f"{data[RE_OFFSET:RE_OFFSET+4].hex()}, expected {RE_PRE.hex()}"
        )
    data[RE_OFFSET : RE_OFFSET + 4] = RE_POST
    return RE_OFFSET


def patch_search(data: bytearray) -> int:
    # Prefer an occurrence near the seal diagnostic string if present.
    anchors = (
        b"seal_system_volume",
        b"Skipping sealing system volume",
        b"allow-root-hash-mismatch",
        b"SystemVolume",
    )
    candidates: list[int] = []
    for i in range(0, len(data) - 3, 4):
        if data[i : i + 4] == CBZ_W19_PLUS_5C:
            candidates.append(i)
    if not candidates:
        raise ValueError("no CBZ w19,+0x5c candidates found in restored_external")

    # If we can find a seal string, pick the CBZ within 0x4000 bytes after it.
    for anchor in anchors:
        pos = data.find(anchor)
        if pos < 0:
            continue
        nearby = [c for c in candidates if pos - 0x200 <= c <= pos + 0x4000]
        if len(nearby) == 1:
            off = nearby[0]
            data[off : off + 4] = RE_POST
            return off
        if len(nearby) > 1:
            # Closest after the string.
            after = [c for c in nearby if c >= pos]
            off = min(after or nearby)
            data[off : off + 4] = RE_POST
            return off

    # Last resort: unique global match.
    if len(candidates) == 1:
        off = candidates[0]
        data[off : off + 4] = RE_POST
        return off
    raise ValueError(
        f"ambiguous CBZ candidates ({len(candidates)}); need seal string anchor"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    raw = bytearray(args.input.read_bytes())
    try:
        off = patch_fixed(raw)
        method = "fixed-d421-16.4"
    except ValueError as fixed_err:
        try:
            off = patch_search(raw)
            method = f"search ({fixed_err})"
        except ValueError as search_err:
            print(f"ERROR: restored_external seal patch failed: {search_err}", file=sys.stderr)
            return 1

    if args.input.read_bytes() == bytes(raw):
        print("ERROR: restored_external patch made no changes", file=sys.stderr)
        return 1

    args.output.write_bytes(raw)
    print(
        f"restored_external seal skip: {method} @0x{off:x} "
        f"{RE_PRE.hex()} -> {RE_POST.hex()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
