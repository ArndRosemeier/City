@echo off
REM Build a shareable Eccentri City portable folder (engine + baked .godot).
REM Delegates to tools\pack_release.ps1 so folder and GitHub zip share one pipeline.
REM
REM Usage:
REM   make_installer.bat
REM   make_installer.bat /S

setlocal EnableExtensions
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
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
echo  Make Eccentri City portable package
echo  -------------------------
echo  Output: %ROOT%\dist\EccentriCityPortable
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\pack_release.ps1" -Root "%ROOT%" -Mode Folder
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
    echo ERROR: pack_release failed with code %ERR%.
    if "%SILENT%"=="0" pause
    exit /b 1
)

echo.
echo Done.
echo Portable folder:
echo   %ROOT%\dist\EccentriCityPortable
echo.
if "%SILENT%"=="0" pause
endlocal
exit /b 0
