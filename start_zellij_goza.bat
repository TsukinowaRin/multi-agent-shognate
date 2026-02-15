@echo off
REM zellij 起動（御座の間テンプレート）
REM ダブルクリックで実行すると zellij pure mode で全エージェントが表示されます

wsl -d Ubuntu -e bash -c "cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && bash scripts/goza_zellij.sh --template goza_room"
