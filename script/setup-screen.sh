#!/bin/bash
# setup-screen.sh — 螢幕 / 顯示 / VNC 一鍵設定（互動式）
#
# 整合所有「螢幕相關」的部署，跨平台自適應：
#   [x11]     強制 display manager 使用 X11（讓 x11vnc 在任何平台都可用）
#             - GDM / SDDM / Raspberry Pi labwc → X11
#   [display] 顯示設定
#             - 平台偵測 jetson-orin / jetson-legacy / raspberry-pi /
#               nvidia-desktop / amd / intel / unknown
#             - jetson-orin：部署 xorg.conf 強制 1080p@60Hz
#               （DP→HDMI 被動轉接器修復）
#             - 其餘平台：不動 xorg.conf，由驅動自動偵測
#             - 所有平台：autostart 跑 xhost +local: 讓本機帳號可開 GUI
#   [vnc]     x11vnc VNC server
#             - 安裝 x11vnc + 設密碼 + 安裝 wrapper（auto VT 切換、SHM-safe）
#             - 啟用 systemd 服務開機自啟動
#
# 互動模式：
#   1. 逐步互動（step） — 問一個做一個
#   2. 一次問完（batch） — 把全部問題先問完再依序執行
#
# CLI 參數（完全跳過互動）：
#   sudo bash setup-screen.sh --all              # x11 + display + VNC
#   sudo bash setup-screen.sh --x11              # 只強制 X11
#   sudo bash setup-screen.sh --display          # 只裝 display
#   sudo bash setup-screen.sh --vnc              # 只裝 VNC
#   sudo bash setup-screen.sh --all --reboot
#   sudo bash setup-screen.sh --vnc --reset-vnc-password
#
# 不帶參數時進入互動選單：
#   sudo bash ~/.config/nvim/script/setup-screen.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUB_DIR="$SCRIPT_DIR/sub"

# === helper ===
ask_yn() {
    local prompt="$1" default="${2:-Y}" hint="[Y/n]" ans
    [ "$default" = "N" ] && hint="[y/N]"
    read -rp "  $prompt $hint: " ans
    ans="${ans:-$default}"
    [[ "$ans" =~ ^[Yy] ]]
}

banner() {
    cat <<'EOF'

================================================
 螢幕 / 顯示 / VNC 設定（setup-screen.sh）
================================================

可設定項目（皆為 opt-in，預設都建議 Y）：
  [x11]     強制 display manager 使用 X11（讓 x11vnc 在任何平台可用）
  [display] 顯示設定（平台自適應 xorg.conf + xhost autostart）
  [vnc]     x11vnc VNC server（systemd 服務 + 自動 VT 切換）

支援平台：Jetson Orin、Jetson Legacy (Nano/TX2/Xavier)、Raspberry Pi、
          x86 桌機 (NVIDIA / AMD / Intel)

EOF
}

run_x11() {
    echo ""
    echo "------------------------------------------------"
    echo " >>> 強制 X11 session"
    echo "------------------------------------------------"
    bash "$SUB_DIR/force-x11.sh"
}

run_display() {
    echo ""
    echo "------------------------------------------------"
    echo " >>> 執行 display 設定"
    echo "------------------------------------------------"
    bash "$SUB_DIR/setup-display.sh"
}

run_vnc() {
    echo ""
    echo "------------------------------------------------"
    echo " >>> 執行 VNC 設定"
    echo "------------------------------------------------"
    VNC_RESET_PASSWORD="$VNC_RESET_PASSWORD" bash "$SUB_DIR/setup_x11vnc.sh"
}

maybe_reboot() {
    if [ "$DO_REBOOT" = "1" ]; then
        echo ""
        echo "5 秒後重開機，按 Ctrl-C 取消..."
        sleep 5
        sudo reboot
    fi
}

# === 互動：逐步模式（step）===
mode_step() {
    banner
    echo "[模式：逐步互動 — 問一個做一個]"

    if ask_yn "要強制 display manager 使用 X11 嗎？（建議）" Y; then
        run_x11
    else
        echo "  跳過 X11 強制"
    fi

    if ask_yn "要設定 display 嗎？" Y; then
        run_display
    else
        echo "  跳過 display"
    fi

    if ask_yn "要設定 VNC 嗎？" Y; then
        if [ -f /etc/x11vnc/passwd ]; then
            if ask_yn "  /etc/x11vnc/passwd 已存在，要重設密碼嗎？" N; then
                export VNC_RESET_PASSWORD=1
            fi
        fi
        run_vnc
    else
        echo "  跳過 VNC"
    fi

    if ask_yn "全部完成，要立刻重開機嗎？" N; then
        DO_REBOOT=1
    fi
    maybe_reboot
}

