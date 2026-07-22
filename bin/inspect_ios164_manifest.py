#!/usr/bin/env python3
"""Read the selected erase identity from an IPSW BuildManifest."""

from __future__ import annotations

import argparse
import plistlib
import sys
import zipfile
from pathlib import Path


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(2)


def component_path(identity: dict, name: str) -> str:
    try:
        path = identity["Manifest"][name]["Info"]["Path"]
    except (KeyError, TypeError) as exc:
        fail(f"selected identity has no {name} path")
        raise AssertionError from exc
    if not isinstance(path, str) or not path:
        fail(f"selected identity has an invalid {name} path")
    return path


def load_manifest(path: Path) -> dict:
    try:
        with zipfile.ZipFile(path) as archive:
            return plistlib.loads(archive.read("BuildManifest.plist"))
    except FileNotFoundError:
        fail(f"missing IPSW: {path}")
    except KeyError:
        fail(f"{path} has no BuildManifest.plist")
    except (OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
        fail(f"cannot read {path}: {exc}")
    raise AssertionError


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipsw", type=Path)
    parser.add_argument("identifier")
    parser.add_argument("board")
    args = parser.parse_args()

    manifest = load_manifest(args.ipsw)
    supported = manifest.get("SupportedProductTypes", [])
    if args.identifier not in supported:
        fail(f"{args.ipsw.name} does not support {args.identifier}")

    matches: list[tuple[int, dict]] = []
    for index, identity in enumerate(manifest.get("BuildIdentities", [])):
        info = identity.get("Info", {})
        if (
            info.get("DeviceClass") == args.board
            and info.get("RestoreBehavior") == "Erase"
        ):
            matches.append((index, identity))

    if len(matches) != 1:
        fail(
            f"{args.ipsw.name} has {len(matches)} erase identities for "
            f"{args.board}, expected one"
        )

    index, identity = matches[0]
    fields = (
        str(manifest.get("ProductVersion", "")),
        str(manifest.get("ProductBuildVersion", "")),
        str(index),
        component_path(identity, "KernelCache"),
        component_path(identity, "OS"),
        component_path(identity, "RestoreRamDisk"),
        component_path(identity, "RestoreTrustCache"),
    )
    print("\t".join(fields))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
