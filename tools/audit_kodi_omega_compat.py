#!/usr/bin/env python3
"""Offline audit of AddKo's declared Kodi 21 (Omega) compatibility surface.

This audit intentionally separates *surface coverage* from *functional parity*.
Passing means AddKo has not accidentally lost an official Python module, Kodi
addon family, binary ABI declaration or pinned reference. Native subsystems such
as InputStream/PVR/Game can still be marked partial in the compatibility matrix.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PINNED_KODI_COMMIT = "f8815ee40f49a700c047982d752be4b2a61420e2"

PYTHON_MODULES = (
    "xbmc",
    "xbmcaddon",
    "xbmcdrm",
    "xbmcgui",
    "xbmcplugin",
    "xbmcvfs",
    "xbmcwsgi",
)

BINARY_CAPABILITIES = (
    "kodi.binary.global.main",
    "kodi.binary.global.general",
    "kodi.binary.global.gui",
    "kodi.binary.global.audioengine",
    "kodi.binary.global.filesystem",
    "kodi.binary.global.network",
    "kodi.binary.global.tools",
    "kodi.binary.instance.audiodecoder",
    "kodi.binary.instance.audioencoder",
    "kodi.binary.instance.game",
    "kodi.binary.instance.imagedecoder",
    "kodi.binary.instance.inputstream",
    "kodi.binary.instance.peripheral",
    "kodi.binary.instance.pvr",
    "kodi.binary.instance.screensaver",
    "kodi.binary.instance.vfs",
    "kodi.binary.instance.visualization",
    "kodi.binary.instance.videocodec",
)

# Markers cover Kodi Omega's official top-level addon type mapping. Prefixes are
# used where Kodi has a family of types (metadata scrapers/resources).
ADDON_EXTENSION_MARKERS = (
    "xbmc.metadata.scraper.",
    "xbmc.ui.screensaver",
    "xbmc.player.musicviz",
    "xbmc.python.pluginsource",
    "xbmc.python.script",
    "xbmc.python.weather",
    "xbmc.python.lyrics",
    "xbmc.python.library",
    "xbmc.python.module",
    "xbmc.subtitle.module",
    "kodi.context.item",
    "kodi.game.controller",
    "xbmc.gui.skin",
    "xbmc.webinterface",
    "xbmc.addon.repository",
    "kodi.pvrclient",
    "xbmc.pvrclient",
    "kodi.gameclient",
    "kodi.peripheral",
    "xbmc.addon.video",
    "xbmc.addon.audio",
    "xbmc.addon.image",
    "xbmc.addon.executable",
    "kodi.addon.game",
    "kodi.audioencoder",
    "kodi.audiodecoder",
    "xbmc.service",
    "kodi.resource.",
    "kodi.inputstream",
    "kodi.vfs",
    "kodi.imagedecoder",
)


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"[FALHA] {message}")


def main() -> int:
    failures: list[str] = []

    manifest_path = ROOT / "third_party" / "kodi_omega" / "api_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("commit") != PINNED_KODI_COMMIT:
        fail("api_manifest.json não usa o commit Kodi Omega fixado", failures)

    declared_modules = set((manifest.get("modules") or {}).keys())
    for module in PYTHON_MODULES:
        shim = ROOT / "runtime" / "python" / "shims" / f"{module}.py"
        swig = (
            ROOT
            / "third_party"
            / "kodi_omega"
            / "swig"
            / f"AddonModule{module[0].upper()}{module[1:]}.i"
        )
        if not shim.is_file():
            fail(f"shim ausente: {shim.relative_to(ROOT)}", failures)
        if not swig.is_file():
            fail(f"SWIG Omega ausente: {swig.relative_to(ROOT)}", failures)
        if module not in declared_modules:
            fail(f"módulo {module} ausente de api_manifest.json", failures)

    capability_path = (
        ROOT / "lib" / "core" / "addons" / "domain" / "kodi_host_capabilities.dart"
    )
    capability_source = capability_path.read_text(encoding="utf-8")
    for capability in BINARY_CAPABILITIES:
        if f"'{capability}'" not in capability_source:
            fail(f"capacidade binária não declarada: {capability}", failures)

    vendor_source = (ROOT / "tools" / "vendor_kodi_omega_api.py").read_text(
        encoding="utf-8"
    )
    if f'KODI_COMMIT = "{PINNED_KODI_COMMIT}"' not in vendor_source:
        fail("vendor_kodi_omega_api.py não usa o commit Omega fixado", failures)
    for module in (
        "Xbmc",
        "Xbmcaddon",
        "Xbmcdrm",
        "Xbmcgui",
        "Xbmcplugin",
        "Xbmcvfs",
        "Xbmcwsgi",
    ):
        if f"AddonModule{module}.i" not in vendor_source:
            fail(f"vendor não cobre AddonModule{module}.i", failures)

    versions = re.findall(
        r"'((?:kodi\.binary\.(?:global|instance)\.[^']+))'\s*:\s*'([^']+)'",
        capability_source,
    )
    if len(versions) != len(BINARY_CAPABILITIES):
        fail(
            "quantidade de capacidades binárias difere da matriz Omega esperada "
            f"({len(versions)} != {len(BINARY_CAPABILITIES)})",
            failures,
        )

    addon_manifest_source = (
        ROOT / "lib" / "core" / "addons" / "domain" / "addon_manifest.dart"
    ).read_text(encoding="utf-8")
    repository_parser_source = (
        ROOT
        / "lib"
        / "core"
        / "repositories"
        / "infrastructure"
        / "repository_index_parser.dart"
    ).read_text(encoding="utf-8")
    addon_surface = addon_manifest_source + "\n" + repository_parser_source
    for marker in ADDON_EXTENSION_MARKERS:
        if marker not in addon_surface:
            fail(f"família de addon Kodi não reconhecida: {marker}", failures)

    required_regression_tests = (
        ROOT / "tools" / "test_embedded_context_isolation.py",
        ROOT
        / "test"
        / "core"
        / "repositories"
        / "repository_kodi_type_coverage_test.dart",
    )
    for test in required_regression_tests:
        if not test.is_file():
            fail(f"teste de regressão ausente: {test.relative_to(ROOT)}", failures)

    if failures:
        print(f"[AddKo] Auditoria Kodi Omega: {len(failures)} falha(s).")
        return 1

    print(
        "[AddKo] Auditoria Kodi Omega: OK — "
        f"{len(PYTHON_MODULES)} módulos Python, "
        f"{len(BINARY_CAPABILITIES)} capacidades ABI e "
        f"{len(ADDON_EXTENSION_MARKERS)} famílias/marcadores de addon cobertos."
    )
    print(
        "[AddKo] Nota: cobertura estrutural não significa que todos os hosts "
        "binários do Kodi já estejam funcionais; consulte KODI_COMPATIBILITY_MATRIX.md."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
