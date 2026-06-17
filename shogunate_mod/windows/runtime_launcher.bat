@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Runtime

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..\..") do set "REPO_DIR=%%~fI"

set "CLEAN_ARG=-c"
set "ATTACH_AFTER=1"

if /I "%~1"=="--resume" set "CLEAN_ARG="
if /I "%~1"=="--clean" set "CLEAN_ARG=-c"
if /I "%~1"=="--no-attach" set "ATTACH_AFTER=0"
if /I "%~2"=="--no-attach" set "ATTACH_AFTER=0"

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Runtime Launcher         ^|
echo   ^|      Starts Shogunate in Ubuntu/WSL and opens shogunate    ^|
echo   +============================================================+
echo.

if not exist "%REPO_DIR%\shutsujin_departure.sh" (
    echo   [ERROR] shutsujin_departure.sh not found next to this launcher.
    echo           Run this bat from the Shogunate folder.
    echo.
    pause
    exit /b 1
)

echo   [1/3] Checking Ubuntu on WSL...
wsl.exe -d Ubuntu -- echo test >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Ubuntu on WSL is not ready.
    echo           Finish Ubuntu initial setup, then run first_setup.sh in WSL.
    echo.
    pause
    exit /b 1
)
echo   [OK] Ubuntu OK
echo.

echo   [2/3] Resolving WSL path...
for /f "usebackq delims=" %%I in (`wsl.exe -d Ubuntu -- wslpath -a "%REPO_DIR%"`) do set "REPO_WSL=%%I"
if not defined REPO_WSL (
    echo   [ERROR] Failed to resolve WSL path from:
    echo           %REPO_DIR%
    echo.
    pause
    exit /b 1
)
echo   [OK] %REPO_WSL%
echo.

echo   [3/3] Starting runtime...
if defined CLEAN_ARG (
    echo        Mode: clean start
) else (
    echo        Mode: resume existing state
)
echo.
wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" && bash ./Shogunate-Runtime.sh %*"
set "RUNTIME_EXIT=%ERRORLEVEL%"
if not "%RUNTIME_EXIT%"=="0" (
    echo.
    echo   [ERROR] Runtime launcher failed with exit code %RUNTIME_EXIT%.
    echo.
    pause
    exit /b %RUNTIME_EXIT%
)

echo.
echo   [OK] Runtime command finished.
echo.
pause
exit /b 0
