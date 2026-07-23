@echo off
REM City — install a portable copy + Desktop / Start Menu shortcuts.
REM Downloads Godot 4.6 + Voxel Tools when missing; optionally builds city_voxel.dll.
REM
REM Usage:
REM   install_city.bat
REM   install_city.bat /D "%LOCALAPPDATA%\Programs\City"
REM   install_city.bat /S /D "D:\Games\City"

setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SILENT=0"
set "INSTALL_DIR=%LOCALAPPDATA%\Programs\City"
set "GODOT_NAME=Godot_v4.6-voxel_win64.exe"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="/S" (
    set "SILENT=1"
    shift
    goto parse_args
)
if /I "%~1"=="/D" (
    if "%~2"=="" (
        echo ERROR: /D requires a path.
        exit /b 1
    )
    set "INSTALL_DIR=%~2"
    shift
    shift
    goto parse_args
)
echo Unknown argument: %~1
echo Usage: install_city.bat [/S] [/D install_dir]
exit /b 1

:args_done
if not exist "%ROOT%\project.godot" (
    echo ERROR: project.godot not found next to installer.
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo.
echo Resolving dependencies (download Godot + Voxel Tools if needed)...
call :ensure_deps
if errorlevel 1 (
    if "%SILENT%"=="0" pause
    exit /b 1
)

if "%SILENT%"=="0" (
    echo.
    echo  City installer
    echo  --------------
    echo  Source : %ROOT%
    echo  Engine : %GODOT_EXE%
    echo  Target : %INSTALL_DIR%
    echo.
    choice /C YN /M "Install City here"
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

REM Core game data (skip VCS / build caches / this installer scratch).
robocopy "%ROOT%" "%INSTALL_DIR%" /E /NFL /NDL /NJH /NJS /nc /ns /np ^
    /XD .git .godot dist native .cursor ^
    /XF install_city.bat *.tmp *.log ^
    /R:2 /W:2 >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 (
    echo ERROR: robocopy failed with code %RC%.
    if "%SILENT%"=="0" pause
    exit /b 1
)

REM Engine binary into a stable relative path for the launcher.
if not exist "%INSTALL_DIR%\tools\godot" mkdir "%INSTALL_DIR%\tools\godot"
copy /Y "%GODOT_EXE%" "%INSTALL_DIR%\tools\godot\%GODOT_NAME%" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy Godot executable.
    if "%SILENT%"=="0" pause
    exit /b 1
)

REM Native bake helper (optional but preferred).
if exist "%ROOT%\addons\city_voxel\bin\city_voxel.dll" (
    if not exist "%INSTALL_DIR%\addons\city_voxel\bin" mkdir "%INSTALL_DIR%\addons\city_voxel\bin"
    copy /Y "%ROOT%\addons\city_voxel\bin\city_voxel.dll" "%INSTALL_DIR%\addons\city_voxel\bin\city_voxel.dll" >nul
)

REM Keep dependency helper so a portable install can re-fetch the engine later.
if exist "%ROOT%\tools\ensure_city_deps.ps1" (
    if not exist "%INSTALL_DIR%\tools" mkdir "%INSTALL_DIR%\tools"
    copy /Y "%ROOT%\tools\ensure_city_deps.ps1" "%INSTALL_DIR%\tools\ensure_city_deps.ps1" >nul
)

call :write_launcher "%INSTALL_DIR%\City.bat"
call :write_uninstall "%INSTALL_DIR%\Uninstall_City.bat"

set "SHORTCUT_PS=%TEMP%\city_install_shortcuts_%RANDOM%.ps1"
(
echo $install = '%INSTALL_DIR%'
echo $launch = Join-Path $install 'City.bat'
echo $uninstall = Join-Path $install 'Uninstall_City.bat'
echo $ws = New-Object -ComObject WScript.Shell
echo $desktop = [Environment]::GetFolderPath^('Desktop'^)
echo $start = Join-Path ^([Environment]::GetFolderPath^('StartMenu'^)^) 'Programs\City'
echo New-Item -ItemType Directory -Force -Path $start ^| Out-Null
echo $items = @(
echo   @{ Path = ^(Join-Path $desktop 'City.lnk'^); Target = $launch; Desc = 'City - procedural voxel city' },
echo   @{ Path = ^(Join-Path $start 'City.lnk'^); Target = $launch; Desc = 'City - procedural voxel city' },
echo   @{ Path = ^(Join-Path $start 'Uninstall City.lnk'^); Target = $uninstall; Desc = 'Uninstall City' }
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
    echo WARNING: Shortcuts could not be created. You can still run City.bat in the install folder.
)

echo.
echo Installed to: %INSTALL_DIR%
echo Launch with Desktop / Start Menu "City", or:
echo   "%INSTALL_DIR%\City.bat"
echo.

if "%SILENT%"=="0" (
    choice /C YN /M "Launch City now"
    if not errorlevel 2 start "" "%INSTALL_DIR%\City.bat"
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
for /f "usebackq delims=" %%L in ("%TEMP%\city_ensure_deps_out.txt") do set "GODOT_EXE=%%L"
if not exist "%GODOT_EXE%" (
    echo ERROR: ensure_city_deps.ps1 did not produce a Godot executable.
    type "%TEMP%\city_ensure_deps_out.txt"
    exit /b 1
)
type "%TEMP%\city_ensure_deps_out.txt"
exit /b 0

:ensure_native
REM Engine already present — still try to fetch/build optional native DLL.
if exist "%ROOT%\tools\ensure_city_deps.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%" >nul
)
exit /b 0


:write_launcher
set "OUT=%~1"
(
echo @echo off
echo setlocal
echo set "ROOT=%%~dp0"
echo set "GODOT_EXE=%%ROOT%%tools\godot\%GODOT_NAME%"
echo if not exist "%%GODOT_EXE%%" ^(
echo     if exist "%%ROOT%%tools\ensure_city_deps.ps1" ^(
echo         echo Engine missing — downloading Godot + Voxel Tools...
echo         powershell -NoProfile -ExecutionPolicy Bypass -File "%%ROOT%%tools\ensure_city_deps.ps1" -Root "%%ROOT%%"
echo     ^)
echo ^)
echo if not exist "%%GODOT_EXE%%" ^(
echo     echo ERROR: Engine missing: %%GODOT_EXE%%
echo     pause
echo     exit /b 1
echo ^)
echo if not exist "%%ROOT%%project.godot" ^(
echo     echo ERROR: project.godot missing in %%ROOT%%
echo     pause
echo     exit /b 1
echo ^)
echo start "City" /MAX "%%GODOT_EXE%%" --path "%%ROOT%%." res://scenes/city_poc.tscn --maximized
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
echo echo This will remove City from:
echo echo   %%INSTALL%%
echo echo And Desktop / Start Menu shortcuts.
echo choice /C YN /M "Uninstall City"
echo if errorlevel 2 exit /b 0
echo powershell -NoProfile -ExecutionPolicy Bypass -Command ^"Remove-Item -Force -ErrorAction SilentlyContinue ([Environment]::GetFolderPath^('Desktop'^) + '\\City.lnk'^); $sm = Join-Path ^([Environment]::GetFolderPath^('StartMenu'^)^) 'Programs\\City'; if ^(Test-Path $sm^) { Remove-Item -Recurse -Force $sm }^"
echo cd /d "%%TEMP%%"
echo rmdir /S /Q "%%INSTALL%%"
echo echo City removed.
echo pause
echo endlocal
) > "%OUT%"
exit /b 0
