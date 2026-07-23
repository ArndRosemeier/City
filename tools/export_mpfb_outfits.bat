@echo off
REM Export MakeHuman/MPFB clothed outfit GLBs via headless Blender.
setlocal
set "ROOT=%~dp0.."
set "BLENDER=%ROOT%\tools\vendor\blender\blender-4.2.9-windows-x64\blender.exe"
set "SCRIPT=%ROOT%\tools\blender_export_mpfb_outfits.py"

if not exist "%BLENDER%" (
  echo ERROR: Blender not found at "%BLENDER%"
  echo Run: python tools\download_blender_mpfb.py ^&^& python tools\extract_vendor.py
  exit /b 1
)

REM Optional: set OUTFIT_ONLY=male_casual_01 to export a single variant.
"%BLENDER%" --background --python "%SCRIPT%"
exit /b %ERRORLEVEL%