# === 互動：一次問完模式（batch）===
mode_batch() {
    banner
    echo "[模式：一次問完 — 把問題問完再依序執行]"
    echo ""

    local do_x11=0 do_display=0 do_vnc=0 reset_pw=0 reboot=0

    ask_yn "要強制 display manager 使用 X11 嗎？（建議）" Y && do_x11=1
    ask_yn "要設定 display 嗎？" Y && do_display=1
    ask_yn "要設定 VNC 嗎？" Y && do_vnc=1
    if [ "$do_vnc" = "1" ] && [ -f /etc/x11vnc/passwd ]; then
        ask_yn "  /etc/x11vnc/passwd 已存在，要重設密碼嗎？" N && reset_pw=1
    fi
    ask_yn "全部完成後要重開機嗎？" N && reboot=1

    echo ""
    echo "------------------------------------------------"
    echo " 即將執行（請最後確認）："
    echo "   強制 X11             : $([ "$do_x11" = 1 ] && echo YES || echo NO)"
    echo "   display 設定         : $([ "$do_display" = 1 ] && echo YES || echo NO)"
    echo "   VNC 設定             : $([ "$do_vnc" = 1 ] && echo YES || echo NO)"
    [ "$do_vnc" = "1" ] && echo "   重設 VNC 密碼        : $([ "$reset_pw" = 1 ] && echo YES || echo NO)"
    echo "   完成後重開機         : $([ "$reboot" = 1 ] && echo YES || echo NO)"
    echo "------------------------------------------------"
    ask_yn "確認執行？" Y || { echo "已取消"; exit 0; }

    [ "$do_x11" = "1" ] && run_x11
    [ "$do_display" = "1" ] && run_display
    if [ "$do_vnc" = "1" ]; then
        [ "$reset_pw" = "1" ] && export VNC_RESET_PASSWORD=1
        run_vnc
    fi
    [ "$reboot" = "1" ] && DO_REBOOT=1
    maybe_reboot
}

# === CLI 模式（非互動）===
mode_cli() {
    [ "$DO_X11" = "1" ] && run_x11
    [ "$DO_DISPLAY" = "1" ] && run_display
    if [ "$DO_VNC" = "1" ]; then
        [ "$RESET_VNC_PASSWORD" = "1" ] && export VNC_RESET_PASSWORD=1
        run_vnc
    fi
    maybe_reboot
}

usage() {
    cat <<EOF
用法：sudo bash $0 [選項]

不帶選項：進入互動選單（可選逐步或一次問完）

選項：
  -a, --all                  x11 + display + VNC 全裝
  -x, --x11                  只強制 X11
  -d, --display              只裝 display
  -v, --vnc                  只裝 VNC
      --no-x11               搭配 --all 使用，跳過 X11 強制
      --reset-vnc-password   即使 /etc/x11vnc/passwd 已存在也重設
  -r, --reboot               執行完自動重開機
  -h, --help                 本說明

支援平台：Jetson Orin、Jetson Legacy、Raspberry Pi、x86 桌機 (NVIDIA/AMD/Intel)
EOF
}

# === 參數解析 ===
DO_X11=0
DO_DISPLAY=0
DO_VNC=0
DO_REBOOT=0
RESET_VNC_PASSWORD=0
EXPLICIT_CLI=0
SKIP_X11=0

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all)               DO_X11=1; DO_DISPLAY=1; DO_VNC=1; EXPLICIT_CLI=1 ;;
        -x|--x11)               DO_X11=1; EXPLICIT_CLI=1 ;;
        -d|--display)           DO_DISPLAY=1; EXPLICIT_CLI=1 ;;
        -v|--vnc)               DO_VNC=1; EXPLICIT_CLI=1 ;;
        --no-x11)               SKIP_X11=1 ;;
        --reset-vnc-password)   RESET_VNC_PASSWORD=1 ;;
        -r|--reboot)            DO_REBOOT=1 ;;
        -h|--help)              usage; exit 0 ;;
        *) echo "未知參數: $1"; usage; exit 1 ;;
    esac
    shift
done

[ "$SKIP_X11" = "1" ] && DO_X11=0

# === 進入點 ===
if [ "$EXPLICIT_CLI" = "1" ]; then
    mode_cli
    exit 0
fi

banner
echo "請選擇互動模式："
echo "  [1] 逐步互動：問一個做一個"
echo "  [2] 一次問完：把全部問題問完再執行"
echo "  [q] 取消"
echo ""
read -rp "選擇 [1/2/q]: " choice
case "$choice" in
    1) mode_step ;;
    2) mode_batch ;;
    q|Q) echo "已取消"; exit 0 ;;
    *) echo "無效選擇"; exit 1 ;;
esac
