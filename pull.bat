@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pull.ps1" %*
exit /b %ERRORLEVEL%
