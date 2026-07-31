@echo off
REM Opens the Windows Smart App Control settings page.
REM A script cannot turn SAC Off — only this dialog can.
setlocal
set "ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%open_smart_app_control.ps1" %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" pause
exit /b %ERR%
