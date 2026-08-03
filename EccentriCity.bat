@echo off
REM Eccentri City - canonical player / developer launcher.
REM Ensures Godot 4.6 + Voxel Tools, KataGo Human-SL net, requires city_voxel.dll,
REM imports on first run.

setlocal EnableExtensions
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "GODOT_NAME=Godot_v4.6-voxel_win64.exe"
set "GODOT_EXE=%ROOT%\tools\godot\%GODOT_NAME%"

if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"

if not exist "%GODOT_EXE%" goto need_engine
goto have_engine

:need_engine
if not exist "%ROOT%\tools\ensure_city_deps.ps1" (
    echo ERROR: Engine missing and tools\ensure_city_deps.ps1 not found.
    echo Place %GODOT_NAME% in tools\godot\ or restore ensure_city_deps.ps1.
    pause
    exit /b 1
)
echo.
echo Engine missing - downloading Godot 4.6 + Voxel Tools ~80 MB...
echo Internet required for this first-time step.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%"
if errorlevel 1 (
    echo ERROR: Could not download the Godot voxel engine.
    pause
    exit /b 1
)

:have_engine
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

REM Smart App Control (Windows 11) blocks unsigned city_voxel.dll when set to On.
if not exist "%ROOT%\tools\open_smart_app_control.ps1" goto after_sac_check
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\open_smart_app_control.ps1" -CheckOnly >nul
if errorlevel 2 goto sac_warn
goto after_sac_check

:sac_warn
echo.
echo WARNING: Windows Smart App Control is On.
echo.
echo Eccentri City needs city_voxel.dll ^(unsigned native code^). With Smart App
echo Control set to On, Windows often blocks that DLL and the game will not run
echo ^(missing native types / black screen / instant script errors^).
echo.
echo You can turn Smart App Control Off in Windows Security. Microsoft usually
echo will not let you turn it back On without resetting the PC.
echo.
choice /C YN /N /M "Open Smart App Control settings now? [Y/N] "
if errorlevel 2 goto after_sac_check
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\open_smart_app_control.ps1" -Force
echo.
echo Set Smart App Control to Off, then press any key to continue launching...
pause >nul
echo.

:after_sac_check

REM Gaming / Go uses the Human-SL net (gitignored; ~95 MB first download).
if exist "%ROOT%\tools\katago\b18c384nbt-humanv0.bin.gz" goto after_katago
if not exist "%ROOT%\tools\ensure_katago.ps1" (
    echo WARNING: tools\ensure_katago.ps1 missing - Go AI will not work until the Human-SL net is present.
    goto after_katago
)
echo.
echo Downloading KataGo Human-SL model for Go (~95 MB)...
echo Internet required for this first-time step. Later launches skip this.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_katago.ps1" -Root "%ROOT%" -HumanOnly
if errorlevel 1 (
    echo WARNING: Could not download the KataGo Human-SL model.
    echo Go AI will fail until you run: powershell -File tools\ensure_katago.ps1 -HumanOnly
    echo.
) else if not exist "%ROOT%\tools\katago\b18c384nbt-humanv0.bin.gz" (
    echo WARNING: KataGo ensure finished but tools\katago\b18c384nbt-humanv0.bin.gz is still missing.
    echo.
)

:after_katago

REM Do not use cmd if-exist/dir on paths containing a .godot segment.
if not exist "%ROOT%\tools\check_godot_import_artifacts.ps1" goto do_import
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_godot_import_artifacts.ps1" -InstallDir "%ROOT%" -Attempts 1 -DelayMs 0 >nul
if errorlevel 1 goto do_import
goto launch

:do_import
echo.
echo First-time asset import - this can take several minutes. Please wait...
echo.
"%GODOT_EXE%" --headless --path "%ROOT%" --import
if not exist "%ROOT%\tools\check_godot_import_artifacts.ps1" (
    echo ERROR: tools\check_godot_import_artifacts.ps1 missing; cannot verify import.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_godot_import_artifacts.ps1" -InstallDir "%ROOT%"
if errorlevel 1 (
    echo ERROR: Import finished but godot cache / imported assets are missing.
    pause
    exit /b 1
)
echo.

:launch
start "Eccentri City" /MAX "%GODOT_EXE%" --path "%ROOT%" res://scenes/city_poc.tscn --maximized
endlocal
exit /b 0

