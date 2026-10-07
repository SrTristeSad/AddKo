from __future__ import annotations

import itertools
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Iterable

from addko_bridge import emit, request

_control_ids = itertools.count(10000)


class Action:
    def __init__(self, action_id: int = 0, button_code: int = 0, amount1: float = 0.0, amount2: float = 0.0) -> None:
        self._id = int(action_id)
        self._button_code = int(button_code)
        self._amount1 = float(amount1)
        self._amount2 = float(amount2)

    def getId(self) -> int:
        return self._id

    def getButtonCode(self) -> int:
        return self._button_code

    def getAmount1(self) -> float:
        return self._amount1

    def getAmount2(self) -> float:
        return self._amount2


class Control:
    control_type = "control"

    def __init__(self, x: int = 0, y: int = 0, width: int = 100, height: int = 40, control_id: int | None = None, **_: Any) -> None:
        self.id = int(control_id if control_id is not None else next(_control_ids))
        self.x = int(x)
        self.y = int(y)
        self.width = int(width)
        self.height = int(height)
        self.visible = True
        self.enabled = True
        self.label = ""
        self.label2 = ""
        self.texture = ""
        self.percent = 0.0
        self.selected = False
        self.items: list[Any] = []
        self.selected_position = 0
        self.children: list[Control] = []
        self.properties: dict[str, str] = {}

    def setVisible(self, visible: bool) -> None:
        self.visible = bool(visible)

    def setEnabled(self, enabled: bool) -> None:
        self.enabled = bool(enabled)

    def setPosition(self, x: int, y: int) -> None:
        self.x = int(x)
        self.y = int(y)

    def setWidth(self, width: int) -> None:
        self.width = int(width)

    def setHeight(self, height: int) -> None:
        self.height = int(height)

    def setLabel(self, label: str = "", *args: Any, **kwargs: Any) -> None:
        self.label = str(label)

    def getLabel(self) -> str:
        return self.label

    def setLabel2(self, label: str) -> None:
        self.label2 = str(label)

    def getLabel2(self) -> str:
        return self.label2

    def setAnimations(self, eventAttr: Iterable[Any]) -> None:
        pass

    def setNavigation(self, up: Any, down: Any, left: Any, right: Any) -> None:
        pass

    def controlUp(self, control: Any) -> None:
        pass

    def controlDown(self, control: Any) -> None:
        pass

    def controlLeft(self, control: Any) -> None:
        pass

    def controlRight(self, control: Any) -> None:
        pass

    def snapshot(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "type": self.control_type,
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
            "visible": self.visible,
            "enabled": self.enabled,
            "label": self.label,
            "label2": self.label2,
            "texture": self.texture,
            "percent": self.percent,
            "selected": self.selected,
            "selected_position": self.selected_position,
            "items": [_item_snapshot(item) for item in self.items],
            "children": [child.snapshot() for child in self.children],
            "properties": dict(self.properties),
        }


class ControlLabel(Control):
    control_type = "label"

    def __init__(self, x: int, y: int, width: int, height: int, label: str = "", *args: Any, **kwargs: Any) -> None:
        super().__init__(x, y, width, height, **kwargs)
        self.label = str(label)


class ControlButton(ControlLabel):
    control_type = "button"


class ControlEdit(ControlLabel):
    control_type = "edit"

    def setText(self, text: str) -> None:
        self.label2 = str(text)

    def getText(self) -> str:
        return self.label2


class ControlImage(Control):
    control_type = "image"

    def __init__(self, x: int, y: int, width: int, height: int, filename: str = "", *args: Any, **kwargs: Any) -> None:
        super().__init__(x, y, width, height, **kwargs)
        self.texture = str(filename)

    def setImage(self, filename: str, useCache: bool = True) -> None:
        self.texture = str(filename)


class ControlProgress(Control):
    control_type = "progress"

    def setPercent(self, percent: float) -> None:
        self.percent = max(0.0, min(100.0, float(percent)))

    def getPercent(self) -> float:
        return self.percent


class ControlRadioButton(ControlButton):
    control_type = "radiobutton"

    def setSelected(self, selected: bool) -> None:
        self.selected = bool(selected)

    def isSelected(self) -> bool:
        return self.selected


class ControlSlider(ControlProgress):
    control_type = "slider"


class ControlSpin(Control):
    control_type = "spin"


class ControlTextBox(ControlLabel):
    control_type = "textbox"

    def setText(self, text: str) -> None:
        self.label = str(text)

    def reset(self) -> None:
        self.label = ""

    def scroll(self, position: int) -> None:
        pass


class ControlGroup(Control):
    control_type = "group"


