@echo off
REM Eccentri City - install a portable copy + Desktop / Start Menu shortcuts.
REM Downloads Godot 4.6 + Voxel Tools when missing. Ships city_voxel.dll from the repo.
REM
REM Usage:
REM   install_city.bat
REM   install_city.bat /D "%LOCALAPPDATA%\Programs\EccentriCity"
REM   install_city.bat /S /D "D:\Games\EccentriCity"

setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SILENT=0"
set "INSTALL_DIR=%LOCALAPPDATA%\Programs\EccentriCity"
set "GODOT_NAME=Godot_v4.6-voxel_win64.exe"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="/S" goto set_silent
if /I "%~1"=="/D" goto set_install_dir
echo Unknown argument: %~1
echo Usage: install_city.bat [/S] [/D install_dir]
exit /b 1

:set_silent
set "SILENT=1"
shift
goto parse_args

:set_install_dir
if "%~2"=="" (
    echo ERROR: /D requires a path.
    exit /b 1
)
REM Set outside a parenthesized block so %%~2 is not expanded too early.
set "INSTALL_DIR=%~2"
shift
shift
goto parse_args

:args_done
if not exist "%ROOT%\project.godot" (
    echo ERROR: project.godot not found next to installer.
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo.
echo Resolving dependencies - download Godot + Voxel Tools if needed...
call :ensure_deps
if errorlevel 1 (
    if "%SILENT%"=="0" pause
    exit /b 1
)

if "%SILENT%"=="0" (
    echo.
    echo  Eccentri City installer
    echo  --------------
    echo  Source : %ROOT%
    echo  Engine : %GODOT_EXE%
    echo  Target : %INSTALL_DIR%
    echo.
    choice /C YN /M "Install Eccentri City here"
    if errorlevel 2 exit /b 0
)

echo.
echo Installing...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" 2>nul
if not exist "%INSTALL_DIR%" (
    echo ERROR: Could not create "%INSTALL_DIR%"
    if "%SILENT%"=="0" pause
    exit /b 1
)

REM Core game data. Skip VCS/dev caches - NEVER copy a stale source .godot.
REM Fresh class_name maps + imported assets are generated on the install copy below
REM so new scripts / preloads / GLBs do not require installer script edits.
robocopy "%ROOT%" "%INSTALL_DIR%" /E /NFL /NDL /NJH /NJS /nc /ns /np ^
    /XD "%ROOT%\.git" "%ROOT%\.godot" "%ROOT%\dist" "%ROOT%\native" "%ROOT%\.cursor" "%ROOT%\tools\vendor" ^
    /XF install_city.bat *.tmp *.log ^
    /R:2 /W:2 >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 (
    echo ERROR: robocopy failed with code %RC%.
    if "%SILENT%"=="0" pause
    exit /b 1
)
if exist "%INSTALL_DIR%\tools\vendor" rmdir /S /Q "%INSTALL_DIR%\tools\vendor"

REM Engine binary into a stable relative path for the launcher.
if not exist "%INSTALL_DIR%\tools\godot" mkdir "%INSTALL_DIR%\tools\godot"
copy /Y "%GODOT_EXE%" "%INSTALL_DIR%\tools\godot\%GODOT_NAME%" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy Godot executable.
    if "%SILENT%"=="0" pause
    exit /b 1
)
set "INSTALL_GODOT=%INSTALL_DIR%\tools\godot\%GODOT_NAME%"

REM Native bake helper - optional but preferred.
if exist "%ROOT%\addons\city_voxel\bin\city_voxel.dll" (
    if not exist "%INSTALL_DIR%\addons\city_voxel\bin" mkdir "%INSTALL_DIR%\addons\city_voxel\bin"
    copy /Y "%ROOT%\addons\city_voxel\bin\city_voxel.dll" "%INSTALL_DIR%\addons\city_voxel\bin\city_voxel.dll" >nul
)

REM Keep dependency helper so a portable install can re-fetch the engine later.
if exist "%ROOT%\tools\ensure_city_deps.ps1" (
    if not exist "%INSTALL_DIR%\tools" mkdir "%INSTALL_DIR%\tools"
    copy /Y "%ROOT%\tools\ensure_city_deps.ps1" "%INSTALL_DIR%\tools\ensure_city_deps.ps1" >nul
)

