#!/usr/bin/env python3
"""Download and stage the official CPython Android embeddable runtime for AddKo.

The generated directory is consumed by android/app/build.gradle.kts and is not
committed. Downloads are pinned by SHA-256 and cached under .cache/addko-python.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
import urllib.request
import zipfile
from pathlib import Path

PYTHON_VERSION = "3.14.8"
PYTHON_MINOR = "3.14"
BASE_URL = f"https://www.python.org/ftp/python/{PYTHON_VERSION}"
CPYTHON_RAW_BASE = f"https://raw.githubusercontent.com/python/cpython/v{PYTHON_VERSION}/Lib"

RUNTIMES = {
    "arm64-v8a": {
        "triplet": "aarch64-linux-android",
        "sha256": "11324313957da3736f44e90257304d288864321a4dd376ed0cc35a54eacf9a33",
    },
    "x86_64": {
        "triplet": "x86_64-linux-android",
        "sha256": "58eb3b2d76ef57e076985a0a6b093cf08906d65ea4ab78cccc6d894d4250c972",
    },
}

REQUIRED_STDLIB_FILES = (
    "zipfile/_path/__init__.py",
    "zipfile/_path/glob.py",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path, expected_sha256: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and sha256_file(destination) == expected_sha256:
        print(f"[AddKo] cache hit: {destination.name}")
        return

    temporary = destination.with_suffix(destination.suffix + ".part")
    temporary.unlink(missing_ok=True)
    print(f"[AddKo] downloading {url}")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "AddKo-build/0.1 (+https://github.com/SrTristeSad/AddKo)"},
    )
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)

    actual = sha256_file(temporary)
    if actual != expected_sha256:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(
            f"SHA-256 mismatch for {destination.name}: expected {expected_sha256}, got {actual}"
        )
    temporary.replace(destination)


def download_text(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "AddKo-build/0.1 (+https://github.com/SrTristeSad/AddKo)"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    if not data or b"404: Not Found" in data[:64]:
        raise RuntimeError(f"Failed to restore CPython stdlib file from {url}")
    destination.write_bytes(data)


def safe_extract(archive: Path, destination: Path) -> None:
    marker = destination / ".addko-extracted"
    if marker.exists():
        return

    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    root = destination.resolve()

    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            target = (destination / member.name).resolve()
            if root != target and root not in target.parents:
                raise RuntimeError(f"Unsafe path in {archive.name}: {member.name}")
        tar.extractall(destination)

    marker.write_text(PYTHON_VERSION, encoding="utf-8")


def locate_prefix(extracted: Path) -> Path:
    direct = extracted / "prefix"
    if (direct / "lib" / f"python{PYTHON_MINOR}").is_dir():
        return direct

    matches = [
        candidate
        for candidate in extracted.rglob("prefix")
        if (candidate / "lib" / f"python{PYTHON_MINOR}").is_dir()
    ]
    if len(matches) != 1:
        raise RuntimeError(f"Could not uniquely locate CPython prefix in {extracted}")
    return matches[0]


def ensure_required_stdlib(stdlib_root: Path) -> None:
    for relative in REQUIRED_STDLIB_FILES:
        target = stdlib_root / relative
        if target.is_file() and target.stat().st_size > 0:
            continue
        print(f"[AddKo] restoring missing CPython stdlib file: {relative}")
        download_text(f"{CPYTHON_RAW_BASE}/{relative}", target)

    missing = [
        relative
        for relative in REQUIRED_STDLIB_FILES
        if not (stdlib_root / relative).is_file()
    ]
    if missing:
        raise RuntimeError(
            "CPython Android runtime is missing required stdlib files: "
            + ", ".join(missing)
        )


def create_stdlib_archive(source: Path, destination: Path) -> None:
    """Package stdlib as one safe asset.

    Android's aapt ignores some asset path components beginning with '_' or '.',
    which breaks legitimate CPython modules such as zipfile/_path and many
    _*.py modules. A single ZIP asset avoids all aapt filename filtering, and
    the Android installer extracts the original names verbatim at runtime.
    """
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".zip.part")
    temporary.unlink(missing_ok=True)

    with zipfile.ZipFile(
        temporary,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=6,
        allowZip64=True,
    ) as archive:
        for path in sorted(source.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(source)
            if "__pycache__" in relative.parts or path.suffix in {".pyc", ".pyo"}:
                continue
            archive.write(path, relative.as_posix())

    temporary.replace(destination)

    with zipfile.ZipFile(destination, "r") as archive:
        names = set(archive.namelist())
        missing = [relative for relative in REQUIRED_STDLIB_FILES if relative not in names]
        if missing:
            raise RuntimeError(
                "Generated stdlib archive is missing required files: " + ", ".join(missing)
            )
        bad = archive.testzip()
        if bad is not None:
            raise RuntimeError(f"Corrupt stdlib archive entry: {bad}")


def stage_abi(prefix: Path, abi: str, output_root: Path) -> None:
    stdlib_source = prefix / "lib" / f"python{PYTHON_MINOR}"
    ensure_required_stdlib(stdlib_source)

    asset_dir = output_root / "assets" / "addko_python" / PYTHON_VERSION / abi
    if asset_dir.exists():
        shutil.rmtree(asset_dir)
    asset_dir.mkdir(parents=True, exist_ok=True)
    stdlib_archive = asset_dir / "stdlib.zip"
    create_stdlib_archive(stdlib_source, stdlib_archive)
    print(f"[AddKo] packed stdlib asset: {stdlib_archive.name} ({stdlib_archive.stat().st_size} bytes)")

    jni_dir = output_root / "jniLibs" / abi
    if jni_dir.exists():
        shutil.rmtree(jni_dir)
    jni_dir.mkdir(parents=True)

    copied = []
    for pattern in ("libpython*.so", "lib*_python.so"):
        for library in sorted((prefix / "lib").glob(pattern)):
            shutil.copy2(library, jni_dir / library.name)
            copied.append(library.name)

    if not any(name.startswith("libpython") for name in copied):
        raise RuntimeError(f"No libpython shared library found in {prefix / 'lib'}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root() / "android" / "app" / "build" / "addko-python-runtime",
        help="Generated Android assets/jniLibs root.",
    )
    parser.add_argument(
        "--abi",
        action="append",
        choices=sorted(RUNTIMES),
        help="ABI to stage. May be repeated; defaults to all supported ABIs.",
    )
    parser.add_argument("--clean", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_root = args.output.resolve()
    selected = args.abi or list(RUNTIMES)
    cache_root = repo_root() / ".cache" / "addko-python" / PYTHON_VERSION

    if args.clean and output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    staged = []
    for abi in selected:
        metadata = RUNTIMES[abi]
        triplet = metadata["triplet"]
        filename = f"python-{PYTHON_VERSION}-{triplet}.tar.gz"
        archive = cache_root / filename
        download(f"{BASE_URL}/{filename}", archive, metadata["sha256"])

        extracted = cache_root / triplet
        safe_extract(archive, extracted)
        prefix = locate_prefix(extracted)
        stage_abi(prefix, abi, output_root)
        staged.append({"abi": abi, "triplet": triplet})
        print(f"[AddKo] staged CPython {PYTHON_VERSION} for {abi}")

    manifest_dir = output_root / "assets" / "addko_python"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    (manifest_dir / "manifest.json").write_text(
        json.dumps(
            {
                "python_version": PYTHON_VERSION,
                "python_minor": PYTHON_MINOR,
                "stdlib_format": "zip",
                "abis": staged,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
