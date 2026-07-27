@echo off
REM Legacy alias — prefer make_installer.bat (tools\pack_release.ps1 -Mode Folder).
call "%~dp0..\make_installer.bat" %*
