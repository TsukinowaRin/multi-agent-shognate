@echo off
REM pure zellij 起動（御座の間テンプレート）
REM ダブルクリックで実行すると pure zellij mode で全エージェントが表示されます
REM backend=zellij, ui=zellij（ネイティブZellijモード）

wsl -d Ubuntu -e bash -c "cd \"$(wslpath -u '%~dp0')\" && bash scripts/goza_zellij.sh --template goza_room"
