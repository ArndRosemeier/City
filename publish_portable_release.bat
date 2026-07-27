@echo off
REM Build slim zip from git-tracked files and upload a GitHub Release.
REM Usage:
REM   publish_portable_release.bat
REM   publish_portable_release.bat portable-20260727
REM   publish_portable_release.bat /SkipUpload

setlocal EnableExtensions
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "TAG="
set "SKIP="

:parse
if "%~1"=="" goto run
if /I "%~1"=="/SkipUpload" (
    set "SKIP=-SkipUpload"
    shift
    goto parse
)
set "TAG=%~1"
shift
goto parse

:run
if "%TAG%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\pack_release.ps1" -Root "%ROOT%" -Mode Publish %SKIP%
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\pack_release.ps1" -Root "%ROOT%" -Mode Publish -Tag "%TAG%" %SKIP%
)
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
    echo ERROR: publish failed with code %ERR%.
    exit /b 1
)
endlocal
exit /b 0
