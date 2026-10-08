@echo off
setlocal
cd /d "%~dp0"
call tools\build_android.bat
exit /b %ERRORLEVEL%
