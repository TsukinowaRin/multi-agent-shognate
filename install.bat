@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Installer

set "REPO_OWNER=TsukinowaRin"
set "REPO_NAME=multi-agent-shognate"
set "REPO_BRANCH=main"
set "DOWNLOAD_URL=https://github.com/%REPO_OWNER%/%REPO_NAME%/archive/refs/heads/%REPO_BRANCH%.zip"
set "INSTALL_ROOT=%USERPROFILE%\tools"
set "INSTALL_DIR=%INSTALL_ROOT%\%REPO_NAME%"
set "TEMP_ROOT=%TEMP%\%REPO_NAME%-installer"
set "ZIP_PATH=%TEMP_ROOT%\%REPO_NAME%-%REPO_BRANCH%.zip"
set "EXTRACT_ROOT=%TEMP_ROOT%\extract"
set "EXTRACTED_DIR=%EXTRACT_ROOT%\%REPO_NAME%-%REPO_BRANCH%"

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Windows Installer         ^|
echo   ^|      Release bootstrap + WSL2 + Ubuntu + first_setup.sh   ^|
echo   +============================================================+
echo.

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "REPO_DIR_WIN="
set "INSTALL_MODE=download"

if exist "%SCRIPT_DIR%\first_setup.sh" (
    set "INSTALL_MODE=local"
    set "REPO_DIR_WIN=%SCRIPT_DIR%"
)

if /I "%INSTALL_MODE%"=="local" (
    echo   Mode:
    echo     Local repository
    echo   Repository:
    echo     %REPO_DIR_WIN%
) else (
    echo   Mode:
    echo     Standalone release bootstrap
    echo   Download source:
    echo     %DOWNLOAD_URL%
    echo   Install target:
    echo     %INSTALL_DIR%
)
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

REM ===== Step 3: Prepare repository =====
echo   [3/4] Preparing repository...
if /I "%INSTALL_MODE%"=="local" goto :repo_ready

if not exist "%INSTALL_ROOT%" mkdir "%INSTALL_ROOT%" >nul 2>&1
if exist "%TEMP_ROOT%" rmdir /s /q "%TEMP_ROOT%" >nul 2>&1
mkdir "%TEMP_ROOT%" >nul 2>&1

echo         Downloading latest source from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_PATH%'"
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Failed to download latest source archive.
    echo           GitHub から最新コードをダウンロードできませんでした。
    pause
    exit /b 1
)

echo         Extracting archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP_PATH%' -DestinationPath '%EXTRACT_ROOT%' -Force"
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] Failed to extract source archive.
    echo           ZIP 展開に失敗しました。
    pause
    exit /b 1
)

if not exist "%EXTRACTED_DIR%\first_setup.sh" (
    echo   [ERROR] Extracted archive is missing first_setup.sh
    echo           展開結果が想定と異なります。
    pause
    exit /b 1
)

echo         Syncing files into install target...
robocopy "%EXTRACTED_DIR%" "%INSTALL_DIR%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS >nul
if %ERRORLEVEL% GEQ 8 (
    echo   [ERROR] Failed to copy files into install target.
    echo           %INSTALL_DIR%
    pause
    exit /b 1
)

set "REPO_DIR_WIN=%INSTALL_DIR%"
echo   [OK] Latest source synced to:
echo        %REPO_DIR_WIN%
echo.

:repo_ready
echo   [OK] Repository ready
echo.
echo         Resolving WSL path...
for /f "usebackq delims=" %%I in (`wsl.exe -d Ubuntu -- wslpath -a "%REPO_DIR_WIN%"`) do set "REPO_WSL=%%I"

if not defined REPO_WSL (
    echo   [ERROR] Failed to resolve WSL path from:
    echo           %REPO_DIR_WIN%
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
echo   Repository location / 配置先:
echo     %REPO_DIR_WIN%
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
