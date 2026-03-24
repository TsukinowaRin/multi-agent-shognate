@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Updater

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Windows Updater          ^|
echo   ^|      Manual update / release auto-update toggle           ^|
echo   +============================================================+
echo.

if not exist "%SCRIPT_DIR%\first_setup.sh" (
    echo   [ERROR] first_setup.sh not found next to updater.bat
    echo           updater.bat は Shogunate の配置先フォルダで実行してください。
    echo.
    pause
    exit /b 1
)

set "MODE_ARG=manual"
set "AUTO_ARG="
if /I "%~1"=="--auto-on" (
    set "AUTO_ARG=--enable-auto"
) else if /I "%~1"=="--auto-off" (
    set "AUTO_ARG=--disable-auto"
)

echo   [1/3] Checking WSL2 / Ubuntu...
wsl.exe -d Ubuntu -- echo test >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Ubuntu on WSL is not ready.
    echo           先に installer を実行して Ubuntu / WSL を整えてください。
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

echo   [3/3] Running updater...
wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" && python3 scripts/update_manager.py manual %AUTO_ARG%"
set "UPDATE_EXIT=%ERRORLEVEL%"

if "%UPDATE_EXIT%"=="10" (
    echo.
    echo   [INFO] Update applied. Running first_setup.sh once...
    wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" && bash first_setup.sh"
    echo.
    echo   [OK] Update complete.
) else if not "%UPDATE_EXIT%"=="0" (
    echo.
    echo   [ERROR] Update failed.
    echo           Ubuntu で詳細確認:
    echo             cd %REPO_WSL%
    echo             python3 scripts/update_manager.py status
    echo             python3 scripts/update_manager.py manual
    echo.
    pause
    exit /b %UPDATE_EXIT%
)

if /I "%~1"=="--auto-on" (
    echo   [OK] Release auto-update enabled.
) else if /I "%~1"=="--auto-off" (
    echo   [OK] Release auto-update disabled.
)

echo.
echo   Current repo:
echo     %SCRIPT_DIR%
echo.
echo   Daily startup:
echo     wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" ^&^& bash shutsujin_departure.sh"
echo.
pause
exit /b 0
