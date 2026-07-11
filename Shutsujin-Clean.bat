@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
call "%SCRIPT_DIR%\shogunate_mod\windows\shutsujin_clean.bat" %*
exit /b %ERRORLEVEL%
