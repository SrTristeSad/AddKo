@echo off
setlocal
cd /d "%~dp0"
title AddKo - Testes

echo Preparando Lua oficial...
python tools\fetch_lua.py || goto :failed

echo.
echo Instalando dependencias Flutter...
flutter pub get || goto :failed

echo.
echo Analisando Dart...
flutter analyze || goto :failed

echo.
echo Executando testes...
flutter test || goto :failed

echo.
echo TESTES CONCLUIDOS.
goto :end

:failed
echo.
echo ERRO: os testes falharam. Veja a mensagem acima.

:end
echo.
pause
endlocal
