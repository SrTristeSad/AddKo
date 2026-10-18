@echo off
setlocal
cd /d "%~dp0"
title AddKo - Build Android Lua

echo ========================================
echo   AddKo - Flutter + Lua Android build
echo ========================================
echo.

where python >nul 2>nul || goto :missing_python
where flutter >nul 2>nul || goto :missing_flutter

python tools\fetch_lua.py || goto :failed
flutter pub get || goto :failed
flutter analyze || goto :failed
flutter test || goto :failed
flutter build apk --release --target-platform android-arm64 || goto :failed

echo.
echo BUILD CONCLUIDO.
echo APK: build\app\outputs\flutter-apk\app-release.apk
goto :end

:missing_python
echo ERRO: Python nao foi encontrado no PATH.
goto :end

:missing_flutter
echo ERRO: Flutter nao foi encontrado no PATH.
goto :end

:failed
echo.
echo ERRO: o build falhou. Veja a mensagem acima.

:end
echo.
pause
endlocal
