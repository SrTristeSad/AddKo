#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

REQUIRED = {
    "zipfile/_path/__init__.py",
    "zipfile/_path/glob.py",
    "_collections_abc.py",
    "importlib/__init__.py",
    "ssl.py",
    "sqlite3/__init__.py",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()

    archive = args.archive.resolve()
    if not archive.is_file():
        print(f"[ERRO] stdlib.zip nao encontrado: {archive}")
        return 1

    try:
        with zipfile.ZipFile(archive, "r") as zf:
            names = set(zf.namelist())
            missing = sorted(REQUIRED - names)
            bad = zf.testzip()
    except (OSError, zipfile.BadZipFile) as error:
        print(f"[ERRO] stdlib.zip invalido: {error}")
        return 1

    if missing:
        print("[ERRO] stdlib.zip sem arquivos obrigatorios:")
        for item in missing:
            print(f"  - {item}")
        return 1
    if bad is not None:
        print(f"[ERRO] stdlib.zip corrompido em: {bad}")
        return 1

    print(f"[AddKo] stdlib.zip: OK ({archive.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
