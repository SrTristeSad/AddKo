@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title AddKo - Build Android ARM64

echo ============================================================
echo                AddKo - BUILD ANDROID ARM64
echo ============================================================
echo.

if not exist "pubspec.yaml" (
  echo [ERRO] pubspec.yaml nao encontrado.
  echo Execute este BAT na pasta raiz do projeto AddKo.
  goto :fail
)

where python >nul 2>&1
if errorlevel 1 (
  echo [ERRO] Python nao foi encontrado no PATH.
  echo Instale Python e marque a opcao para adicionar ao PATH.
  goto :fail
)

where flutter >nul 2>&1
if errorlevel 1 (
  echo [ERRO] Flutter nao foi encontrado no PATH.
  echo Configure o Flutter antes de executar este build.
  goto :fail
)

where java >nul 2>&1
if errorlevel 1 (
  echo [ERRO] Java nao foi encontrado no PATH.
  echo O projeto usa Java 17 ou superior.
  goto :fail
)

echo [INFO] Flutter:
call flutter --version
if errorlevel 1 goto :fail
echo.
echo [INFO] Java:
java -version
if errorlevel 1 goto :fail
echo.
echo [INFO] Python:
python --version
if errorlevel 1 goto :fail
echo.

echo [1/1] Preparando Kodi, testando e compilando AddKo...
call tools\build_android.bat
set "BUILD_EXIT=%ERRORLEVEL%"
if not "%BUILD_EXIT%"=="0" goto :build_failed

set "APK=dist\AddKo-26-arm64.apk"
if not exist "%APK%" (
  echo.
  echo [ERRO] O build terminou sem erro, mas o APK nao foi encontrado.
  echo Esperado: %CD%\%APK%
  goto :fail
)

echo.
echo ============================================================
echo [OK] BUILD FINALIZADO COM SUCESSO
echo APK: %CD%\%APK%
echo ============================================================
echo.
for %%I in ("%APK%") do echo Tamanho: %%~zI bytes
echo.
choice /C SN /N /M "Abrir a pasta do APK agora? [S/N]: "
if errorlevel 2 goto :done
explorer /select,"%CD%\%APK%"

:done
echo.
pause
exit /b 0

:build_failed
echo.
echo ============================================================
echo [ERRO] O build falhou com codigo %BUILD_EXIT%.
echo Veja acima a primeira mensagem de erro.
echo ============================================================
echo.
pause
exit /b %BUILD_EXIT%

:fail
echo.
echo ============================================================
echo [ERRO] Build cancelado.
echo ============================================================
echo.
pause
exit /b 1
