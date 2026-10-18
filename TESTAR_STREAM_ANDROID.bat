@echo off
setlocal
cd /d "%~dp0"
title AddKo - Teste Streaming Android

echo ==========================================
echo   AddKo: MP4 + Range + Player Android
echo ==========================================
echo.

where py >nul 2>nul
if not errorlevel 1 (
    set "PY=py -3"
) else (
    where python >nul 2>nul
    if errorlevel 1 goto :missing_python
    set "PY=python"
)

echo [1/4] Testando servidor HTTP e suporte a Range...
%PY% tools\test_stream_smoke_server.py
if errorlevel 1 goto :failed

echo.
echo [2/4] Criando os dois pacotes .addko...
%PY% tools\build_stream_smoke_examples.py
if errorlevel 1 goto :failed

echo.
echo [3/4] Preparando ADB USB reverse...
where adb >nul 2>nul
if errorlevel 1 goto :missing_adb

adb devices
adb reverse tcp:8765 tcp:8765
if errorlevel 1 goto :failed
adb reverse --list

echo.
echo [4/4] Iniciando servidor local...
echo.
echo Instale no AddKo do celular:
echo    dist\MediaSource-1.0.0.addko
echo    dist\MediaBridge-1.0.0.addko
echo.
echo Entre no Media Bridge, toque Reproduzir e use Diagnosticar conexao.
echo Durante o teste, nao feche esta janela.
echo Use CTRL+C para encerrar o servidor.
echo.

if "%~1"=="" (
    %PY% tools\stream_smoke_server.py
) else (
    %PY% tools\stream_smoke_server.py "%~1"
)
goto :cleanup

:missing_python
echo ERRO: Python 3 nao esta disponivel no PATH.
goto :end

:missing_adb
echo ERRO: adb nao esta no PATH. Instale Android platform-tools.
echo Gere os pacotes acima, mas a conexao USB nao foi configurada.
goto :end

:failed
echo ERRO: confira a mensagem acima.

:cleanup
adb reverse --remove tcp:8765 >nul 2>nul

:end
echo.
pause
endlocal
