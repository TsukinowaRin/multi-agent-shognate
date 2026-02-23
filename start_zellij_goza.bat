@echo off
REM zellij hybrid 起動（御座の間テンプレート）
REM ダブルクリックで実行すると tmux backend + zellij ui で全エージェントが表示されます
REM （pure zellij modeを使いたい場合は start_zellij_pure.bat を使用）

wsl -d Ubuntu -e bash -c "cd \"$(wslpath -u '%~dp0')\" && bash scripts/goza_hybrid.sh --template goza_room"
