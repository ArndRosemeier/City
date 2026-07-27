@echo off
REM Eccentri City — canonical player / developer launcher.
REM Ensures Godot 4.6 + Voxel Tools, requires city_voxel.dll, imports on first run.

setlocal EnableExtensions
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "GODOT_NAME=Godot_v4.6-voxel_win64.exe"
set "GODOT_EXE=%ROOT%\tools\godot\%GODOT_NAME%"

if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"

if not exist "%GODOT_EXE%" (
    if not exist "%ROOT%\tools\ensure_city_deps.ps1" (
        echo ERROR: Engine missing and tools\ensure_city_deps.ps1 not found.
        echo Place %GODOT_NAME% in tools\godot\ or restore ensure_city_deps.ps1.
        pause
        exit /b 1
    )
    echo.
    echo Engine missing - downloading Godot 4.6 + Voxel Tools (~80 MB)...
    echo Internet required for this first-time step.
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%"
    if errorlevel 1 (
        echo ERROR: Could not download the Godot voxel engine.
        pause
        exit /b 1
    )
)
if not exist "%GODOT_EXE%" (
    if exist "%ROOT%\tools\godot\%GODOT_NAME%" set "GODOT_EXE=%ROOT%\tools\godot\%GODOT_NAME%"
)
if not exist "%GODOT_EXE%" (
    echo ERROR: Engine still missing: %GODOT_EXE%
    pause
    exit /b 1
)
if not exist "%ROOT%\project.godot" (
    echo ERROR: project.godot missing in %ROOT%
    pause
    exit /b 1
)
if not exist "%ROOT%\addons\city_voxel\bin\city_voxel.dll" (
    echo ERROR: addons\city_voxel\bin\city_voxel.dll missing.
    echo This DLL is required. Rebuild with tools\build_city_voxel.ps1 or restore from git.
    pause
    exit /b 1
)

dir /b "%ROOT%\.godot\global_script_class_cache.cfg" >nul 2>&1
if errorlevel 1 goto do_import
dir /b "%ROOT%\.godot\imported" >nul 2>&1
if errorlevel 1 goto do_import
goto launch

:do_import
echo.
echo First-time asset import - this can take several minutes. Please wait...
echo.
"%GODOT_EXE%" --headless --path "%ROOT%" --import
if exist "%ROOT%\tools\check_godot_import_artifacts.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_godot_import_artifacts.ps1" -InstallDir "%ROOT%"
    if errorlevel 1 (
        echo ERROR: Import finished but godot cache / imported assets are missing.
        pause
        exit /b 1
    )
) else (
    dir /b "%ROOT%\.godot\global_script_class_cache.cfg" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Import finished but the godot class cache is still missing.
        pause
        exit /b 1
    )
    dir /b "%ROOT%\.godot\imported" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Import finished but the godot imported folder is still missing.
        pause
        exit /b 1
    )
)
echo.

:launch
start "Eccentri City" /MAX "%GODOT_EXE%" --path "%ROOT%" res://scenes/city_poc.tscn --maximized
endlocal
exit /b 0
