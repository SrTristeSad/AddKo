from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any

from addko_bridge import special_path


def translatePath(path: str) -> str:
    return special_path(path)


def exists(path: str) -> bool:
    return Path(translatePath(path)).exists()


def mkdir(path: str) -> bool:
    try:
        Path(translatePath(path)).mkdir()
        return True
    except OSError:
        return False


def mkdirs(path: str) -> bool:
    try:
        Path(translatePath(path)).mkdir(parents=True, exist_ok=True)
        return True
    except OSError:
        return False


def rmdir(path: str, force: bool = False) -> bool:
    target = Path(translatePath(path))
    try:
        if force:
            shutil.rmtree(target)
        else:
            target.rmdir()
        return True
    except OSError:
        return False


def delete(path: str) -> bool:
    try:
        Path(translatePath(path)).unlink()
        return True
    except OSError:
        return False


def rename(fileName: str, newFileName: str) -> bool:
    try:
        source = Path(translatePath(fileName))
        target = Path(translatePath(newFileName))
        target.parent.mkdir(parents=True, exist_ok=True)
        source.replace(target)
        return True
    except OSError:
        return False


def copy(source: str, destination: str) -> bool:
    try:
        src = Path(translatePath(source))
        dst = Path(translatePath(destination))
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        return True
    except OSError:
        return False


def listdir(path: str) -> tuple[list[str], list[str]]:
    root = Path(translatePath(path))
    directories: list[str] = []
    files: list[str] = []
    try:
        for child in root.iterdir():
            if child.is_dir():
                directories.append(child.name)
            else:
                files.append(child.name)
    except OSError:
        pass
    return directories, files


def validatePath(path: str) -> str:
    return os.path.normpath(translatePath(path))


class File:
    def __init__(self, filepath: str, mode: str = "r") -> None:
        self.filepath = translatePath(filepath)
        self.mode = mode or "r"
        target = Path(self.filepath)
        if any(flag in self.mode for flag in ("w", "a", "+")):
            target.parent.mkdir(parents=True, exist_ok=True)
        self._handle = open(target, self.mode + ("b" if "b" not in self.mode else ""))

    def read(self, numBytes: int = 0) -> bytes:
        if numBytes and numBytes > 0:
            return self._handle.read(numBytes)
        return self._handle.read()

    def readBytes(self, numBytes: int = 0) -> bytes:
        return self.read(numBytes)

    def write(self, buffer: Any) -> bool:
        try:
            if isinstance(buffer, str):
                buffer = buffer.encode("utf-8")
            self._handle.write(buffer)
            return True
        except OSError:
            return False

    def size(self) -> int:
        try:
            return os.path.getsize(self.filepath)
        except OSError:
            return 0

    def seek(self, seekBytes: int, iWhence: int = 0) -> int:
        return self._handle.seek(seekBytes, iWhence)

    def close(self) -> None:
        if not self._handle.closed:
            self._handle.close()

    def __enter__(self) -> "File":
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.close()


class Stat:
    def __init__(self, path: str) -> None:
        self._path = translatePath(path)
        self._stat = os.stat(self._path)

    def st_size(self) -> int:
        return self._stat.st_size

    def st_mode(self) -> int:
        return self._stat.st_mode

    def st_mtime(self) -> int:
        return int(self._stat.st_mtime)

    def st_ctime(self) -> int:
        return int(self._stat.st_ctime)

    def st_atime(self) -> int:
        return int(self._stat.st_atime)
