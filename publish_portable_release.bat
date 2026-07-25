@echo off
REM Build slim EccentriCityPortable-windows.zip and upload a GitHub Release.
REM Usage:
REM   publish_portable_release.bat
REM   publish_portable_release.bat portable-20260725
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
	powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\publish_portable_release.ps1" -Root "%ROOT%" %SKIP%
) else (
	powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\publish_portable_release.ps1" -Root "%ROOT%" -Tag "%TAG%" %SKIP%
)
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
	echo ERROR: publish failed. ERRORLEVEL=%ERR%
	pause
	exit /b %ERR%
)
endlocal
exit /b 0
