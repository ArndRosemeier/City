@echo off
REM City — procedural crowd walk demo (MakeHuman pedestrians).

setlocal
set "ROOT=%~dp0"

if defined GODOT (
    set "GODOT_EXE=%GODOT%"
) else if exist "%ROOT%tools\godot\Godot_v4.6-stable_win64.exe" (
    set "GODOT_EXE=%ROOT%tools\godot\Godot_v4.6-stable_win64.exe"
) else if exist "C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe" (
    set "GODOT_EXE=C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe"
) else (
    echo ERROR: Godot 4.6 not found.
    pause
    exit /b 1
)

echo Starting crowd walk demo...
start "City Crowd" /MAX "%GODOT_EXE%" --path "%ROOT%." res://scenes/main.tscn --maximized
endlocal
