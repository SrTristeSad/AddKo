#!/usr/bin/env python3
"""Verify the bundled Kodi runtime while ignoring generated Python bytecode caches."""
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'third_party/kodi_21_3'


def is_transient_python_cache(name: str) -> bool:
    normalized = name.replace('\\', '/')
    parts = normalized.split('/')
    return '__pycache__' in parts or normalized.endswith(('.pyc', '.pyo'))


def load_inventory():
    raw = json.loads((VENDOR / 'RUNTIME_INVENTORY.json').read_text(encoding='utf-8'))
    # Backward compatibility: old inventories accidentally included generated
    # CPython bytecode. Never make those caches part of runtime integrity.
    return {name: checksum for name, checksum in raw.items()
            if not is_transient_python_cache(name)}


def verify_elf(data, name):
    if data[:5] != b'\x7fELF\x02' or data[5] != 1 or struct.unpack_from('<H', data, 18)[0] != 183:
        raise ValueError('%s is not an ARM64 ELF library' % name)


def main():
    inventory = load_inventory()
    for name, expected in inventory.items():
        p = VENDOR / name
        if not p.is_file():
            raise ValueError('Missing Kodi runtime file: ' + name)
        if hashlib.sha256(p.read_bytes()).hexdigest() != expected:
            raise ValueError('Kodi runtime file changed: ' + name)
        if name.startswith('jniLibs/') and name.endswith('.so'):
            verify_elf(p.read_bytes(), name)

    required = [
        'jniLibs/arm64-v8a/libkodi.so',
        'jniLibs/arm64-v8a/libinputstream.adaptive.so',
        'jniLibs/arm64-v8a/libinputstream.ffmpegdirect.so',
        'assets/python3.11/lib/python3.11/os.py',
        'assets/addons/skin.estuary/addon.xml',
        'assets/system/addon-manifest.xml',
        'assets/addons/repository.xbmc.org/addon.xml',
        'assets/addons/script.addko.bridge/default.py',
    ]
    missing_required = [name for name in required if name not in inventory]
    if missing_required:
        raise ValueError('Incomplete native core inventory: ' + ', '.join(missing_required))

    print('[AddKo] Kodi 21.3 native core: OK (%d stable files, ARM64; Python caches ignored)' % len(inventory))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit('[AddKo] ' + str(exc))
