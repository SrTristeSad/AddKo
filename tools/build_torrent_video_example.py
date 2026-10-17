"""Build the legally-neutral AddKo/Luelement video torrent demo (Python stdlib)."""
from __future__ import annotations

import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "examples" / "torrent_video"
OUTPUT = ROOT / "dist" / "VideoTorrent-0.1.0.addko"


def build() -> Path:
    manifest_bytes = (SOURCE / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    assert manifest["id"] == "io.addko.examples.torrent_video"
    assert manifest["entry"] == "main.lua"
    assert manifest["dependencies"] == ["io.addko.luelement"]
    assert manifest["permissions"] == []
    files = {"manifest.json": manifest_bytes, "main.lua": (SOURCE / "main.lua").read_bytes()}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUTPUT, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in files.items():
            archive.writestr(name, content)
    with ZipFile(OUTPUT) as archive:
        assert set(archive.namelist()) == set(files)
        assert all(archive.read(name) == content for name, content in files.items())
    return OUTPUT


if __name__ == "__main__":
    print(f"Pacote AddKo criado: {build()}")
