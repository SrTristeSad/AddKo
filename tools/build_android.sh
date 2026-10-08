#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v flutter >/dev/null 2>&1 || {
  echo '[ERRO] Flutter não foi encontrado no PATH.' >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo '[ERRO] Python 3 não foi encontrado no PATH.' >&2
  exit 1
}

mkdir -p dist
flutter pub get
python3 tools/android/fetch_python_runtime.py --output android/app/build/addko-python-runtime
PYTHON=python3 flutter build apk --debug --split-per-abi

arm64='build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk'
x64='build/app/outputs/flutter-apk/app-x86_64-debug.apk'
[[ -f "$arm64" ]] || {
  echo "[ERRO] APK ARM64 não foi gerado em $arm64" >&2
  exit 1
}
cp -f "$arm64" dist/AddKo-arm64-debug.apk
[[ ! -f "$x64" ]] || cp -f "$x64" dist/AddKo-x86_64-debug.apk

echo "[OK] ARM64: $ROOT/dist/AddKo-arm64-debug.apk"
[[ ! -f dist/AddKo-x86_64-debug.apk ]] || echo "[OK] x86_64: $ROOT/dist/AddKo-x86_64-debug.apk"
