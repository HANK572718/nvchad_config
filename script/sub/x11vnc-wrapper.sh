#!/bin/bash
# x11vnc wrapper: 持續偵測當前 active VT 的 Xorg，自動切換 x11vnc
# 支援：登入/登出/切換帳號/GDM greeter，始終顯示螢幕上實際可見的畫面
#
# 原理：
#   1. 讀取 /sys/class/tty/tty0/active 取得當前 active VT（如 tty1）
#   2. 找到在該 VT 上執行的 Xorg 進程（從 cmdline 的 vt 參數判斷）
#   3. 用 ss 配對該 PID 擁有的 X11 socket 取得 display 編號
#   4. 從 cmdline 取得 -auth 路徑
#   5. 偵測到變化 OR x11vnc 死亡時 重啟 x11vnc
#
# x11vnc 啟動旗標說明（重點）：
#   -noshm   不用 MIT-SHM 共享記憶體做螢幕 polling。
#            原因：wrapper 以 root 跑、目標 Xorg 由 gdm/user 擁有，
#            X server 的 SHM 段只允許建立者那個 UID 存取，
#            root attach 會被拒 (BadAccess on X_ShmAttach) 導致 x11vnc 直接退出。
#
# 部署位置：/usr/local/bin/x11vnc-wrapper.sh
# 原始碼：~/.config/nvim/script/sub/x11vnc-wrapper.sh
# 文件：~/.config/nvim/docs/setup-screen.md

RFBAUTH="/etc/x11vnc/passwd"
RFBPORT=5900
VNC_PID=""

get_active_xorg() {
    local active_vt
    active_vt=$(cat /sys/class/tty/tty0/active 2>/dev/null)
    [ -z "$active_vt" ] && return
    local vt_num="${active_vt#tty}"

    for pid in $(pgrep -x Xorg); do
        local xorg_vt
        xorg_vt=$(tr '\0' '\n' < /proc/"$pid"/cmdline 2>/dev/null | grep -oP '^vt\K[0-9]+$')
        [ "$xorg_vt" != "$vt_num" ] && continue

        local auth
        auth=$(tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null | grep -oP '(?<=-auth )\S+')
        [ -z "$auth" ] && continue

        local display
        display=$(ss -xlp 2>/dev/null | grep "pid=${pid}," | grep -oP '\.X11-unix/X\K[0-9]+' | head -1)
        [ -z "$display" ] && continue

        echo ":${display} ${auth}"
        return
    done
}

start_x11vnc() {
    local display_num="$1" xauth="$2"
    /usr/bin/x11vnc -display "$display_num" -auth "$xauth" \
        -rfbauth "$RFBAUTH" -rfbport "$RFBPORT" \
        -noshm \
        -forever -noxdamage -repeat -shared -quiet &
    VNC_PID=$!
    echo "$(date): 啟動 x11vnc (PID=$VNC_PID) display=$display_num auth=$xauth"
}

vnc_alive() {
    [ -n "$VNC_PID" ] && kill -0 "$VNC_PID" 2>/dev/null
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

    DISPLAY_NUM=$(echo "$NEW_STATE" | awk '{print $1}')
    XAUTH=$(echo "$NEW_STATE" | awk '{print $2}')

    if [ "$NEW_STATE" != "$CURRENT_STATE" ]; then
        echo "$(date): 切換至 display=$DISPLAY_NUM auth=$XAUTH (舊: ${CURRENT_STATE:-無})"

        if vnc_alive; then
            echo "$(date): 停止舊的 x11vnc (PID=$VNC_PID)"
            kill "$VNC_PID" 2>/dev/null
            wait "$VNC_PID" 2>/dev/null
        fi
        VNC_PID=""

        CURRENT_STATE="$NEW_STATE"
        start_x11vnc "$DISPLAY_NUM" "$XAUTH"
    elif ! vnc_alive; then
        # 目標 Xorg 沒變但 x11vnc 自己掛了 → 重啟
        echo "$(date): 偵測到 x11vnc 已死，重啟中..."
        VNC_PID=""
        start_x11vnc "$DISPLAY_NUM" "$XAUTH"
        sleep 2
    fi

    sleep 3
done
