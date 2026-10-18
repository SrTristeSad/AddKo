#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import shutil
import tarfile
import urllib.request
from pathlib import Path

VERSION = "5.5.1"
URL = f"https://www.lua.org/ftp/lua-{VERSION}.tar.gz"
SHA256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce"
ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "lua"
ARCHIVE = CACHE / f"lua-{VERSION}.tar.gz"
VENDOR = ROOT / "native" / "vendor"
TARGET = VENDOR / f"lua-{VERSION}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    print(f"Downloading Lua {VERSION} from official upstream...")
    with urllib.request.urlopen(URL, timeout=60) as response, ARCHIVE.open("wb") as output:
        shutil.copyfileobj(response, output)


def main() -> None:
    if TARGET.joinpath("src", "lua.h").is_file():
        print(f"Lua {VERSION} already staged at {TARGET}")
        return

    if not ARCHIVE.is_file() or sha256(ARCHIVE) != SHA256:
        if ARCHIVE.exists():
            ARCHIVE.unlink()
        download()

    actual = sha256(ARCHIVE)
    if actual != SHA256:
        raise SystemExit(f"Lua archive SHA-256 mismatch: expected {SHA256}, got {actual}")

    VENDOR.mkdir(parents=True, exist_ok=True)
    if TARGET.exists():
        shutil.rmtree(TARGET)

    print(f"Extracting verified Lua {VERSION}...")
    with tarfile.open(ARCHIVE, "r:gz") as archive:
        archive.extractall(VENDOR, filter="data")

    if not TARGET.joinpath("src", "lua.h").is_file():
        raise SystemExit("Lua extraction completed but src/lua.h was not found")

    print(f"Lua {VERSION} ready.")


if __name__ == "__main__":
    main()
