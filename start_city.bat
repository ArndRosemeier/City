@echo off
REM City — voxel district POC (Voxel Tools / godot_voxel).
REM Requires Godot 4.6 + Voxel Tools module (not stock Godot).

setlocal
set "ROOT=%~dp0"

if defined GODOT (
    set "GODOT_EXE=%GODOT%"
) else if exist "%ROOT%tools\godot\Godot_v4.6-voxel_win64.exe" (
    set "GODOT_EXE=%ROOT%tools\godot\Godot_v4.6-voxel_win64.exe"
) else if exist "%ROOT%tools\godot\Godot_v4.6-stable_win64.exe" (
    set "GODOT_EXE=%ROOT%tools\godot\Godot_v4.6-stable_win64.exe"
) else if exist "C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe" (
    set "GODOT_EXE=C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe"
) else (
    echo ERROR: Voxel Tools Godot not found.
    echo Download Godot 4.6 + Voxel Tools 1.6 into tools\godot\Godot_v4.6-voxel_win64.exe
    echo Or set GODOT to that executable.
    pause
    exit /b 1
)

if not exist "%ROOT%project.godot" (
    echo ERROR: project.godot not found in "%ROOT%"
    pause
    exit /b 1
)

echo Starting voxel city POC (godot_voxel, FPS walk, ~392x280m district)...
echo   WASD walk   Mouse look   Wheel zoom   LMB dig   R autorun   Esc quit
echo   Sidewalks/curbs, traffic, street lights. Towers up to 100m.
echo   Engine: %GODOT_EXE%
echo.

start "City Voxel" /MAX "%GODOT_EXE%" --path "%ROOT%." res://scenes/city_poc.tscn --maximized
endlocal
