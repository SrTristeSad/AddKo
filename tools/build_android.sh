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

export ADDKO_ANDROID_ABIS="${ADDKO_ANDROID_ABIS:-arm64-v8a}"
if [[ "$ADDKO_ANDROID_ABIS" != "arm64-v8a" ]]; then
  echo "[ERRO] tools/build_android.sh é o build leve de teste ARM64. ADDKO_ANDROID_ABIS=$ADDKO_ANDROID_ABIS" >&2
  echo "Use o pipeline multi-ABI quando quiser gerar pacotes de desenvolvimento para outra arquitetura." >&2
  exit 1
fi

mkdir -p dist
flutter pub get
python3 tools/audit_kodi_omega_compat.py
python3 tools/test_kodi_shims.py
python3 tools/test_embedded_context_isolation.py
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
python3 tools/android/fetch_python_runtime.py --abi arm64-v8a --output android/app/build/addko-python-runtime
PYTHON=python3 flutter build apk --debug --target-platform android-arm64

apk='build/app/outputs/flutter-apk/app-debug.apk'
[[ -f "$apk" ]] || {
  echo "[ERRO] APK ARM64 não foi gerado em $apk" >&2
  exit 1
}
python3 tools/android/verify_addko_apk.py "$apk" --abi arm64-v8a --strict-abi
cp -f "$apk" dist/AddKo-arm64-debug.apk

echo "[OK] ARM64: $ROOT/dist/AddKo-arm64-debug.apk"