class ControlList(Control):
    control_type = "list"

    def addItem(self, item: Any, sendMessage: bool = True) -> None:
        self.items.append(item)

    def addItems(self, items: Iterable[Any]) -> None:
        self.items.extend(items)

    def selectItem(self, item: int) -> None:
        if self.items:
            self.selected_position = max(0, min(int(item), len(self.items) - 1))

    def getSelectedPosition(self) -> int:
        return self.selected_position if self.items else -1

    def getSelectedItem(self) -> Any:
        if not self.items:
            return None
        return self.items[self.selected_position]

    def size(self) -> int:
        return len(self.items)

    def reset(self) -> None:
        self.items.clear()
        self.selected_position = 0

    def removeItem(self, index: int) -> None:
        if 0 <= index < len(self.items):
            del self.items[index]
            self.selectItem(self.selected_position)


class Window:
    def __init__(self, existingWindowId: int = -1) -> None:
        self._window_id = existingWindowId if existingWindowId >= 0 else 13000
        self._controls: dict[int, Control] = {}
        self._properties: dict[str, str] = {}
        self._focus_id = -1
        self._closed = False

    def show(self) -> None:
        emit("xbmcgui.Window.show", window_id=self._window_id)

    def doModal(self) -> None:
        request("xbmcgui.Window.doModal", default=True, window_id=self._window_id)

    def close(self) -> None:
        self._closed = True
        emit("xbmcgui.Window.close", window_id=self._window_id)

    def addControl(self, control: Control) -> None:
        self._controls[control.id] = control

    def addControls(self, controls: Iterable[Control]) -> None:
        for control in controls:
            self.addControl(control)

    def removeControl(self, control: Control) -> None:
        self._controls.pop(control.id, None)

    def removeControls(self, controls: Iterable[Control]) -> None:
        for control in controls:
            self.removeControl(control)

    def getControl(self, controlId: int) -> Control:
        control_id = int(controlId)
        if control_id not in self._controls:
            raise RuntimeError(f"Control {control_id} does not exist")
        return self._controls[control_id]

    def setFocus(self, control: Control) -> None:
        self._focus_id = control.id

    def setFocusId(self, controlId: int) -> None:
        self._focus_id = int(controlId)

    def getFocus(self) -> Control:
        return self.getControl(self._focus_id)

    def getFocusId(self) -> int:
        return self._focus_id

    def setProperty(self, key: str, value: str) -> None:
        self._properties[str(key).lower()] = str(value)

    def getProperty(self, key: str) -> str:
        return self._properties.get(str(key).lower(), "")

    def clearProperty(self, key: str) -> None:
        self._properties.pop(str(key).lower(), None)

    def clearProperties(self) -> None:
        self._properties.clear()


class WindowDialog(Window):
    pass


class WindowXML(Window):
    def __init__(self, xmlFilename: str, scriptPath: str, defaultSkin: str = "Default", defaultRes: str = "720p", isMedia: bool = False) -> None:
        super().__init__()
        self.xmlFilename = str(xmlFilename)
        self.scriptPath = str(scriptPath)
        self.defaultSkin = str(defaultSkin)
        self.defaultRes = str(defaultRes)
        self.isMedia = bool(isMedia)
        self._items: list[Any] = []
        self._list_position = 0
        self._content = ""
        self._container_properties: dict[str, str] = {}
        self._xml_path = self._find_xml()
        self._design_width, self._design_height = _resolution_size(self.defaultRes)
        if self._xml_path is not None:
            self._load_controls(self._xml_path)

    def _find_xml(self) -> Path | None:
        root = Path(self.scriptPath)
        candidates = [
            root / "resources" / "skins" / self.defaultSkin / self.defaultRes / self.xmlFilename,
            root / "resources" / "skins" / self.defaultSkin / "1080i" / self.xmlFilename,
            root / "resources" / "skins" / self.defaultSkin / "720p" / self.xmlFilename,
            root / self.xmlFilename,
        ]
        for candidate in candidates:
            if candidate.is_file():
                return candidate
        skins = root / "resources" / "skins"
        if skins.is_dir():
            for candidate in skins.rglob(self.xmlFilename):
                if candidate.is_file():
                    return candidate
        return None

    def _load_controls(self, source: Path) -> None:
        try:
            root = ET.parse(source).getroot()
        except ET.ParseError:
            return
        coordinates = root.find("coordinates")
        if coordinates is not None:
            # Kodi uses resolution metadata from the skin, but many addon XML files
            # only declare coordinates implicitly through defaultRes.
            pass
        controls = root.find("controls")
        if controls is None:
            return
        for node in controls.findall("control"):
            control = _control_from_xml(node)
            if control is not None:
                self._controls[control.id] = control

    def doModal(self) -> None:
        self._closed = False
        self.onInit()
        while not self._closed:
            response = request(
                "xbmcgui.WindowXML.doModal",
                default={"action": "close"},
                title=self.getProperty("title"),
                xml_filename=self.xmlFilename,
                xml_path=str(self._xml_path) if self._xml_path else "",
                width=self._design_width,
                height=self._design_height,
                focus_id=self._focus_id,
                properties=dict(self._properties),
                controls=[control.snapshot() for control in self._controls.values()],
                list_items=[_item_snapshot(item) for item in self._items],
                list_position=self._list_position,
                content=self._content,
            )
            if not isinstance(response, dict):
                break
            action = str(response.get("action", "close"))
            if action == "click":
                control_id = int(response.get("control_id", -1))
                list_position = response.get("list_position")
                if isinstance(list_position, int):
                    self.setCurrentListPosition(list_position)
                    control = self._controls.get(control_id)
                    if isinstance(control, ControlList):
                        control.selectItem(list_position)
                self._focus_id = control_id
                self.onClick(control_id)
                continue
            if action == "action":
                self.onAction(Action(int(response.get("action_id", 0))))
                continue
            break
        self._closed = True

    def addItem(self, item: Any, position: int = 2**31 - 1) -> None:
        if position >= len(self._items):
            self._items.append(item)
        elif position <= 0:
            self._items.insert(0, item)
        else:
            self._items.insert(position, item)

    def addItems(self, items: Iterable[Any]) -> None:
        self._items.extend(items)

    def removeItem(self, position: int) -> None:
        if 0 <= position < len(self._items):
            del self._items[position]
            self.setCurrentListPosition(self._list_position)

    def getCurrentListPosition(self) -> int:
        return self._list_position if self._items else -1

    def setCurrentListPosition(self, position: int) -> None:
        if not self._items:
            self._list_position = 0
            return
        self._list_position = max(0, min(int(position), len(self._items) - 1))

    def getListItem(self, position: int) -> Any:
        return self._items[position]

    def getListSize(self) -> int:
        return len(self._items)

    def clearList(self) -> None:
        self._items.clear()
        self._list_position = 0

    def setContainerProperty(self, key: str, value: str) -> None:
        self._container_properties[str(key)] = str(value)

    def setContent(self, value: str) -> None:
        self._content = str(value)

    def getCurrentContainerId(self) -> int:
        for control in self._controls.values():
            if isinstance(control, ControlList):
                return control.id
        return -1

    def onInit(self) -> None:
        pass

    def onClick(self, controlId: int) -> None:
        pass

    def onDoubleClick(self, controlId: int) -> None:
        pass

    def onFocus(self, controlId: int) -> None:
        pass

    def onAction(self, action: Action) -> None:
        pass


