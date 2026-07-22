#!/usr/bin/env python3
"""Build a usbliter8-aware futurerestore from stock LukeeGD v2.0.0 Build 329.

Stock futurerestore refuses live Recovery + --use-pwndfu + --no-ibss (the liter8
handoff path) and trips generator/skip-blob edges that A13 cross-version restores
need. Offsets target the arm64 slice of:

  futurerestore v2.0.0(45d0267ee24854d8bb9f5dbef29c3226af0d48db-329)

This is the same v12 patch set used by the proven A13 16.4 restore path.
"""

from __future__ import annotations

import argparse
import platform
import shutil
import subprocess
import sys
from pathlib import Path

NOP = bytes.fromhex("1f2003d5")


def find_branch_to(data: bytearray, target: int) -> list[int]:
    hits: list[int] = []
    for off in range(0, len(data) - 4, 4):
        w = int.from_bytes(data[off : off + 4], "little")
        if (w & 0xFC000000) == 0x14000000:  # B
            imm26 = w & 0x3FFFFFF
            if imm26 & 0x2000000:
                imm26 -= 0x4000000
            if off + imm26 * 4 == target:
                hits.append(off)
        if (w & 0xFF000010) == 0x54000000:  # B.cond
            imm19 = (w >> 5) & 0x7FFFF
            if imm19 & 0x40000:
                imm19 -= 0x80000
            if off + imm19 * 4 == target:
                hits.append(off)
        if (w & 0x7F000000) == 0x34000000:  # CBZ/CBNZ
            imm19 = (w >> 5) & 0x7FFFF
            if imm19 & 0x40000:
                imm19 -= 0x80000
            if off + imm19 * 4 == target:
                hits.append(off)
    return hits


def bl_target(data: bytearray, off: int) -> int:
    w = int.from_bytes(data[off : off + 4], "little")
    imm26 = w & 0x3FFFFFF
    if imm26 & 0x2000000:
        imm26 -= 0x4000000
    return off + imm26 * 4


