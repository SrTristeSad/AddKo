#!/usr/bin/env python3
"""Compile the same AddKo sandbox C/Lua runtime for Linux-only CI tests.

This script does not package any native module into a .addko file and does
not grant Lua arbitrary native execution.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CMAKE = ROOT / "native" / "CMakeLists.txt"
LUA = ROOT / "native" / "vendor" / "lua-5.5.1" / "src"


def main() -> None:
    if sys.platform != "linux":
        raise SystemExit("Linux CI runner required")
    if len(sys.argv) != 2:
        raise SystemExit("Usage: build_test_lua.py /absolute/output.so")
    output = Path(sys.argv[1]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    cmake_text = CMAKE.read_text(encoding="utf-8")
    core_match = re.search(r"set\(LUA_CORE(.*?)\n\)", cmake_text, re.S)
    if not core_match:
        raise SystemExit("Cannot locate Lua core files in native CMakeLists")
    names = re.findall(r"\$\{LUA_ROOT\}/([A-Za-z0-9_]+\.c)", core_match.group(1))
    if len(names) < 20:
        raise SystemExit("Unexpected missing Lua core source files")

    files = [ROOT / "native" / "addko_lua_bridge.c"]
    files.extend(LUA / name for name in names)
    if not all(path.is_file() for path in files):
        raise SystemExit("Native sources missing; run tools/fetch_lua.py first")

    command = [
        "cc", "-shared", "-fPIC", "-std=c99", "-O2",
        "-fvisibility=hidden", "-DLUA_USE_C89", "-I", str(LUA),
        "-o", str(output),
        *(str(path) for path in files),
        "-lm", "-ldl",
    ]
    subprocess.run(command, check=True)
    print(f"Built exact AddKo sandbox Lua sources: {output}")


if __name__ == "__main__":
    main()
