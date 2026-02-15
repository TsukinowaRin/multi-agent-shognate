@echo off
REM zellij 起動（御座の間テンプレート）
REM ダブルクリックで実行すると zellij pure mode で全エージェントが表示されます

cd /d "%~dp0"
wsl -d Ubuntu -e bash -c "cd $(pwd) && bash scripts/goza_zellij.sh --template goza_room"
