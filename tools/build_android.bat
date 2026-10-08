@echo off
setlocal EnableExtensions
cd /d "%~dp0\.."

echo [AddKo] Verificando Flutter...
where flutter >nul 2>nul || (
  echo [ERRO] Flutter nao foi encontrado no PATH.
  echo Instale o Flutter e abra um novo terminal antes de tentar novamente.
  exit /b 1
)

echo [AddKo] Verificando Python...
where python >nul 2>nul || (
  echo [ERRO] Python 3 nao foi encontrado no PATH.
  echo O build usa Python para preparar o runtime CPython do Android.
  exit /b 1
)
python --version || exit /b 1

if not exist dist mkdir dist

echo [AddKo] Baixando dependencias Flutter...
call flutter pub get || exit /b 1

echo [AddKo] Preparando CPython Android verificado por SHA-256...
python tools\android\fetch_python_runtime.py --output android\app\build\addko-python-runtime || exit /b 1

set "PYTHON=python"
echo [AddKo] Gerando APKs por arquitetura...
call flutter build apk --debug --split-per-abi || exit /b 1

set "ARM64=build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk"
set "X64=build\app\outputs\flutter-apk\app-x86_64-debug.apk"

if not exist "%ARM64%" (
  echo [ERRO] O APK ARM64 nao foi gerado em %ARM64%.
  exit /b 1
)

copy /Y "%ARM64%" "dist\AddKo-arm64-debug.apk" >nul || exit /b 1
if exist "%X64%" copy /Y "%X64%" "dist\AddKo-x86_64-debug.apk" >nul

echo.
echo [OK] Build concluido.
echo ARM64: %CD%\dist\AddKo-arm64-debug.apk
if exist "dist\AddKo-x86_64-debug.apk" echo x86_64: %CD%\dist\AddKo-x86_64-debug.apk
exit /b 0
