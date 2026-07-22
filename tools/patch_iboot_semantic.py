#!/usr/bin/env python3
import argparse
import importlib.util
import struct
from pathlib import Path

from capstone import CS_ARCH_ARM64, CS_MODE_ARM, Cs


MOV_X0_ZERO = struct.pack("<I", 0xD2800000)

# Function-boundary markers emitted by the compiler at every iBoot function
# prologue on A12/A13 (pointer-auth signed / branch-target-ident).
PACIBSP = 0xD503237F
BTI_C = 0xD503245F
# Authenticated indirect *call* mnemonics (BLRAA/BLRAAZ/BLRAB/BLRABZ). The
# property-validate callback dispatches into the registered sub-callbacks with
# these; ordinary functions rarely use three of them.
AUTH_CALLS = ("blraa", "blraaz", "blrab", "blrabz")


def load_patchfinder(path):
    spec = importlib.util.spec_from_file_location("spiro_patchfinder", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _function_bounds(data):
    """Yield (start, end) file offsets for every discovered iBoot function."""
    size = len(data)
    code_end = size
    for off in range(size - 4, 0, -4):
        if struct.unpack_from("<I", data, off)[0] in (PACIBSP, BTI_C):
            code_end = min(size, off + 0x1000)
            break
    starts = [off for off in range(0, code_end - 4, 4)
              if struct.unpack_from("<I", data, off)[0] in (PACIBSP, BTI_C)]
    for index, start in enumerate(starts):
        nxt = starts[index + 1] if index + 1 < len(starts) else code_end
        yield start, min(nxt, start + 0x2000)


def _is_callback_function(instructions):
    """Structural signature of image4_validate_property_callback.

    Version-invariant across iOS 16-27 on A12/A13: the callback switches on the
    Image4 property value type loaded from ``[argN, #0x10]`` with a {4, 2, 1}
    three-way dispatch, then invokes the registered sub-callbacks through
    authenticated indirect calls. The string anchor the patchfinder normally
    uses is absent on 16-18 (the error strings live in an unreferenced table),
    so this locates the same function purely from its shape.
    """
    auth_calls = sum(1 for ins in instructions
                     if ins.mnemonic in AUTH_CALLS)
    for index, ins in enumerate(instructions):
        if ins.mnemonic != "cmp":
            continue
        parts = ins.op_str.replace(",", "").split()
        if len(parts) != 2 or not parts[1].startswith("#"):
            continue
        reg = parts[0]
        try:
            if int(parts[1][1:], 0) != 4:
                continue
        except ValueError:
            continue
        seen_two = seen_one = False
        for follow in instructions[index + 1:index + 24]:
            if follow.mnemonic != "cmp":
                continue
            q = follow.op_str.replace(",", "").split()
            if len(q) == 2 and q[0] == reg and q[1].startswith("#"):
                try:
                    value = int(q[1][1:], 0)
                except ValueError:
                    continue
                if value == 2:
                    seen_two = True
                elif value == 1:
                    seen_one = True
        if not (seen_two and seen_one):
            continue
        # The dispatched value must be the property type loaded from [reg, #0x10].
        for prev in instructions[max(0, index - 6):index][::-1]:
            if (prev.mnemonic in ("ldr", "ldrb", "ldrh")
                    and prev.op_str.startswith(reg + ",")
                    and prev.op_str.rstrip().endswith("#0x10]")):
                return auth_calls >= 3
    return False


def find_callback_by_signature(data):
    """Locate the property-validate callback function start, fail-closed.

    Requires exactly one function to match the structural signature; otherwise
    the caller falls back to the audited iBoot64Patcher path.
    """
    disassembler = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    matches = []
    for start, end in _function_bounds(data):
        instructions = list(disassembler.disasm(data[start:end], start))
        if _is_callback_function(instructions):
            matches.append(start)
    if len(matches) != 1:
        raise ValueError(
            f"callback signature matched {len(matches)} functions, expected 1")
    return matches[0]


def callback_patch(data, patchfinder_path):
    module = load_patchfinder(patchfinder_path)
    finder = module.IBootPatchfinder(data, mode="ibss", verbose=False)
    finder.find_key_functions()
    start = finder.results.get("_image4_validate_property_callback")
    if start is None:
        # iOS 16-18 iBoot: no per-string adrp anchor. Locate the callback by its
        # version-invariant instruction shape instead (still fail-closed).
        start = find_callback_by_signature(data)
    disassembler = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    candidates = []
    end = min(len(data), start + 0x1800)
    instructions = list(disassembler.disasm(data[start:end], start))
    for index, instruction in enumerate(instructions):
        if instruction.mnemonic != "mov" or not instruction.op_str.startswith("x0, x"):
            continue
        try:
            source = int(instruction.op_str.split("x")[-1])
        except ValueError:
            continue
        if source < 19 or source > 28 or index == 0:
            continue
        previous = instructions[index - 1]
        following = instructions[index + 1:index + 18]
        has_return = any(item.mnemonic in ("ret", "retab") for item in following)
        has_restore = any(item.mnemonic == "ldp" and "sp" in item.op_str
                          for item in following)
        if previous.mnemonic == "b.ne" and has_return and has_restore:
            candidates.append(instruction.address)
    if len(candidates) != 1:
        raise ValueError(f"expected one verified callback return, found {len(candidates)}")
    offset = candidates[0]
    output = bytearray(data)
    output[offset:offset + 4] = MOV_X0_ZERO
    return output, offset


def replace_unique(data, old, new):
    if len(old) != len(new):
        raise ValueError("same-length replacement required")
    offsets = []
    position = 0
    while True:
        position = data.find(old, position)
        if position < 0:
            break
        offsets.append(position)
        position += 1
    if len(offsets) != 1:
        raise ValueError(f"expected one {old!r}, found {len(offsets)}")
    data[offsets[0]:offsets[0] + len(old)] = new
    return offsets[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--mode", choices=("ibss", "ibec"), required=True)
    parser.add_argument("--patchfinder", type=Path, required=True)
    args = parser.parse_args()
    source = args.input.read_bytes()
    output, callback = callback_patch(source, args.patchfinder)
    changes = [f"callback=0x{callback:x}"]
    if args.mode == "ibec":
        progress = replace_unique(output, b" -progress\0", b" -v\0\0\0\0\0\0\0\0")
        restore = replace_unique(output, b" -restore\0", b" wdt=-1\0\0\0")
        changes.extend((f"progress=0x{progress:x}", f"restore=0x{restore:x}"))
    args.output.write_bytes(output)
    changed = sum(left != right for left, right in zip(source, output))
    expected = 4 if args.mode == "ibss" else 20
    if changed != expected:
        args.output.unlink(missing_ok=True)
        raise SystemExit(f"unsafe patch result: expected {expected} changed bytes, got {changed}")
    print(f"{args.mode}: {changed} changed bytes; " + " ".join(changes))


if __name__ == "__main__":
    main()
