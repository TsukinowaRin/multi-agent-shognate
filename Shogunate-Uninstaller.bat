@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title multi-agent-shognate Uninstaller

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "UNINSTALLER_NAME=%~nx0"

echo.
echo   +============================================================+
echo   ^|  [SHOGUN] multi-agent-shognate - Uninstaller              ^|
echo   ^|      Stops runtime, preserves or removes personal data,   ^|
echo   ^|      then removes the installed files in this folder      ^|
echo   +============================================================+
echo.

if not exist "%SCRIPT_DIR%\first_setup.sh" (
    echo   [ERROR] first_setup.sh not found next to %UNINSTALLER_NAME%
    echo           %UNINSTALLER_NAME% は Shogunate 配置先フォルダで実行してください。
    echo.
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%\shutsujin_departure.sh" (
    echo   [ERROR] shutsujin_departure.sh not found next to %UNINSTALLER_NAME%
    echo.
    pause
    exit /b 1
)

echo   Install location:
echo     %SCRIPT_DIR%
echo.
echo   This removes files inside the folder above.
echo   Parent folder itself is kept so you can clean-install again.
echo.

echo   Personal data handling:
echo     [Y] Preserve personal data outside this folder for later restore
echo     [N] Delete everything in this install
choice /M "Preserve personal data before uninstall"
set "PRESERVE_CHOICE=%ERRORLEVEL%"

choice /M "Proceed with uninstall"
if errorlevel 2 (
    echo.
    echo   [INFO] Uninstall cancelled.
    echo.
    exit /b 0
)

set "PRESERVE_DATA=0"
if "%PRESERVE_CHOICE%"=="1" set "PRESERVE_DATA=1"

echo.
echo   [1/4] Checking WSL / Ubuntu...
wsl.exe -d Ubuntu -- echo test >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [WARN] Ubuntu on WSL is not ready. Runtime stop step will be skipped.
    set "REPO_WSL="
    goto :after_wsl
)

for /f "usebackq delims=" %%I in (`wsl.exe -d Ubuntu -- wslpath -a "%SCRIPT_DIR%"`) do set "REPO_WSL=%%I"
if not defined REPO_WSL (
    echo   [WARN] Failed to resolve WSL path. Runtime stop step will be skipped.
) else (
    echo   [OK] WSL path:
    echo        %REPO_WSL%
)
echo.

:after_wsl
echo   [2/4] Stopping running Shogunate sessions...
if defined REPO_WSL (
    wsl.exe -d Ubuntu -- bash -lc "tmux kill-session -t goza-no-ma 2>/dev/null || true; tmux kill-session -t shogun 2>/dev/null || true; tmux kill-session -t gunshi 2>/dev/null || true; tmux kill-session -t multiagent 2>/dev/null || true"
)
echo   [OK] Stop step finished
echo.

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "STAMP=%%I"
if not defined STAMP set "STAMP=%RANDOM%%RANDOM%"
for %%I in ("%SCRIPT_DIR%") do set "INSTALL_DIR_NAME=%%~nxI"
for %%I in ("%SCRIPT_DIR%\..") do set "PARENT_DIR=%%~fI"
set "BACKUP_ROOT=%PARENT_DIR%\%INSTALL_DIR_NAME%-userdata-backup-%STAMP%"

echo   [3/4] Preparing personal data handling...
if "%PRESERVE_DATA%"=="1" (
    mkdir "%BACKUP_ROOT%" >nul 2>&1
    for %%R in (
        "config\settings.yaml"
        "dashboard.md"
    ) do (
        if exist "%SCRIPT_DIR%\%%~R" (
            mkdir "%BACKUP_ROOT%\%%~dpR" >nul 2>&1
            copy /Y "%SCRIPT_DIR%\%%~R" "%BACKUP_ROOT%\%%~R" >nul
        )
    )
    for %%D in (
        ".claude"
        ".codex"
        ".shogunate"
        "projects"
        "context\local"
        "instructions\local"
        "skills\local"
        "queue"
        "logs"
    ) do (
        if exist "%SCRIPT_DIR%\%%~D" (
            robocopy "%SCRIPT_DIR%\%%~D" "%BACKUP_ROOT%\%%~D" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS >nul
        )
    )
    echo   [OK] Personal data preserved at:
    echo        %BACKUP_ROOT%
) else (
    echo   [INFO] All personal data in this install will be deleted
)
echo.

echo   [4/4] Scheduling file removal...
set "CLEANUP_SCRIPT=%TEMP%\multi-agent-shognate-uninstall-%RANDOM%%RANDOM%.cmd"
(
    echo @echo off
    echo setlocal EnableExtensions
    echo ping -n 3 127.0.0.1 ^>nul
    echo del /f /q "%SCRIPT_DIR%\%UNINSTALLER_NAME%" ^>nul 2^>^&1
    echo for /d %%%%D in ^("%SCRIPT_DIR%\*"^) do rmdir /s /q "%%%%~fD" ^>nul 2^>^&1
    echo del /f /q "%SCRIPT_DIR%\*" ^>nul 2^>^&1
    echo for /f %%%%F in ^('dir /b /a "%SCRIPT_DIR%" 2^>nul'^) do goto :retry
    echo goto :done
    echo :retry
    echo ping -n 3 127.0.0.1 ^>nul
    echo del /f /q "%SCRIPT_DIR%\%UNINSTALLER_NAME%" ^>nul 2^>^&1
    echo for /d %%%%D in ^("%SCRIPT_DIR%\*"^) do rmdir /s /q "%%%%~fD" ^>nul 2^>^&1
    echo del /f /q "%SCRIPT_DIR%\*" ^>nul 2^>^&1
    echo :done
    echo del /f /q "%%~f0" ^>nul 2^>^&1
) > "%CLEANUP_SCRIPT%"

start "" cmd /c "%CLEANUP_SCRIPT%"

echo.
echo   [OK] Uninstall scheduled.
if "%PRESERVE_DATA%"=="1" (
    echo   Preserved data:
    echo     %BACKUP_ROOT%
    echo   You can reinstall cleanly into the same folder later and restore from that backup if needed.
 ) else (
    echo   Install files and personal data in this folder will be fully removed.
    echo   You can reinstall cleanly into the same folder later.
)
echo.
echo   This window can now be closed.
echo.
exit /b 0
