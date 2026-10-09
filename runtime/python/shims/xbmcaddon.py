from __future__ import annotations

import ast
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from addko_bridge import context, emit


class Addon:
    def __init__(self, id: str | None = None) -> None:
        ctx = context()
        self._id = id or str(ctx["addon_id"])
        self._addons_root = Path(ctx["addons_root"])
        self._path = self._addons_root / self._id
        self._profile = Path(ctx["addon_data_root"]) / self._id
        self._profile.mkdir(parents=True, exist_ok=True)
        self._manifest = self._load_manifest()
        self._settings_file = self._profile / "settings.json"
        self._localized_strings: dict[int, str] | None = None

    def _load_manifest(self) -> ET.Element:
        source = self._path / "addon.xml"
        if not source.is_file():
            raise RuntimeError(f"Addon manifest not found: {source}")
        return ET.parse(source).getroot()

    def getAddonInfo(self, key: str) -> str:
        key = key.lower()
        metadata = None
        for extension in self._manifest.findall("extension"):
            if extension.attrib.get("point") == "xbmc.addon.metadata":
                metadata = extension
                break

        values = {
            "id": self._manifest.attrib.get("id", self._id),
            "name": self._manifest.attrib.get("name", self._id),
            "version": self._manifest.attrib.get("version", ""),
            "author": self._manifest.attrib.get("provider-name", ""),
            "path": str(self._path),
            "profile": str(self._profile),
            "icon": str(self._path / self._asset_path(metadata, "icon", "icon.png")),
            "fanart": str(self._path / self._asset_path(metadata, "fanart", "fanart.jpg")),
            "summary": self._metadata_text(metadata, "summary"),
            "description": self._metadata_text(metadata, "description"),
            "disclaimer": self._metadata_text(metadata, "disclaimer"),
            "changelog": self._metadata_text(metadata, "news"),
            "type": self._primary_type(),
        }
        return values.get(key, "")

    def getLocalizedString(self, id: int) -> str:
        if self._localized_strings is None:
            self._localized_strings = self._load_localized_strings()
        value = self._localized_strings.get(int(id))
        if value is not None:
            return value
        emit("xbmcaddon.getLocalizedString", addon_id=self._id, string_id=id)
        return str(id)

    def getSetting(self, id: str) -> str:
        values = self._load_settings()
        if id in values:
            return str(values[id])
        default = self._setting_default(id)
        return default or ""

    def getSettingString(self, id: str) -> str:
        return self.getSetting(id)

    def getSettingBool(self, id: str) -> bool:
        return self.getSetting(id).strip().lower() in {"true", "1", "yes", "on"}

    def getSettingInt(self, id: str) -> int:
        try:
            return int(self.getSetting(id))
        except (TypeError, ValueError):
            return 0

    def getSettingNumber(self, id: str) -> float:
        try:
            return float(self.getSetting(id))
        except (TypeError, ValueError):
            return 0.0

    def setSetting(self, id: str, value: Any) -> None:
        values = self._load_settings()
        values[str(id)] = str(value)
        self._save_settings(values)
        emit("xbmcaddon.setSetting", addon_id=self._id, setting_id=id, value=str(value))

    def setSettingString(self, id: str, value: str) -> bool:
        self.setSetting(id, value)
        return True

    def setSettingBool(self, id: str, value: bool) -> bool:
        self.setSetting(id, "true" if value else "false")
        return True

    def setSettingInt(self, id: str, value: int) -> bool:
        self.setSetting(id, str(value))
        return True

    def setSettingNumber(self, id: str, value: float) -> bool:
        self.setSetting(id, str(value))
        return True

    def openSettings(self) -> None:
        emit("xbmcaddon.openSettings", addon_id=self._id)

    def _load_settings(self) -> dict[str, Any]:
        if not self._settings_file.is_file():
            return {}
        try:
            with self._settings_file.open("r", encoding="utf-8") as handle:
                value = json.load(handle)
                return value if isinstance(value, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    def _save_settings(self, values: dict[str, Any]) -> None:
        self._profile.mkdir(parents=True, exist_ok=True)
        temporary = self._settings_file.with_suffix(".tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(values, handle, ensure_ascii=False, indent=2)
        temporary.replace(self._settings_file)

    def _setting_default(self, setting_id: str) -> str | None:
        candidates = [
            self._path / "resources" / "settings.xml",
            self._path / "resources" / "settings" / "settings.xml",
        ]
        for source in candidates:
            if not source.is_file():
                continue
            try:
                root = ET.parse(source).getroot()
            except ET.ParseError:
                continue
            for setting in root.iter("setting"):
                if setting.attrib.get("id") != setting_id:
                    continue
                if "default" in setting.attrib:
                    return setting.attrib["default"]
                default = setting.find("default")
                if default is not None and default.text is not None:
                    return default.text
        return None

    def _load_localized_strings(self) -> dict[int, str]:
        language_root = self._path / "resources" / "language"
        if not language_root.is_dir():
            return {}

        preferred = [
            "resource.language.pt_br",
            "Portuguese (Brazil)",
            "Portuguese",
            "resource.language.en_gb",
            "English",
        ]
        directories = {child.name.lower(): child for child in language_root.iterdir() if child.is_dir()}
        ordered: list[Path] = []
        for name in preferred:
            match = directories.get(name.lower())
            if match is not None and match not in ordered:
                ordered.append(match)
        for child in directories.values():
            if child not in ordered:
                ordered.append(child)

        merged: dict[int, str] = {}
        for directory in reversed(ordered):
            po = directory / "strings.po"
            xml = directory / "strings.xml"
            if po.is_file():
                merged.update(self._parse_po(po))
            elif xml.is_file():
                merged.update(self._parse_legacy_strings_xml(xml))
        return merged

    def _parse_po(self, source: Path) -> dict[int, str]:
        try:
            lines = source.read_text(encoding="utf-8-sig").splitlines()
        except OSError:
            return {}

        result: dict[int, str] = {}
        context_id: int | None = None
        msgid_parts: list[str] = []
        msgstr_parts: list[str] = []
        field: str | None = None

        def finish() -> None:
            nonlocal context_id, msgid_parts, msgstr_parts, field
            if context_id is not None:
                translated = "".join(msgstr_parts)
                fallback = "".join(msgid_parts)
                value = translated if translated else fallback
                if value:
                    result[context_id] = value
            context_id = None
            msgid_parts = []
            msgstr_parts = []
            field = None

        for raw in [*lines, ""]:
            line = raw.strip()
            if not line:
                finish()
                continue
            if line.startswith("#") and not line.startswith("msgctxt"):
                continue
            if line.startswith("msgctxt "):
                finish()
                value = self._po_value(line[len("msgctxt ") :])
                if value.startswith("#"):
                    try:
                        context_id = int(value[1:])
                    except ValueError:
                        context_id = None
                field = "context"
            elif line.startswith("msgid "):
                msgid_parts = [self._po_value(line[len("msgid ") :])]
                field = "msgid"
            elif line.startswith("msgstr "):
                msgstr_parts = [self._po_value(line[len("msgstr ") :])]
                field = "msgstr"
            elif line.startswith('"'):
                value = self._po_value(line)
                if field == "msgid":
                    msgid_parts.append(value)
                elif field == "msgstr":
                    msgstr_parts.append(value)
        return result

    def _po_value(self, value: str) -> str:
        try:
            decoded = ast.literal_eval(value)
            return decoded if isinstance(decoded, str) else str(decoded)
        except (SyntaxError, ValueError):
            return value.strip().strip('"')

    def _parse_legacy_strings_xml(self, source: Path) -> dict[int, str]:
        try:
            root = ET.parse(source).getroot()
        except (OSError, ET.ParseError):
            return {}
        result: dict[int, str] = {}
        for node in root.iter("string"):
            raw_id = node.attrib.get("id")
            if raw_id is None:
                continue
            try:
                string_id = int(raw_id)
            except ValueError:
                continue
            if node.text:
                result[string_id] = node.text
        return result

    def _metadata_text(self, metadata: ET.Element | None, name: str) -> str:
        if metadata is None:
            return ""
        values = metadata.findall(name)
        if not values:
            return ""
        for value in values:
            lang = value.attrib.get("lang", "").lower()
            if lang in {"en_gb", "en-us", "pt_br", "pt-br", ""} and value.text:
                return value.text.strip()
        return (values[0].text or "").strip()

    def _asset_path(self, metadata: ET.Element | None, name: str, fallback: str) -> str:
        if metadata is None:
            return fallback
        assets = metadata.find("assets")
        if assets is None:
            return fallback
        node = assets.find(name)
        if node is None or not node.text:
            return fallback
        return node.text.strip()

    def _primary_type(self) -> str:
        for extension in self._manifest.findall("extension"):
            point = extension.attrib.get("point", "")
            if point:
                return point
        return ""
