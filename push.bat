@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push.ps1" %*
exit /b %ERRORLEVEL%
