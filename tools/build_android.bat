@echo off
setlocal
cd /d "%~dp0.."
python tools\android\fetch_kodi_runtime.py || exit /b 1
call flutter pub get || exit /b 1
python -m unittest discover -s tests -v || exit /b 1
call flutter analyze --no-fatal-infos --no-fatal-warnings || exit /b 1
call flutter test || exit /b 1
call flutter build apk --release --target-platform android-arm64 --no-pub || exit /b 1
python tools\android\verify_addko_apk.py build\app\outputs\flutter-apk\app-release.apk --abi arm64-v8a --strict-abi || exit /b 1
if not exist dist mkdir dist
copy /Y build\app\outputs\flutter-apk\app-release.apk dist\AddKo-26-arm64.apk >nul || exit /b 1
echo [OK] dist\AddKo-26-arm64.apk
