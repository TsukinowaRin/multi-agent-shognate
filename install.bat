@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Installer

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Windows Installer         ^|
echo   ^|           WSL2 + Ubuntu + first_setup.sh                  ^|
echo   +============================================================+
echo.

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

echo   Repository:
echo     %SCRIPT_DIR%
echo.

REM ===== Step 1: Check/Install WSL2 =====
echo   [1/4] Checking WSL2...
wsl.exe --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   WSL2 not found. Installing automatically...
    echo   WSL2 が見つかりません。自動インストール中...
    echo.

    net session >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo   +============================================================+
        echo   ^|  [WARN] Administrator privileges required!                 ^|
        echo   ^|         管理者権限が必要です                               ^|
        echo   +============================================================+
        echo.
        echo   Right-click install.bat and select "Run as administrator"
        echo   install.bat を右クリック→「管理者として実行」
        echo.
        pause
        exit /b 1
    )

    powershell -Command "wsl --install --no-launch"
    echo.
    echo   +============================================================+
    echo   ^|  [!] Restart required!                                     ^|
    echo   ^|      再起動後に install.bat を再実行してください           ^|
    echo   +============================================================+
    echo.
    pause
    exit /b 0
)
echo   [OK] WSL2 OK
echo.

REM ===== Step 2: Check/Install Ubuntu =====
echo   [2/4] Checking Ubuntu...
wsl.exe -d Ubuntu -- echo test >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :ubuntu_ok

wsl.exe -d Ubuntu -- exit 0 >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :ubuntu_needs_setup

echo.
echo   Ubuntu not found. Installing automatically...
echo   Ubuntu が見つかりません。自動インストール中...
echo.
powershell -Command "wsl --install -d Ubuntu --no-launch"
echo.
echo   +============================================================+
echo   ^|  [NOTE] Ubuntu installation started!                       ^|
echo   ^|         Ubuntu の初期セットアップ後に install.bat を再実行 ^|
echo   +============================================================+
echo.
pause
exit /b 0

:ubuntu_needs_setup
echo.
echo   +============================================================+
echo   ^|  [WARN] Ubuntu initial setup required!                     ^|
echo   ^|         Ubuntu の初期設定がまだ完了していません            ^|
echo   +============================================================+
echo.
echo   1. Start Menu から Ubuntu を開く
echo   2. Linux user name / password を設定する
echo   3. install.bat をもう一度実行する
echo.
pause
exit /b 1

:ubuntu_ok
echo   [OK] Ubuntu OK
echo.

REM ===== Step 3: Resolve repo path in WSL =====
echo   [3/4] Resolving repository path...
for /f "usebackq delims=" %%I in (`wsl.exe -d Ubuntu -- wslpath -a "%SCRIPT_DIR%"`) do set "REPO_WSL=%%I"

if not defined REPO_WSL (
    echo   [ERROR] Failed to resolve WSL path from:
    echo           %SCRIPT_DIR%
    pause
    exit /b 1
)

echo   [OK] WSL path:
echo        %REPO_WSL%
echo.

REM ===== Step 4: Run first_setup.sh =====
echo   [4/4] Running first_setup.sh in Ubuntu...
echo         first_setup.sh を実行中...
echo.

wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" && bash first_setup.sh"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   +============================================================+
    echo   ^|  [WARN] first_setup.sh exited with an error.              ^|
    echo   ^|         first_setup.sh が正常終了しませんでした            ^|
    echo   +============================================================+
    echo.
    echo   Re-run inside Ubuntu for details:
    echo   Ubuntu で詳細確認:
    echo     cd %REPO_WSL%
    echo     bash first_setup.sh
    echo.
    pause
    exit /b 1
)

echo.
echo   +============================================================+
echo   ^|  [OK] Setup complete!                                      ^|
echo   ^|       初回セットアップ完了                                 ^|
echo   +============================================================+
echo.
echo   Daily startup / 以後の起動:
echo     wsl.exe -d Ubuntu -- bash -lc "cd \"%REPO_WSL%\" ^&^& bash shutsujin_departure.sh"
echo.
echo   Or inside Ubuntu:
echo     cd %REPO_WSL%
echo     bash shutsujin_departure.sh
echo.
pause
exit /b 0
