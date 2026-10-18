"""Build the legally-neutral AddKo/Luelement video torrent demo (Python stdlib)."""
from __future__ import annotations

import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "examples" / "torrent_video"



def build() -> Path:
    manifest_bytes = (SOURCE / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    assert manifest["id"] == "io.addko.examples.torrent_video"
    assert manifest["entry"] == "main.lua"
    assert manifest["dependencies"] == ["io.addko.luelement"]
    assert manifest["permissions"] == []
    output = ROOT / "dist" / f"VideoTorrent-{manifest['version']}.addko"
    files = {"manifest.json": manifest_bytes, "main.lua": (SOURCE / "main.lua").read_bytes()}
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in files.items():
            archive.writestr(name, content)
    with ZipFile(output) as archive:
        assert set(archive.namelist()) == set(files)
        assert all(archive.read(name) == content for name, content in files.items())
    return output


if __name__ == "__main__":
    print(f"Pacote AddKo criado: {build()}")
