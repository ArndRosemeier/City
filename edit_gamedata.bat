@echo off
REM Launch the assets/gamedata.json tkinter editor.
setlocal
cd /d "%~dp0"
python tools\edit_gamedata.py %*
if errorlevel 1 pause
endlocal
