@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Role Configurator

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Role Configurator         ^|
echo   ^|      Runs role configuration inside Ubuntu/WSL              ^|
echo   +============================================================+
echo.

if not exist "%SCRIPT_DIR%\scripts\configure_runtime_roles.py" (
    echo   [ERROR] scripts\configure_runtime_roles.py not found next to this launcher.
    echo           Run this bat from the Shogunate folder.
    echo.
    pause
    exit /b 1
)

echo   [1/3] Checking Ubuntu on WSL...
wsl.exe -d Ubuntu -- echo test >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Ubuntu on WSL is not ready.
    echo           Run install.bat first, or finish Ubuntu initial setup.
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

echo   [3/3] Opening configurator...
echo.
wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" && python3 scripts/configure_runtime_roles.py"
set "CONFIG_EXIT=%ERRORLEVEL%"
if not "%CONFIG_EXIT%"=="0" (
    echo.
    echo   [ERROR] Configurator failed with exit code %CONFIG_EXIT%.
    echo.
    pause
    exit /b %CONFIG_EXIT%
)

echo.
echo   [OK] Role configuration finished.
echo        Restart runtime with Shogunate-Runtime.bat or:
echo        bash shutsujin_departure.sh -c
echo.
pause
exit /b 0
