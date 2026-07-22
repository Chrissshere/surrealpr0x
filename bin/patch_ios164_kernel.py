#!/usr/bin/env python3
"""Patch the iOS 16.4 arm64e kernel.

This wrapper deliberately fails rather than emitting a stock or partially
patched kernel.  It combines the local Kernel64Patcher3 iOS-16 passes with
the semantic usbliter8 kernel patchfinder.  The latter must resolve all three
security-policy targets before an output is written.
"""

from __future__ import annotations

import argparse
import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATCHFINDER_CANDIDATES = (
    ROOT / "tools" / "kernel_patchfinder.py",
)


def require_changed(before: Path, after: Path, label: str) -> None:
    if not after.is_file() or after.stat().st_size != before.stat().st_size:
        raise RuntimeError(f"{label} produced an invalid output")
    if before.read_bytes() == after.read_bytes():
        raise RuntimeError(f"{label} made no changes; refusing a stock kernel")


def run_patcher(binary: Path, source: Path, destination: Path, flag: str) -> None:
    result = subprocess.run(
        [str(binary), str(source), str(destination), flag],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(
            f"Kernel64Patcher3 {flag} failed:\n{result.stdout}{result.stderr}"
        )
    require_changed(source, destination, f"Kernel64Patcher3 {flag}")
    print(f"Kernel64Patcher3 {flag}: verified")


def load_patchfinder(path: Path):
    spec = importlib.util.spec_from_file_location("kernel_patchfinder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load kernel patchfinder: {path}")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except ModuleNotFoundError as exc:
        if exc.name == "capstone":
            raise RuntimeError(
                "missing Python dependency 'capstone'; run "
                "./.venv/bin/pip install capstone"
            ) from exc
        raise
    return module


def resolve_patchfinder(explicit: Path | None) -> Path:
    candidates = (explicit,) if explicit else DEFAULT_PATCHFINDER_CANDIDATES
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate
    expected = " or ".join(str(item) for item in DEFAULT_PATCHFINDER_CANDIDATES)
    raise RuntimeError(f"missing kernel patchfinder ({expected})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--kernel64-patcher",
        type=Path,
        default=ROOT / "bin" / "Kernel64Patcher3",
    )
    parser.add_argument("--patchfinder", type=Path)
    args = parser.parse_args()

    if not args.input.is_file():
        raise SystemExit(f"missing input kernel: {args.input}")
    if not args.kernel64_patcher.is_file():
        raise SystemExit(f"missing Kernel64Patcher3: {args.kernel64_patcher}")

    patchfinder_path = resolve_patchfinder(args.patchfinder)
    work = Path(tempfile.mkdtemp(prefix="surreal-ios164-kernel-"))
    try:
        current = work / "stock.raw"
        shutil.copy2(args.input, current)

        # Use the supported locators for iOS 16.4.
        for flag in ("-a", "-f", "-h"):
            next_path = work / f"kernel-{flag[1:]}.raw"
            run_patcher(args.kernel64_patcher, current, next_path, flag)
            current = next_path

        module = load_patchfinder(patchfinder_path)
        patchfinder = module.KernelPatchfinder(current.read_bytes(), verbose=True)
        targets = patchfinder.find_all()
        required = {
            "PE_i_can_has_debugger",
            "AMFIIsCDHashInTrustCache",
            "launch_constraints_func",
        }
        missing = sorted(required.difference(targets))
        if missing:
            raise RuntimeError("unresolved kernel targets: " + ", ".join(missing))

        applied = patchfinder.patch_all(targets)
        if applied != 8:
            raise RuntimeError(f"kernel patchfinder applied {applied} patches, expected 8")

        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(bytes(patchfinder.data))
        require_changed(args.input, args.output, "combined iOS 16.4 patch set")
        changed = sum(a != b for a, b in zip(args.input.read_bytes(), args.output.read_bytes()))
        print(f"verified iOS 16.4 kernel: {changed} changed bytes")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
