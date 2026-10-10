#!/usr/bin/env python3
import argparse
import hashlib
from pathlib import Path
import zipfile
from audit_kodi_core import VENDOR, load_inventory, verify_elf

parser = argparse.ArgumentParser()
parser.add_argument('apk', type=Path)
parser.add_argument('--abi', default='arm64-v8a')
parser.add_argument('--strict-abi', action='store_true')
args = parser.parse_args()
if args.abi != 'arm64-v8a':
    raise SystemExit('Kodi Beta 1 supports ARM64 only')

inventory = load_inventory()
with zipfile.ZipFile(args.apk) as apk:
    corrupt = apk.testzip()
    if corrupt:
        raise SystemExit('Corrupt APK entry: ' + corrupt)
    names = set(apk.namelist())
    for source, expected in inventory.items():
        name = source.replace('jniLibs/', 'lib/', 1) if source.startswith('jniLibs/') else source
        if name not in names:
            raise SystemExit('APK missing native Kodi runtime: ' + name)
        data = apk.read(name)
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit('APK Kodi runtime checksum mismatch: ' + name)
        if name.startswith('lib/') and name.endswith('.so'):
            verify_elf(data, name)
    if args.strict_abi:
        if any(n.startswith('lib/') and not n.startswith('lib/arm64-v8a/') for n in names):
            raise SystemExit('APK contains an unexpected native ABI')
    dex = b''.join(apk.read(n) for n in names if n.startswith('classes') and n.endswith('.dex'))
    classes = [
        b'L' + p.relative_to(VENDOR / 'java').with_suffix('').as_posix().encode() + b';'
        for p in (VENDOR / 'java').rglob('*.java')
    ]
    classes.append(b'Lcom/srtristesad/addko/KodiBootstrapActivity;')
    classes.append(b'Lcom/srtristesad/addko/XBMCInputDeviceListener;')
    classes.append(b'Lcom/srtristesad/addko/XBMCBroadcastReceiver;')
    for cls in classes:
        if cls not in dex:
            raise SystemExit('APK missing Kodi Android class: ' + cls.decode())
print('[AddKo] APK contains complete verified Kodi runtime + native InputStream (ARM64)')
