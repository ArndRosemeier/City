@echo off
REM Export MakeHuman/MPFB male+female glTF/GLB bases via headless Blender.
setlocal
set "ROOT=%~dp0.."
set "BLENDER=%ROOT%\tools\vendor\blender\blender-4.2.9-windows-x64\blender.exe"
set "SCRIPT=%ROOT%\tools\blender_export_mpfb_humans.py"

if not exist "%BLENDER%" (
  echo ERROR: Blender not found at "%BLENDER%"
  echo Run: python tools\download_blender_mpfb.py ^&^& python tools\extract_vendor.py
  exit /b 1
)

"%BLENDER%" --background --python "%SCRIPT%"
exit /b %ERRORLEVEL%
