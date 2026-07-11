@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title multi-agent-shognate Shutsujin Resume

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..\..") do set "REPO_DIR=%%~fI"

echo.
echo   [SHOGUN] Shutsujin resume debug launcher
echo            mode: resume existing state
echo.
call "%REPO_DIR%\shogunate_mod\windows\shutsujin_launcher.bat" %*
exit /b %ERRORLEVEL%
