@echo off
REM Build a shareable City portable folder for other Windows PCs.
REM Stages sources, re-imports the staged copy with Godot, then validates
REM every script + city_poc. Zip yourself if you need an archive.
REM
REM Recipients use the folder, then either:
REM   - double-click City.bat            (play in place)
REM   - double-click install_city.bat    (copy to Programs + shortcuts)
REM
REM Usage:
REM   make_installer.bat
REM   make_installer.bat /S

setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "OUT_DIR=%ROOT%\dist\CityPortable"
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
echo  Make City portable package
echo  -------------------------
echo  Output folder : %OUT_DIR%
echo.

if not exist "%ROOT%\project.godot" (
    echo ERROR: Run this from the City repo root.
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo [1/3] Ensuring Godot + Voxel Tools engine...
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
echo [2/3] Staging portable folder + baking Godot import...
echo   ^(Copies sources, then runs headless --import on the staged copy so new
echo    scripts, class_name types, and preloaded GLBs/audio are always current.^)
if exist "%OUT_DIR%" rmdir /S /Q "%OUT_DIR%"
mkdir "%OUT_DIR%" 2>nul

call "%ROOT%\install_city.bat" /S /D "%OUT_DIR%"
set "STAGE_ERR=!ERRORLEVEL!"
if not "!STAGE_ERR!"=="0" (
    echo ERROR: Staging via install_city.bat failed. ERRORLEVEL=!STAGE_ERR!
    if "%SILENT%"=="0" pause
    exit /b 1
)

REM Keep the end-user installer + deps helper inside the package.
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
echo - Package includes a full Godot import + script class cache.
echo   Keep the .godot folder; deleting it forces a long re-import.
echo - Needs a 64-bit Windows 10/11 PC. No Rust/Visual Studio required.
echo - If the engine binary is missing, install_city.bat / City.bat can
echo   re-download Godot 4.6 + Voxel Tools ^(internet required^).
) > "%OUT_DIR%\README_INSTALL.txt"

echo.
echo [3/3] Validating staged package ^(all scripts + city_poc^)...
set "VALIDATE_LOG=%TEMP%\city_portable_validate_%RANDOM%.log"
"%OUT_DIR%\tools\godot\%GODOT_NAME%" --headless --path "%OUT_DIR%" -s res://tools/validate_portable.gd > "%VALIDATE_LOG%" 2>&1
set "VAL_ERR=!ERRORLEVEL!"
findstr /I /C:"PORTABLE_VALIDATE: OK" "%VALIDATE_LOG%" >nul
if errorlevel 1 (
    echo ERROR: Portable validation failed. Log:
    type "%VALIDATE_LOG%"
    del "%VALIDATE_LOG%" >nul 2>&1
    if "%SILENT%"=="0" pause
    exit /b 1
)
if not "!VAL_ERR!"=="0" (
    echo ERROR: Validator exited with code !VAL_ERR!
    type "%VALIDATE_LOG%"
    del "%VALIDATE_LOG%" >nul 2>&1
    if "%SILENT%"=="0" pause
    exit /b 1
)
echo   Validation OK.
del "%VALIDATE_LOG%" >nul 2>&1

echo.
echo Done.
echo Portable folder:
echo   %OUT_DIR%
echo.
if "%SILENT%"=="0" pause
endlocal
exit /b 0
