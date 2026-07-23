@echo off
REM Build a portable City folder under dist\CityPortable (no shortcuts).
REM Zip that folder to share; recipients can run City.bat or install_city.bat from it.

setlocal EnableExtensions
set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "OUT=%ROOT%\dist\CityPortable"

echo Packing portable City into:
echo   %OUT%
echo.

if exist "%ROOT%\install_city.bat" (
    call "%ROOT%\install_city.bat" /S /D "%OUT%"
) else (
    echo ERROR: install_city.bat not found at repo root.
    exit /b 1
)

REM Portable packs keep the installer so users can copy into Programs later.
copy /Y "%ROOT%\install_city.bat" "%OUT%\install_city.bat" >nul

echo.
echo Done. Zip contents of:
echo   %OUT%
echo Or run:
echo   %OUT%\City.bat
endlocal
exit /b 0
