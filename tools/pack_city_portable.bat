@echo off
REM Legacy alias — prefer make_installer.bat at the repo root (also builds the zip).
setlocal
call "%~dp0..\make_installer.bat"
endlocal
exit /b %ERRORLEVEL%