REM Bake .godot for THIS install tree: class cache + imported preloads.
REM This is what keeps packages current after gameplay changes.
echo.
echo Importing assets into install ^(Godot headless - may take a few minutes^)...
"%INSTALL_GODOT%" --headless --path "%INSTALL_DIR%" --import
set "IMP_ERR=!ERRORLEVEL!"
REM Godot often exits non-zero after a successful headless --import, and the
REM bake folder can land a moment after the process returns. Poll in PowerShell.
REM Avoid cmd "if exist" on paths that contain a ".godot" segment; that can throw
REM a parse error about "." being unexpected at this time.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\check_godot_import_artifacts.ps1" -InstallDir "%INSTALL_DIR%"
if errorlevel 1 (
    echo ERROR: Godot import did not produce class cache / imported assets.
    echo   Install: %INSTALL_DIR%
    echo   Godot --import exit code was !IMP_ERR!.
    if "%SILENT%"=="0" pause
    exit /b 1
)
echo   Asset import OK ^(godot exit !IMP_ERR!^).

call :write_launcher "%INSTALL_DIR%\EccentriCity.bat"
call :write_uninstall "%INSTALL_DIR%\Uninstall_EccentriCity.bat"

REM Skip Desktop/Start Menu shortcuts in silent mode - used by make_installer staging.
if "%SILENT%"=="1" goto after_shortcuts

set "SHORTCUT_PS=%TEMP%\city_install_shortcuts_%RANDOM%.ps1"
(
echo $install = '%INSTALL_DIR%'
echo $launch = Join-Path $install 'EccentriCity.bat'
echo $uninstall = Join-Path $install 'Uninstall_EccentriCity.bat'
echo $ws = New-Object -ComObject WScript.Shell
echo $desktop = [Environment]::GetFolderPath^('Desktop'^)
echo $start = Join-Path ^([Environment]::GetFolderPath^('StartMenu'^)^) 'Programs\EccentriCity'
echo New-Item -ItemType Directory -Force -Path $start ^| Out-Null
echo $items = @^(
echo   @{ Path = ^(Join-Path $desktop 'EccentriCity.lnk'^); Target = $launch; Desc = 'Eccentri City - procedural voxel city' },
echo   @{ Path = ^(Join-Path $start 'EccentriCity.lnk'^); Target = $launch; Desc = 'Eccentri City - procedural voxel city' },
echo   @{ Path = ^(Join-Path $start 'Uninstall Eccentri City.lnk'^); Target = $uninstall; Desc = 'Uninstall Eccentri City' }
echo ^)
echo foreach ^($item in $items^) {
echo   $lnk = $ws.CreateShortcut^($item.Path^)
echo   $lnk.TargetPath = $item.Target
echo   $lnk.WorkingDirectory = $install
echo   $lnk.Description = $item.Desc
echo   $lnk.Save^(^)
echo }
) > "%SHORTCUT_PS%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SHORTCUT_PS%"
set "SC_ERR=%ERRORLEVEL%"
del "%SHORTCUT_PS%" >nul 2>&1
if not "%SC_ERR%"=="0" (
    echo WARNING: Shortcuts could not be created. You can still run EccentriCity.bat in the install folder.
)

:after_shortcuts
echo.
echo Installed to: %INSTALL_DIR%
echo Launch with Desktop / Start Menu "Eccentri City", or:
echo   "%INSTALL_DIR%\EccentriCity.bat"
echo.

if "%SILENT%"=="0" (
    choice /C YN /M "Launch Eccentri City now"
    if not errorlevel 2 start "" "%INSTALL_DIR%\EccentriCity.bat"
)

endlocal
exit /b 0


:ensure_deps
set "GODOT_EXE="
if defined GODOT if exist "%GODOT%" (
    set "GODOT_EXE=%GODOT%"
    exit /b 0
)
if exist "%ROOT%\tools\godot\%GODOT_NAME%" (
    set "GODOT_EXE=%ROOT%\tools\godot\%GODOT_NAME%"
    goto ensure_native
)
if exist "%ROOT%\%GODOT_NAME%" (
    set "GODOT_EXE=%ROOT%\%GODOT_NAME%"
    goto ensure_native
)

if not exist "%ROOT%\tools\ensure_city_deps.ps1" (
    echo ERROR: Engine missing and tools\ensure_city_deps.ps1 not found.
    echo Download Godot 4.6 + Voxel Tools into tools\godot\%GODOT_NAME%
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%" > "%TEMP%\city_ensure_deps_out.txt"
if errorlevel 1 (
    echo ERROR: Dependency download/build failed.
    type "%TEMP%\city_ensure_deps_out.txt"
    exit /b 1
)
for /f "usebackq delims=" %%L in ("%TEMP%\city_ensure_deps_out.txt") do (
    echo %%L | findstr /I /E ".exe" >nul && set "GODOT_EXE=%%L"
)
if not exist "%GODOT_EXE%" (
    echo ERROR: ensure_city_deps.ps1 did not produce a Godot executable.
    type "%TEMP%\city_ensure_deps_out.txt"
    exit /b 1
)
type "%TEMP%\city_ensure_deps_out.txt"
exit /b 0

:ensure_native
REM Engine already present - still run deps helper; warns if DLL somehow missing.
if exist "%ROOT%\tools\ensure_city_deps.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%" >nul
)
exit /b 0


