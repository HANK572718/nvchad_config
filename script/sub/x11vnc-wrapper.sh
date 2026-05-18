#!/bin/bash
# x11vnc wrapper: 持續偵測當前 active VT 的 Xorg，自動切換 x11vnc
# 支援：登入/登出/切換帳號/GDM greeter，始終顯示螢幕上實際可見的畫面
#
# 原理：
#   1. 讀取 /sys/class/tty/tty0/active 取得當前 active VT（如 tty1）
#   2. 找到在該 VT 上執行的 Xorg 進程（從 cmdline 的 vt 參數判斷）
#   3. 用 ss 配對該 PID 擁有的 X11 socket 取得 display 編號
#   4. 從 cmdline 取得 -auth 路徑
#   5. 偵測到變化時重啟 x11vnc

RFBAUTH="/etc/x11vnc/passwd"
RFBPORT=5900
VNC_PID=""

get_active_xorg() {
    # 取得當前 active VT
    local active_vt
    active_vt=$(cat /sys/class/tty/tty0/active 2>/dev/null)
    [ -z "$active_vt" ] && return

    # 將 ttyN 轉為數字 N
    local vt_num="${active_vt#tty}"

    # 找到在此 VT 上的 Xorg
    for pid in $(pgrep -x Xorg); do
        local xorg_vt
        xorg_vt=$(tr '\0' '\n' < /proc/"$pid"/cmdline 2>/dev/null | grep -oP '^vt\K[0-9]+$')
        [ "$xorg_vt" != "$vt_num" ] && continue

        # 找到了，取 auth
        local auth
        auth=$(tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null | grep -oP '(?<=-auth )\S+')
        [ -z "$auth" ] && continue

        # 用 ss 找此 PID listen 的 X11 socket
        local display
        display=$(ss -xlp 2>/dev/null | grep "pid=${pid}," | grep -oP '\.X11-unix/X\K[0-9]+' | head -1)
        [ -z "$display" ] && continue

        echo ":${display} ${auth}"
        return
    done
}

cleanup() {
    [ -n "$VNC_PID" ] && kill "$VNC_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT

CURRENT_STATE=""

while true; do
    NEW_STATE=$(get_active_xorg)

    if [ -z "$NEW_STATE" ]; then
        sleep 2
        continue
    fi

    if [ "$NEW_STATE" != "$CURRENT_STATE" ]; then
        DISPLAY_NUM=$(echo "$NEW_STATE" | awk '{print $1}')
        XAUTH=$(echo "$NEW_STATE" | awk '{print $2}')

        echo "$(date): 切換至 display=$DISPLAY_NUM auth=$XAUTH (舊: ${CURRENT_STATE:-無})"

        # 停止舊的 x11vnc
        if [ -n "$VNC_PID" ]; then
            echo "$(date): 停止舊的 x11vnc (PID=$VNC_PID)"
            kill "$VNC_PID" 2>/dev/null
            wait "$VNC_PID" 2>/dev/null
        fi

        CURRENT_STATE="$NEW_STATE"

        # 啟動新的 x11vnc
        /usr/bin/x11vnc -display "$DISPLAY_NUM" -auth "$XAUTH" \
            -rfbauth "$RFBAUTH" -rfbport "$RFBPORT" \
            -forever -noxdamage -repeat -shared &
        VNC_PID=$!
        echo "$(date): 啟動 x11vnc (PID=$VNC_PID) display=$DISPLAY_NUM auth=$XAUTH"
    fi

    sleep 3
done
