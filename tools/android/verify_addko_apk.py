#!/usr/bin/env python3
"""Verify the Android APK contains only the native runtime it is meant to ship."""

from __future__ import annotations

import argparse
import json
import zipfile
from pathlib import Path

PYTHON_VERSION = "3.14.8"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--abi", default="arm64-v8a")
    parser.add_argument(
        "--strict-abi",
        action="store_true",
        help="Fail if another AddKo CPython ABI is accidentally packaged.",
    )
    args = parser.parse_args()

    apk = args.apk.resolve()
    if not apk.is_file():
        raise SystemExit(f"[AddKo] APK not found: {apk}")

    abi = args.abi
    manifest_name = "assets/addko_python/manifest.json"
    required = {
        f"lib/{abi}/libaddko_python_host.so",
        f"lib/{abi}/libaddko_kodi_engine.so",
        f"lib/{abi}/libpython3.14.so",
        f"assets/addko_python/{PYTHON_VERSION}/{abi}/stdlib.zip",
        manifest_name,
    }

    with zipfile.ZipFile(apk, "r") as archive:
        names = set(archive.namelist())
        missing = sorted(required - names)
        bad = archive.testzip()

        manifest_abis: set[str] = set()
        if manifest_name in names:
            try:
                manifest = json.loads(archive.read(manifest_name).decode("utf-8"))
                raw_abis = manifest.get("abis", [])
                if isinstance(raw_abis, list):
                    for item in raw_abis:
                        if isinstance(item, dict) and item.get("abi"):
                            manifest_abis.add(str(item["abi"]))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise SystemExit(
                    f"[AddKo] invalid CPython runtime manifest inside APK: {error}"
                ) from error

    if bad is not None:
        raise SystemExit(f"[AddKo] APK contains a corrupt ZIP entry: {bad}")
    if missing:
        raise SystemExit(
            "[AddKo] APK is missing required native/runtime files:\n  - "
            + "\n  - ".join(missing)
        )

    if manifest_abis and abi not in manifest_abis:
        raise SystemExit(
            f"[AddKo] runtime manifest does not declare requested ABI {abi}: "
            + ", ".join(sorted(manifest_abis))
        )

    if args.strict_abi:
        extra_assets = sorted(
            name
            for name in names
            if name.startswith(f"assets/addko_python/{PYTHON_VERSION}/")
            and name.endswith("/stdlib.zip")
            and name != f"assets/addko_python/{PYTHON_VERSION}/{abi}/stdlib.zip"
        )
        extra_python = sorted(
            name
            for name in names
            if name.startswith("lib/")
            and name.endswith("/libpython3.14.so")
            and name != f"lib/{abi}/libpython3.14.so"
        )
        if extra_assets or extra_python:
            extras = [*extra_assets, *extra_python]
            raise SystemExit(
                "[AddKo] lean APK contains an unexpected CPython ABI:\n  - "
                + "\n  - ".join(extras)
            )
        if manifest_abis and manifest_abis != {abi}:
            raise SystemExit(
                "[AddKo] lean APK manifest declares extra ABIs: "
                + ", ".join(sorted(manifest_abis))
            )

    print(f"[AddKo] APK native runtime: OK ({abi})")
    print("[AddKo]   libaddko_python_host.so")
    print("[AddKo]   libaddko_kodi_engine.so")
    print("[AddKo]   libpython3.14.so")
    print("[AddKo]   CPython stdlib.zip")
    if args.strict_abi:
        print("[AddKo]   no extra CPython ABI packaged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
