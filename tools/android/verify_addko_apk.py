#!/usr/bin/env python3
"""Verify the Android APK contains the native runtimes AddKo depends on."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--abi", default="arm64-v8a")
    args = parser.parse_args()

    apk = args.apk.resolve()
    if not apk.is_file():
        raise SystemExit(f"[AddKo] APK not found: {apk}")

    abi = args.abi
    required = {
        f"lib/{abi}/libaddko_python_host.so",
        f"lib/{abi}/libaddko_kodi_engine.so",
        f"lib/{abi}/libpython3.14.so",
        f"assets/addko_python/3.14.8/{abi}/stdlib.zip",
        "assets/addko_python/manifest.json",
    }

    with zipfile.ZipFile(apk, "r") as archive:
        names = set(archive.namelist())
        missing = sorted(required - names)
        bad = archive.testzip()

    if bad is not None:
        raise SystemExit(f"[AddKo] APK contains a corrupt ZIP entry: {bad}")
    if missing:
        raise SystemExit(
            "[AddKo] APK is missing required native/runtime files:\n  - "
            + "\n  - ".join(missing)
        )

    print(f"[AddKo] APK native runtime: OK ({abi})")
    print("[AddKo]   libaddko_python_host.so")
    print("[AddKo]   libaddko_kodi_engine.so")
    print("[AddKo]   libpython3.14.so")
    print("[AddKo]   CPython stdlib.zip")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
