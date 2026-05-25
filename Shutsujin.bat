@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Shutsujin

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Shutsujin Launcher       ^|
echo   ^|      Starts shutsujin; choose views with cgo/CGO/csa/CSA   ^|
echo   +============================================================+
echo.

if not exist "%SCRIPT_DIR%\shutsujin_departure.sh" (
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
for /f "usebackq delims=" %%I in (`wsl.exe -d Ubuntu -- wslpath -a "%SCRIPT_DIR%"`) do set "REPO_WSL=%%I"
if not defined REPO_WSL (
    echo   [ERROR] Failed to resolve WSL path from:
    echo           %SCRIPT_DIR%
    echo.
    pause
    exit /b 1
)
echo   [OK] %REPO_WSL%
echo.

echo   [3/3] Starting shutsujin...
echo        This launcher does not auto-open Goza View.
echo        After startup, type cgo or CGO for Goza View.
echo        Type csa or CSA for Ashigaru View.
echo.
wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" && bash ./Shutsujin.sh %*"
set "SHUTSUJIN_EXIT=%ERRORLEVEL%"
if not "%SHUTSUJIN_EXIT%"=="0" (
    echo.
    echo   [ERROR] Shutsujin launcher failed with exit code %SHUTSUJIN_EXIT%.
    echo.
    pause
    exit /b %SHUTSUJIN_EXIT%
)

echo.
echo   [OK] Shutsujin command finished.
echo.
pause
exit /b 0
