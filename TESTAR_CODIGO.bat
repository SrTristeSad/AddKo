@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================================
echo AddKo - Analise e testes locais
echo ============================================================
echo.

where flutter >nul 2>nul || (
  echo [ERRO] Flutter nao foi encontrado no PATH.
  goto :finish_error
)

echo [AddKo] flutter pub get...
call flutter pub get
if errorlevel 1 goto :finish_error

echo [AddKo] flutter analyze...
call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 goto :finish_error

echo [AddKo] flutter test...
call flutter test
if errorlevel 1 goto :finish_error

echo.
echo [OK] Analise e testes concluidos.
set "RESULT=0"
goto :finish

:finish_error
echo.
echo [ERRO] Analise ou testes falharam.
set "RESULT=1"

:finish
echo.
echo Esta janela vai permanecer aberta.
pause
exit /b %RESULT%
