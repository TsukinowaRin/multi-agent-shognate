@echo off
REM zellij hybrid 起動（御座の間テンプレート）
REM ダブルクリックで実行すると tmux backend + zellij ui で全エージェントが表示されます
REM （注: pure zellij modeはWindowsバッチから起動できないためhybridを使用）

wsl -d Ubuntu -e bash -c "cd \"$(wslpath -u '%~dp0')\" && bash scripts/goza_hybrid.sh --template goza_room"
