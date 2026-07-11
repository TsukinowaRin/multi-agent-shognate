@echo off
setlocal

where wsl.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] wsl.exe が見つかりません。WSL上で android/tools/setup_android_ssh.sh を実行してください。
  exit /b 1
)

for /f "usebackq delims=" %%I in (`wsl.exe wslpath "%~dp0..\.."`) do set "WSL_ROOT=%%I"

wsl.exe bash -lc "cd '%WSL_ROOT%' && bash android/tools/setup_android_ssh.sh %*"
exit /b %errorlevel%
