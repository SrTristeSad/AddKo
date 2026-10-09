@echo off
setlocal EnableExtensions
cd /d "%~dp0\.."

set "APK=build\app\outputs\flutter-apk\app-debug.apk"
set "DIST_APK=dist\AddKo-arm64-debug.apk"
set "STDLIB_ZIP=android\app\build\addko-python-runtime\assets\addko_python\3.14.8\arm64-v8a\stdlib.zip"
set "ADDKO_ANDROID_ABIS=arm64-v8a"

echo [AddKo] Verificando Flutter...
where flutter >nul 2>nul || (
  echo [ERRO] Flutter nao foi encontrado no PATH.
  echo Rode flutter doctor em um Prompt de Comando.
  exit /b 1
)

echo [AddKo] Verificando Python...
where python >nul 2>nul || (
  echo [ERRO] Python 3 nao foi encontrado no PATH.
  exit /b 1
)
python --version || exit /b 1

if not exist dist mkdir dist
if exist "%DIST_APK%" del /Q "%DIST_APK%"

echo [AddKo] Limpando build anterior...
call flutter clean
if errorlevel 1 exit /b 1

echo [AddKo] Baixando dependencias Flutter...
call flutter pub get
if errorlevel 1 exit /b 1

echo [AddKo] Auditando superficie Kodi Omega...
python tools\audit_kodi_omega_compat.py
if errorlevel 1 (
  echo [ERRO] A matriz estrutural Kodi Omega esta incompleta.
  exit /b 1
)

echo [AddKo] Validando APIs Python do Kodi...
python tools\test_kodi_shims.py
if errorlevel 1 (
  echo [ERRO] A camada de compatibilidade Python/Kodi falhou no smoke test.
  exit /b 1
)

echo [AddKo] Analise estatica...
call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 (
  echo [ERRO] flutter analyze encontrou erro de compilacao.
  exit /b 1
)

echo [AddKo] Testes Flutter...
call flutter test
if errorlevel 1 (
  echo [ERRO] flutter test encontrou falhas.
  exit /b 1
)

echo [AddKo] Preparando CPython Android ARM64...
python tools\android\fetch_python_runtime.py --abi arm64-v8a --output android\app\build\addko-python-runtime
if errorlevel 1 exit /b 1

echo [AddKo] Conferindo stdlib CPython empacotada...
python tools\android\verify_staged_runtime.py "%STDLIB_ZIP%"
if errorlevel 1 exit /b 1

set "PYTHON=python"
echo [AddKo] Gerando APK ARM64...
call flutter build apk --debug --target-platform android-arm64
if errorlevel 1 (
  echo [ERRO] flutter build apk falhou.
  exit /b 1
)

if not exist "%APK%" (
  echo [ERRO] Flutter terminou sem gerar %APK%.
  echo Procurando APKs gerados...
  dir /S /B build\*.apk 2>nul
  exit /b 1
)

echo [AddKo] Verificando motor Kodi/Python dentro do APK...
python tools\android\verify_addko_apk.py "%APK%" --abi arm64-v8a --strict-abi
if errorlevel 1 (
  echo [ERRO] O APK foi gerado, mas esta incompleto ou trouxe ABI extra.
  exit /b 1
)

copy /Y "%APK%" "%DIST_APK%" >nul
if errorlevel 1 (
  echo [ERRO] Nao foi possivel copiar o APK para dist.
  exit /b 1
)

for %%F in ("%DIST_APK%") do set "APK_SIZE=%%~zF"
echo.
echo [OK] APK ARM64 gerado e verificado.
echo Arquivo: %CD%\%DIST_APK%
echo Tamanho: %APK_SIZE% bytes
exit /b 0
