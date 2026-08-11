@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish_update.ps1" %*
exit /b %ERRORLEVEL%