:write_launcher
set "OUT=%~1"
(
echo @echo off
echo setlocal EnableExtensions
echo set "ROOT=%%~dp0"
echo set "ROOT=%%ROOT:~0,-1%%"
echo set "GODOT_EXE=%%ROOT%%\tools\godot\%GODOT_NAME%"
echo.
echo if not exist "%%GODOT_EXE%%" ^(
echo     if not exist "%%ROOT%%\tools\ensure_city_deps.ps1" ^(
echo         echo ERROR: Engine missing and tools\ensure_city_deps.ps1 not found.
echo         echo Place %GODOT_NAME% in tools\godot\ or restore ensure_city_deps.ps1.
echo         pause
echo         exit /b 1
echo     ^)
echo     echo.
echo     echo Engine missing - downloading Godot 4.6 + Voxel Tools ^(~80 MB^)...
echo     echo Internet required for this first-time step.
echo     echo.
echo     powershell -NoProfile -ExecutionPolicy Bypass -File "%%ROOT%%\tools\ensure_city_deps.ps1" -Root "%%ROOT%%"
echo     if errorlevel 1 ^(
echo         echo ERROR: Could not download the Godot voxel engine.
echo         pause
echo         exit /b 1
echo     ^)
echo ^)
echo if not exist "%%GODOT_EXE%%" ^(
echo     echo ERROR: Engine still missing: %%GODOT_EXE%%
echo     pause
echo     exit /b 1
echo ^)
echo if not exist "%%ROOT%%\project.godot" ^(
echo     echo ERROR: project.godot missing in %%ROOT%%
echo     pause
echo     exit /b 1
echo ^)
echo if not exist "%%ROOT%%\addons\city_voxel\bin\city_voxel.dll" ^(
echo     echo ERROR: addons\city_voxel\bin\city_voxel.dll missing.
echo     echo This DLL ships with the release zip and is required to play.
echo     pause
echo     exit /b 1
echo ^)
echo dir /b "%%ROOT%%\.godot\global_script_class_cache.cfg" ^>nul 2^>^&1
echo if errorlevel 1 goto do_import
echo dir /b "%%ROOT%%\.godot\imported" ^>nul 2^>^&1
echo if errorlevel 1 goto do_import
echo goto launch
echo.
echo :do_import
echo echo.
echo echo First-time asset import - this can take several minutes. Please wait...
echo echo.
echo "%%GODOT_EXE%%" --headless --path "%%ROOT%%" --import
echo dir /b "%%ROOT%%\.godot\global_script_class_cache.cfg" ^>nul 2^>^&1
echo if errorlevel 1 ^(
echo     echo ERROR: Import finished but the godot class cache is still missing.
echo     pause
echo     exit /b 1
echo ^)
echo dir /b "%%ROOT%%\.godot\imported" ^>nul 2^>^&1
echo if errorlevel 1 ^(
echo     echo ERROR: Import finished but the godot imported folder is still missing.
echo     pause
echo     exit /b 1
echo ^)
echo.
echo :launch
echo start "Eccentri City" /MAX "%%GODOT_EXE%%" --path "%%ROOT%%" res://scenes/city_poc.tscn --maximized
echo endlocal
) > "%OUT%"
exit /b 0


:write_uninstall
set "OUT=%~1"
(
echo @echo off
echo setlocal
echo set "INSTALL=%%~dp0"
echo set "INSTALL=%%INSTALL:~0,-1%%"
echo echo This will remove Eccentri City from:
echo echo   %%INSTALL%%
echo echo And Desktop / Start Menu shortcuts.
echo choice /C YN /M "Uninstall Eccentri City"
echo if errorlevel 2 exit /b 0
echo powershell -NoProfile -ExecutionPolicy Bypass -Command ^"Remove-Item -Force -ErrorAction SilentlyContinue ^(^([Environment]::GetFolderPath^('Desktop'^) + '\\EccentriCity.lnk'^)^); $sm = Join-Path ^([Environment]::GetFolderPath^('StartMenu'^)^) 'Programs\\EccentriCity'; if ^(Test-Path $sm^) { Remove-Item -Recurse -Force $sm }^"
echo cd /d "%%TEMP%%"
echo rmdir /S /Q "%%INSTALL%%"
echo echo Eccentri City removed.
echo pause
echo endlocal
) > "%OUT%"
exit /b 0
