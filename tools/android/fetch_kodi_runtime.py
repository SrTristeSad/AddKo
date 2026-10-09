#!/usr/bin/env python3
"""Stage pinned official Kodi binaries; integration overlays stay versioned in Git."""
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'third_party/kodi_21_3'
CACHE = ROOT / '.cache/kodi'


def download(url, checksum, name):
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / name
    def valid():
        return target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == checksum
    if not valid():
        temporary = target.with_suffix(target.suffix + '.pending')
        print('Downloading pinned runtime:', name, flush=True)
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as output:
            shutil.copyfileobj(response, output)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != checksum:
            raise RuntimeError('Runtime checksum mismatch: ' + name)
        temporary.replace(target)
    return target


def write(name, data):
    target = (VENDOR / name).resolve()
    if not target.is_relative_to(VENDOR.resolve()):
        raise ValueError('Unsafe runtime entry: ' + name)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


def main():
    # Save versioned integration overlays before replacing official files.
    overlay_names = ['assets/system/addon-manifest.xml',
                     'assets/addons/skin.estuary/xml/Home.xml',
                     'assets/addons/script.addko.bridge/addon.xml',
                     'assets/addons/script.addko.bridge/default.py']
    overlays = {name: (VENDOR / name).read_bytes() for name in overlay_names}
    provenance = json.loads((VENDOR / 'PROVENANCE.json').read_text())
    apk = download(provenance['apk_url'], provenance['apk_sha256'], 'kodi-21.3-arm64.apk')
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            if name.endswith('/'):
                continue
            if name.startswith('assets/'):
                write(name, archive.read(name))
            elif name.startswith('lib/arm64-v8a/'):
                write(name.replace('lib/', 'jniLibs/', 1), archive.read(name))
    addons = json.loads((VENDOR / 'INPUTSTREAM_PROVENANCE.json').read_text())
    for addon in addons:
        filename = addon['id'] + '-' + addon['version'] + '.zip'
        url = 'https://mirrors.kodi.tv/addons/omega/' + addon['id'] + '+android-aarch64/' + filename
        package = download(url, addon['sha256'], filename)
        with zipfile.ZipFile(package) as archive:
            for name in archive.namelist():
                if name.endswith('/'):
                    continue
                if name.endswith('.so'):
                    library = Path(name).name
                    if not library.startswith('lib'):
                        library = 'lib' + library
                    write('jniLibs/arm64-v8a/' + library, archive.read(name))
                else:
                    write('assets/addons/' + name, archive.read(name))
    for name, data in overlays.items():
        write(name, data)
    from audit_kodi_core import main as audit
    audit()


if __name__ == '__main__':
    main()
