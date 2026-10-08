@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo AddKo - Build Android local
echo ============================================================
echo.

call tools\build_android.bat
set "BUILD_EXIT=%ERRORLEVEL%"

echo.
echo ============================================================
if "%BUILD_EXIT%"=="0" (
  if exist "dist\AddKo-arm64-debug.apk" (
    echo [OK] BUILD FINALIZADO COM SUCESSO.
    echo APK: %CD%\dist\AddKo-arm64-debug.apk
  ) else (
    echo [ERRO] O script terminou com codigo 0, mas o APK nao foi encontrado.
    echo Esperado: %CD%\dist\AddKo-arm64-debug.apk
    set "BUILD_EXIT=2"
  )
) else (
  echo [ERRO] O build falhou com codigo %BUILD_EXIT%.
  echo Veja acima a primeira mensagem de erro.
)
echo ============================================================
echo.
echo Esta janela vai permanecer aberta para voce poder copiar o erro.
pause
exit /b %BUILD_EXIT%
