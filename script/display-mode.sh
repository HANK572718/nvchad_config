#!/bin/bash
# display-mode.sh — 套用 DP-0 顯示設定
#
# 強制 1920x1080@60Hz，確保 DP→HDMI 被動式轉接器可正常輸出畫面。
# 背景：Jetson Orin Nano 只有 DisplayPort 輸出，接 HDMI 螢幕需用轉接器。
# Driver 預設會選螢幕最高頻率（如 120Hz），但被動式轉接器無法傳輸，
# 導致螢幕顯示 "No Signal"。此腳本強制降為 60Hz 解決此問題。
#
# 部署位置：/usr/local/bin/display-mode.sh
# 原始碼：~/.config/nvim/script/display-mode.sh

# --- 解析 DISPLAY / XAUTHORITY ---
# 優先使用環境變數，否則 fallback 到 VT 偵測（同 x11vnc-wrapper.sh 邏輯）
resolve_display() {
    if [ -n "$DISPLAY" ] && [ -n "$XAUTHORITY" ]; then
        return 0
    fi

    local active_vt vt_num pid xorg_vt auth display
    active_vt=$(cat /sys/class/tty/tty0/active 2>/dev/null)
    [ -z "$active_vt" ] && return 1

    vt_num="${active_vt#tty}"

    for pid in $(pgrep -x Xorg 2>/dev/null); do
        xorg_vt=$(tr '\0' '\n' < /proc/"$pid"/cmdline 2>/dev/null | grep -oP '^vt\K[0-9]+$')
        [ "$xorg_vt" != "$vt_num" ] && continue

        auth=$(tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null | grep -oP '(?<=-auth )\S+')
        [ -z "$auth" ] && continue

        display=$(ss -xlp 2>/dev/null | grep "pid=${pid}," | grep -oP '\.X11-unix/X\K[0-9]+' | head -1)
        [ -z "$display" ] && continue

        export DISPLAY=":${display}"
        export XAUTHORITY="${auth}"
        return 0
    done

    return 1
}

if ! resolve_display; then
    echo "錯誤：找不到執行中的 X session" >&2
    exit 1
fi

xrandr --output DP-0 --mode 1920x1080 --rate 60
echo "完成：DP-0 設定為 1920x1080@60Hz（DISPLAY=$DISPLAY）"
