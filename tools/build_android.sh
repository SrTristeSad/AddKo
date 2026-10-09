#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/android/fetch_kodi_runtime.py
flutter pub get
python3 -m unittest discover -s tests -v
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --target-platform android-arm64 --no-pub
python3 tools/android/verify_addko_apk.py build/app/outputs/flutter-apk/app-release.apk --abi arm64-v8a --strict-abi
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/AddKo-26-arm64.apk