class WindowXMLDialog(WindowXML):
    pass


def _resolution_size(value: str) -> tuple[int, int]:
    name = value.lower()
    if "1080" in name:
        return 1920, 1080
    if "720" in name:
        return 1280, 720
    if "ntsc" in name:
        return (720, 480)
    if "pal" in name:
        return (720, 576)
    return 1280, 720


def _text(node: ET.Element, name: str, default: str = "") -> str:
    child = node.find(name)
    return default if child is None or child.text is None else child.text.strip()


def _integer(node: ET.Element, name: str, default: int) -> int:
    value = _text(node, name, str(default))
    try:
        return int(float(value))
    except ValueError:
        return default


def _control_from_xml(node: ET.Element) -> Control | None:
    control_type = node.attrib.get("type", _text(node, "type", "")).lower()
    raw_id = node.attrib.get("id", _text(node, "id", "0"))
    try:
        control_id = int(raw_id)
    except ValueError:
        control_id = next(_control_ids)
    x = _integer(node, "posx", _integer(node, "left", 0))
    y = _integer(node, "posy", _integer(node, "top", 0))
    width = _integer(node, "width", 200)
    height = _integer(node, "height", 50)
    label = _text(node, "label")

    common = dict(x=x, y=y, width=width, height=height, control_id=control_id)
    if control_type == "label":
        control: Control = ControlLabel(label=label, **common)
    elif control_type == "button":
        control = ControlButton(label=label, **common)
    elif control_type == "edit":
        control = ControlEdit(label=label, **common)
    elif control_type in {"image", "multiimage"}:
        control = ControlImage(filename=_text(node, "texture"), **common)
    elif control_type == "list" or control_type == "panel" or control_type == "fixedlist" or control_type == "wraplist":
        control = ControlList(**common)
    elif control_type == "progress":
        control = ControlProgress(**common)
    elif control_type == "radiobutton":
        control = ControlRadioButton(label=label, **common)
    elif control_type == "slider":
        control = ControlSlider(**common)
    elif control_type == "spincontrol":
        control = ControlSpin(**common)
    elif control_type == "textbox":
        control = ControlTextBox(label=label, **common)
    elif control_type == "group":
        control = ControlGroup(**common)
        for child_node in node.findall("control"):
            child = _control_from_xml(child_node)
            if child is not None:
                control.children.append(child)
    else:
        control = Control(**common)
        control.control_type = control_type or "control"
        control.label = label

    control.visible = _text(node, "visible", "true").lower() not in {"false", "0"}
    control.enabled = _text(node, "enable", "true").lower() not in {"false", "0"}
    if isinstance(control, ControlImage):
        control.texture = _text(node, "texture", control.texture)
    return control


def _item_snapshot(item: Any) -> dict[str, Any]:
    if hasattr(item, "to_addko_dict"):
        return item.to_addko_dict()
    return {"label": str(item), "label2": "", "path": "", "art": {}, "properties": {}}
