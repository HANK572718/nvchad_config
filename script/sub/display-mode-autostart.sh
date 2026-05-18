#!/bin/bash
# display-mode-autostart.sh — 開機自動登入後執行
#
# 動作：
#   1. xhost +local: — 讓所有本機帳號可執行 GUI/Qt 程式
#   2. 呼叫 display-mode.sh（Jetson 上強制 60Hz；桌機 no-op）
#
# 由 ~/.config/autostart/set-resolution.desktop 呼叫。
#
# 部署位置：/usr/local/bin/display-mode-autostart.sh
# 原始碼：~/.config/nvim/script/sub/display-mode-autostart.sh
# 文件：~/.config/nvim/docs/setup-screen.md

sleep 3

# 授權所有本機帳號存取目前 X display
xhost +local: >/dev/null 2>&1

exec /usr/local/bin/display-mode.sh
