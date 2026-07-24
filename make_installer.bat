@echo off
REM Build a shareable City package for other Windows PCs.
REM This does NOT install onto your machine - it creates dist\City-Windows.zip
REM
REM Recipients unzip, then either:
REM   - double-click City.bat            (play in place)
REM   - double-click install_city.bat    (copy to Programs + shortcuts)
REM
REM Usage:
REM   make_installer.bat
REM   make_installer.bat /S
REM
REM Requires internet once if tools\godot\Godot_v4.6-voxel_win64.exe is missing.

setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "OUT_DIR=%ROOT%\dist\CityPortable"
set "ZIP_PATH=%ROOT%\dist\City-Windows.zip"
set "GODOT_NAME=Godot_v4.6-voxel_win64.exe"
set "SILENT=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="/S" (
    set "SILENT=1"
    shift
    goto parse_args
)
echo Unknown argument: %~1
echo Usage: make_installer.bat [/S]
exit /b 1

:args_done

echo.
echo  Make City installer package
echo  ---------------------------
echo  Output folder : %OUT_DIR%
echo  Output zip    : %ZIP_PATH%
echo.

if not exist "%ROOT%\project.godot" (
    echo ERROR: Run this from the City repo root.
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo [1/4] Ensuring Godot + Voxel Tools engine...
if not exist "%ROOT%\tools\ensure_city_deps.ps1" (
    echo ERROR: tools\ensure_city_deps.ps1 missing.
    if "%SILENT%"=="0" pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\ensure_city_deps.ps1" -Root "%ROOT%"
if errorlevel 1 (
    echo ERROR: Could not resolve engine dependencies.
    if "%SILENT%"=="0" pause
    exit /b 1
)
if not exist "%ROOT%\tools\godot\%GODOT_NAME%" (
    echo ERROR: Engine still missing after ensure step: tools\godot\%GODOT_NAME%
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo.
echo [2/4] Staging portable folder...
if exist "%OUT_DIR%" rmdir /S /Q "%OUT_DIR%"
mkdir "%OUT_DIR%" 2>nul

REM Reuse the silent installer to copy game + engine into the staging folder.
call "%ROOT%\install_city.bat" /S /D "%OUT_DIR%"
set "STAGE_ERR=!ERRORLEVEL!"
if not "!STAGE_ERR!"=="0" (
    echo ERROR: Staging via install_city.bat failed. ERRORLEVEL=!STAGE_ERR!
    if "%SILENT%"=="0" pause
    exit /b 1
)

REM Keep the end-user installer inside the package.
copy /Y "%ROOT%\install_city.bat" "%OUT_DIR%\install_city.bat" >nul
if exist "%ROOT%\tools\ensure_city_deps.ps1" (
    if not exist "%OUT_DIR%\tools" mkdir "%OUT_DIR%\tools"
    copy /Y "%ROOT%\tools\ensure_city_deps.ps1" "%OUT_DIR%\tools\ensure_city_deps.ps1" >nul
)

(
echo City - Windows package
echo ======================
echo.
echo Option A - play immediately
echo   Double-click City.bat
echo.
echo Option B - install with shortcuts
echo   Double-click install_city.bat
echo   Default location: %%LOCALAPPDATA%%\Programs\City
echo.
echo Notes
echo -----
echo - First launch may take a few minutes while Godot imports assets.
echo - Needs a 64-bit Windows 10/11 PC. No Rust/Visual Studio required.
echo - If the engine binary is missing, install_city.bat / City.bat can
echo   re-download Godot 4.6 + Voxel Tools ^(internet required^).
) > "%OUT_DIR%\README_INSTALL.txt"

echo.
echo [3/4] Creating zip...
if exist "%ZIP_PATH%" del /F /Q "%ZIP_PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path (Join-Path '%OUT_DIR%' '*') -DestinationPath '%ZIP_PATH%' -Force"
if errorlevel 1 (
    echo ERROR: Failed to create zip.
    if "%SILENT%"=="0" pause
    exit /b 1
)
if not exist "%ZIP_PATH%" (
    echo ERROR: Zip was not created: %ZIP_PATH%
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo.
echo [4/4] Done.
for %%A in ("%ZIP_PATH%") do echo   Zip size: %%~zA bytes
echo.
echo Share this file:
echo   %ZIP_PATH%
echo.
echo Or the unzipped folder:
echo   %OUT_DIR%
echo.
if "%SILENT%"=="0" pause
endlocal
exit /b 0