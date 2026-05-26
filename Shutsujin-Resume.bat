@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title multi-agent-shognate Shutsujin Resume

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo.
echo   [SHOGUN] Shutsujin resume debug launcher
echo.
call "%SCRIPT_DIR%\Shutsujin.bat" %*
exit /b %ERRORLEVEL%
