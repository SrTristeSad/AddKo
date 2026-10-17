@echo off
setlocal
cd /d "%~dp0"
title AddKo - Exemplo Video por Torrent

echo ========================================
echo    Criar addon Video por Torrent
echo ========================================
echo.
where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\build_torrent_video_example.py
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo ERRO: Python 3 nao foi encontrado.
    goto :end
  )
  python tools\build_torrent_video_example.py
)
if errorlevel 1 goto :end

echo.
echo Pacote criado: dist\VideoTorrent-0.1.1.addko
:end
echo.
pause
endlocal