def patch_arm64(data: bytearray) -> list[str]:
    patched: list[str] = []

    gen_sites = {
        "getGenerator_missing_cbz": 0xB9EC,
        "getGenerator_missing_bcond": 0xBA24,
        "plist_generator_guard": 0xDE58,
        "set_generator_fail": 0xA4D8,
    }
    for label, target in gen_sites.items():
        hits = find_branch_to(data, target)
        if len(hits) != 1:
            raise SystemExit(f"Could not locate generator patch site {label}: {hits}")
        data[hits[0] : hits[0] + 4] = NOP
        patched.append(f"{label}@{hits[0]:#x}")

    for fixed in (0xC424,):
        word = int.from_bytes(data[fixed : fixed + 4], "little")
        if (word & 0xFC000000) == 0x94000000:  # BL
            data[fixed : fixed + 4] = NOP
            patched.append(f"plist_generator_bl@{fixed:#x}")

    reterror_fn = 0x1EB0F4
    for off in range(0xBA00, 0xBAD4, 4):
        w = int.from_bytes(data[off : off + 4], "little")
        if (w & 0xFFFFFC00) != 0x5281A000:
            continue
        bl = off + 4
        if (int.from_bytes(data[bl : bl + 4], "little") & 0xFC000000) != 0x94000000:
            continue
        if bl_target(data, bl) != reterror_fn:
            continue
        data[bl : bl + 4] = NOP
        patched.append(f"getGenerator_genstr_throw@{bl:#x}")

    v8_fixed = {
        "enterPwnRecovery_nonce_mismatch_bcond": 0xB924,
        "generator_sha_fail_bcond_1": 0xBC1C,
        "generator_sha_fail_bcond_2": 0xBCB4,
        "generator_sha_fail_bcond_3": 0xBD48,
        "generator_sha_fail_bcond_4": 0xBDB0,
        "generator_sha_fail_bcond_5": 0xBEEC,
        "generator_sha_fail_bl_1": 0xBF10,
        "generator_sha_fail_bl_2": 0xBF18,
        "generator_sha_fail_bl_3": 0xBF20,
        "generator_sha_fail_bl_4": 0xBF28,
    }
    for label, off in v8_fixed.items():
        data[off : off + 4] = NOP
        patched.append(f"{label}@{off:#x}")

    fixed_words = {
        # v10: --no-ibss / restore-mode wait honesty
        0xCC70: (NOP, "skip_enterPwnRecovery_dfu_beq"),
        0xD5F8: (NOP, "recovery_enter_restore_retassure_cbnz"),
        0xD690: (NOP, "mode_restore_wait_bne"),
        # v11: skip enterPwnRecovery wrapper that re-sends iBEC
        0xCEA0: (NOP, "skip_doRestore_enterPwnRecovery_bl"),
        # v12: recovery + --use-pwndfu + --no-ibss fallthrough + skip-blob safety
        0xC2A0: (NOP, "allow_recovery_pwndfu_noibss_fallthrough"),
        0xC79C: (bytes.fromhex("64000014"), "force_skipblob_buildidentity_continue"),
        0xCEB4: (bytes.fromhex("0b000014"), "force_skipblob_skip_stale_error_free"),
        0xCEDC: (NOP, "force_skipblob_skip_stale_error_free_loopback"),
    }
    for off, (word, label) in fixed_words.items():
        data[off : off + 4] = word
        patched.append(f"{label}@{off:#x}")

    required_nops = {
        0xB84C: "getGenerator_missing_cbz",
        0xB85C: "getGenerator_missing_bcond",
        0xB924: "enterPwnRecovery_nonce_mismatch_bcond",
        0xBA1C: "getGenerator_genstr_throw_1",
        0xBA54: "getGenerator_genstr_throw_2",
        0xBA8C: "getGenerator_genstr_throw_3",
        0xBACC: "getGenerator_genstr_throw_4",
        0xBC1C: "generator_sha_fail_bcond_1",
        0xBCB4: "generator_sha_fail_bcond_2",
        0xBD48: "generator_sha_fail_bcond_3",
        0xBDB0: "generator_sha_fail_bcond_4",
        0xBEEC: "generator_sha_fail_bcond_5",
        0xBF10: "generator_sha_fail_bl_1",
        0xBF18: "generator_sha_fail_bl_2",
        0xBF20: "generator_sha_fail_bl_3",
        0xBF28: "generator_sha_fail_bl_4",
        0xC424: "plist_generator_bl",
        0xC428: "plist_generator_guard",
        0xA2A4: "set_generator_fail",
        0xCC70: "skip_enterPwnRecovery_dfu_beq",
        0xD5F8: "recovery_enter_restore_retassure_cbnz",
        0xD690: "mode_restore_wait_bne",
        0xCEA0: "skip_doRestore_enterPwnRecovery_bl",
        0xC2A0: "allow_recovery_pwndfu_noibss_fallthrough",
        0xCEDC: "force_skipblob_skip_stale_error_free_loopback",
    }
    for off, label in required_nops.items():
        if data[off : off + 4] != NOP:
            raise SystemExit(
                f"Patch verify failed for {label} @{off:#x}="
                f"{data[off:off + 4].hex()}"
            )
    if data[0xC79C : 0xC79C + 4] != bytes.fromhex("64000014"):
        raise SystemExit("Patch verify failed for force_skipblob_buildidentity_continue")
    if data[0xCEB4 : 0xCEB4 + 4] != bytes.fromhex("0b000014"):
        raise SystemExit("Patch verify failed for force_skipblob_skip_stale_error_free")

    return patched


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("stock", type=Path, help="stock futurerestore binary")
    parser.add_argument("output", type=Path, help="output futurerestore-usbliter8 path")
    args = parser.parse_args()

    if not args.stock.is_file():
        raise SystemExit(f"missing stock futurerestore: {args.stock}")

    host = platform.machine()
    if host not in ("arm64", "x86_64"):
        raise SystemExit(f"unsupported host architecture: {host}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    arm = args.output.parent / ".futurerestore-arm64.tmp"
    try:
        subprocess.run(
            ["lipo", str(args.stock), "-thin", "arm64", "-output", str(arm)],
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        # Already a thin arm64 binary.
        try:
            shutil.copy2(args.stock, arm)
        except OSError as copy_exc:
            raise SystemExit(f"could not prepare arm64 slice: {exc} / {copy_exc}") from copy_exc

    data = bytearray(arm.read_bytes())
    if len(data) < 0x100000:
        raise SystemExit(f"arm64 slice looks too small ({len(data)} bytes)")

    patched = patch_arm64(data)
    print("futurerestore v12 patches:", ", ".join(patched), file=sys.stderr)
    arm.write_bytes(data)

    if host == "arm64":
        shutil.copy2(arm, args.output)
    else:
        # Intel host: ship a fat binary. The x86_64 slice stays stock; the arm64
        # slice is patched for Apple Silicon / Rosetta-remote use. The iOS 16.4
        # restore path itself requires Apple Silicon (arm64 host) at runtime.
        x86 = args.output.with_suffix(".x86_64.tmp")
        try:
            subprocess.run(
                ["lipo", str(args.stock), "-thin", "x86_64", "-output", str(x86)],
                check=True,
            )
            subprocess.run(
                ["lipo", "-create", str(x86), str(arm), "-output", str(args.output)],
                check=True,
            )
        finally:
            x86.unlink(missing_ok=True)

    arm.unlink(missing_ok=True)
    args.output.chmod(0o755)
    subprocess.run(["xattr", "-cr", str(args.output)], check=False)
    # Ad-hoc sign so macOS will exec a rewritten binary.
    subprocess.run(
        ["codesign", "-s", "-", "-f", str(args.output)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
