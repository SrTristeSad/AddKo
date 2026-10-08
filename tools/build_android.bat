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
if exist "dist\AddKo-arm64-debug.apk" del /Q "dist\AddKo-arm64-debug.apk"

echo [AddKo] Limpando build anterior para nao reutilizar codigo antigo...
call flutter clean || exit /b 1

echo [AddKo] Baixando dependencias Flutter...
call flutter pub get || exit /b 1

echo [AddKo] Verificando o codigo antes do build...
call flutter analyze --no-fatal-infos --no-fatal-warnings || exit /b 1

echo [AddKo] Executando testes de regressao...
call flutter test || exit /b 1

echo [AddKo] Preparando CPython Android ARM64 verificado por SHA-256...
python tools\android\fetch_python_runtime.py --abi arm64-v8a --output android\app\build\addko-python-runtime || exit /b 1

set "PYTHON=python"
echo [AddKo] Gerando APK ARM64...
call flutter build apk --debug --target-platform android-arm64 || exit /b 1

set "APK=build\app\outputs\flutter-apk\app-debug.apk"
if not exist "%APK%" (
  echo [ERRO] O APK nao foi gerado em %APK%.
  exit /b 1
)

copy /Y "%APK%" "dist\AddKo-arm64-debug.apk" >nul || exit /b 1

echo.
echo [OK] Analise, testes e build concluidos.
echo APK: %CD%\dist\AddKo-arm64-debug.apk
exit /b 0
