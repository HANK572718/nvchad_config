#!/bin/bash
# display-mode.sh — 套用顯示模式（平台自適應）
#
# 行為：
#   - Jetson：把目前 connected 的 output 強制設為 1920x1080@60Hz
#             解決 Jetson Orin Nano 的 DP→HDMI 被動轉接器無法傳輸 >60Hz 訊號的問題
#   - 桌機 (NVIDIA/AMD/Intel)：no-op，由驅動 + 桌面環境自動處理顯示模式
#
# 部署位置：/usr/local/bin/display-mode.sh
# 原始碼：~/.config/nvim/script/sub/display-mode.sh

detect_platform() {
    if [ -f /etc/nv_tegra_release ]; then echo "jetson"; return; fi
    if [ -r /proc/device-tree/model ] && grep -qiE 'jetson|tegra' /proc/device-tree/model 2>/dev/null; then
        echo "jetson"; return
    fi
    echo "desktop"
}

# --- 解析 DISPLAY / XAUTHORITY（從 active VT 上的 Xorg 找） ---
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

PLATFORM=$(detect_platform)

if [ "$PLATFORM" != "jetson" ]; then
    echo "平台 ($PLATFORM)：未套用 mode override，由驅動自動處理"
    exit 0
fi

if ! resolve_display; then
    echo "錯誤：找不到執行中的 X session" >&2
    exit 1
fi

# 動態抓出第一個 connected 的 output（不再寫死 DP-0）
CONNECTED=$(xrandr 2>/dev/null | awk '/ connected/ {print $1; exit}')
if [ -z "$CONNECTED" ]; then
    echo "錯誤：xrandr 找不到任何已連接的輸出" >&2
    exit 1
fi

xrandr --output "$CONNECTED" --mode 1920x1080 --rate 60
echo "完成：$CONNECTED 設定為 1920x1080@60Hz（DISPLAY=$DISPLAY）"
