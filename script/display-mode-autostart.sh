#!/bin/bash
# display-mode-autostart.sh — 開機自動登入後套用 60Hz 顯示設定
#
# 由 ~/.config/autostart/set-resolution.desktop 呼叫。
#
# 部署位置：/usr/local/bin/display-mode-autostart.sh
# 原始碼：~/.config/nvim/script/display-mode-autostart.sh

sleep 3
exec /usr/local/bin/display-mode.sh
