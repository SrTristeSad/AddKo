"""Package the media source tool and visual app into two .addko ZIPs.

Python standard library only. Does not require Flutter, Android or Docker.
"""
from __future__ import annotations

import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "examples"
DIST = ROOT / "dist"


def build_one(folder: str) -> Path:
    source = EXAMPLES / folder
    manifest_bytes = (source / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    if manifest.get("entry") != "main.lua":
        raise ValueError(f"Entrypoint inválido em {folder}")
    if manifest.get("type") not in ("app", "service"):
        raise ValueError(f"Tipo de extensão inválido em {folder}")
    main_bytes = (source / "main.lua").read_bytes()
    if not main_bytes:
        raise ValueError(f"Lua vazio em {folder}")
    if folder == "media_source_service":
        assert manifest["type"] == "service"
        assert manifest["permissions"] == ["network"]
    else:
        assert manifest["type"] == "app"
        assert manifest["permissions"] == ["media"]
        assert manifest["dependencies"] == ["io.addko.example.media-source"]

    name = "MediaSource" if folder == "media_source_service" else "MediaBridge"
    destination = DIST / f"{name}-{manifest['version']}.addko"
    destination.parent.mkdir(parents=True, exist_ok=True)
    entries = {
        "manifest.json": manifest_bytes,
        "main.lua": main_bytes,
    }
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        for path, contents in entries.items():
            archive.writestr(path, contents)
    with ZipFile(destination, "r") as archive:
        if set(archive.namelist()) != set(entries):
            raise RuntimeError("Pacote .addko contém arquivos incorretos")
        for name, expected in entries.items():
            if archive.read(name) != expected:
                raise RuntimeError(f"Falha de integridade em {name}")
    return destination


def main() -> None:
    service = build_one("media_source_service")
    addon = build_one("media_player_app")
    print("Serviço de mídia:", service)
    print("Addon visual:", addon)
    print("Instale o serviço primeiro, depois o addon.")


if __name__ == "__main__":
    main()
