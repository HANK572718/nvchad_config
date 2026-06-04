#!/bin/bash
# show-status.sh — 一鍵診斷螢幕 / X11 / VNC 當前狀態
#
# 適用情境：
#   - 想知道目前 session 是 X11 還是 Wayland
#   - 想確認 force-x11 設定有沒有真的生效
#   - 想確認 x11vnc 是否在 listen
#   - 故障排除時看一眼整體狀況
#
# 通常透過上層 setup-screen.sh --status 呼叫，亦可單獨執行：
#   bash ~/.config/nvim/script/sub/show-status.sh
#
# 文件：~/.config/nvim/docs/setup-screen.md

# 顏色（terminal 才染色）
if [ -t 1 ]; then
    G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[1m'; Z=$'\e[0m'
else
    G=""; Y=""; R=""; B=""; Z=""
fi

ok()    { printf '  %s✓%s %s\n' "$G" "$Z" "$1"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$Z" "$1"; }
bad()   { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; }
info()  { printf '  %s\n' "$1"; }
hdr()   { printf '\n%s== %s ==%s\n' "$B" "$1" "$Z"; }

# === 平台 ===
detect_platform() {
    local model=""
    if [ -r /proc/device-tree/model ]; then
        model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    fi
    case "$model" in
        *Orin*|*orin*)           echo "jetson-orin"; return ;;
        *Raspberry*|*raspberry*) echo "raspberry-pi"; return ;;
    esac
    if [ -f /etc/nv_tegra_release ] || echo "$model" | grep -qiE 'jetson|tegra'; then
        echo "jetson-legacy"; return
    fi
    local gpu
    gpu=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
    case "$gpu" in
        *NVIDIA*|*nVidia*)     echo "nvidia-desktop" ;;
        *AMD*|*ATI*|*Radeon*)  echo "amd" ;;
        *Intel*)               echo "intel" ;;
        *)                     echo "unknown" ;;
    esac
}

hdr "平台"
PLATFORM=$(detect_platform)
info "代號     : $PLATFORM"
if [ -r /proc/device-tree/model ]; then
    info "model    : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
fi
gpu_line=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
[ -n "$gpu_line" ] && info "GPU      : $gpu_line"

# === Session type ===
hdr "Session 類型（X11 vs Wayland）"
SESSION_TYPE=""

# 1) 自己環境變數（tty/SSH 時會是 "tty"，graphical session 才會是 x11/wayland）
if [ -n "$XDG_SESSION_TYPE" ]; then
    info "XDG_SESSION_TYPE = $XDG_SESSION_TYPE （目前這個 shell）"
    case "$XDG_SESSION_TYPE" in
        x11|wayland) SESSION_TYPE="$XDG_SESSION_TYPE" ;;
    esac
fi

# 2) loginctl 找有 seat 的 active session（真正的圖形 session）
if command -v loginctl >/dev/null 2>&1; then
    while read -r sid uid user seat _; do
        [ "$seat" = "-" ] && continue
        stype=$(loginctl show-session "$sid" -p Type --value 2>/dev/null)
        sstate=$(loginctl show-session "$sid" -p State --value 2>/dev/null)
        info "loginctl session $sid (user=$user seat=$seat state=$sstate type=$stype)"
        # 圖形 session 永遠優先於 shell 環境變數
        if [ "$sstate" = "active" ]; then
            case "$stype" in
                x11|wayland) SESSION_TYPE="$stype" ;;
            esac
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
fi

# 3) 直接看是否有 Xorg / wayland compositor 在跑
if pgrep -x Xorg >/dev/null 2>&1; then
    ok "Xorg 進程存在（X11 確定）"
else
    warn "Xorg 進程不存在"
fi
if pgrep -xf 'gnome-shell.*--wayland|wayfire|labwc|sway|Hyprland|weston|kwin_wayland' >/dev/null 2>&1; then
    warn "偵測到 Wayland 合成器在跑"
fi

case "$SESSION_TYPE" in
    x11)     ok "結論：當前是 X11（x11vnc 可正常運作）" ;;
    wayland) bad "結論：當前是 Wayland（x11vnc 無法 attach；請執行 setup-screen.sh --x11 + reboot）" ;;
    "")      warn "結論：無法判定（可能無圖形 session）" ;;
    *)       info "結論：未知 type=$SESSION_TYPE" ;;
esac

# === Xorg 細節 ===
if pgrep -x Xorg >/dev/null 2>&1; then
    hdr "Xorg 細節"
    for pid in $(pgrep -x Xorg); do
        cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
        vt=$(echo "$cmd" | grep -oP 'vt\K[0-9]+' | head -1)
        auth=$(echo "$cmd" | grep -oP '(?<=-auth )\S+')
        disp=$(ss -xlp 2>/dev/null | grep "pid=${pid}," | grep -oP '\.X11-unix/X\K[0-9]+' | head -1)
        owner=$(ps -o user= -p "$pid" 2>/dev/null | xargs)
        info "PID=$pid user=$owner vt=$vt display=:$disp auth=$auth"
    done
fi

# === Display manager 與 X11 強制狀態 ===
hdr "Display Manager"
DM=""
[ -f /etc/X11/default-display-manager ] && DM=$(basename "$(cat /etc/X11/default-display-manager)")
[ -n "$DM" ] && info "default-display-manager : $DM"

# GDM
for conf in /etc/gdm3/custom.conf /etc/gdm/custom.conf; do
    [ -f "$conf" ] || continue
    info "$conf:"
    if grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' "$conf"; then
        ok "  WaylandEnable=false（X11 已強制）"
    elif grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=' "$conf"; then
        warn "  WaylandEnable 存在但不是 false：$(grep -E '^[[:space:]]*WaylandEnable' "$conf")"
    else
        warn "  未設定 WaylandEnable（GDM 預設啟用 Wayland）"
    fi
done

# SDDM
if [ -d /etc/sddm.conf.d ] || [ -f /etc/sddm.conf ]; then
    info "SDDM:"
    if grep -rhE '^[[:space:]]*DisplayServer[[:space:]]*=[[:space:]]*x11' /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null | grep -q .; then
        ok "  DisplayServer=x11"
    else
        warn "  未強制 DisplayServer=x11"
    fi
fi

# Raspberry Pi
if command -v raspi-config >/dev/null 2>&1; then
    info "Raspberry Pi raspi-config 可用 — 建議用 sudo raspi-config nonint do_wayland W1 強制 X11"
fi

# === VNC ===
hdr "x11vnc 服務"
if systemctl list-unit-files x11vnc.service >/dev/null 2>&1 && \
   systemctl cat x11vnc.service >/dev/null 2>&1; then
    state=$(systemctl is-active x11vnc.service 2>/dev/null)
    enabled=$(systemctl is-enabled x11vnc.service 2>/dev/null)
    info "systemd  : state=$state enabled=$enabled"
    [ "$state" = "active" ] && ok "x11vnc.service 執行中" || bad "x11vnc.service 未在執行"
else
    warn "x11vnc.service 未安裝（執行 setup-screen.sh --vnc 來安裝）"
fi

if ss -tlnp 2>/dev/null | grep -q ':5900 '; then
    ok "port 5900 listening"
    ss -tlnp 2>/dev/null | grep ':5900 ' | sed 's/^/    /'
else
    bad "port 5900 沒人 listen（x11vnc 沒跑或 crash 中）"
fi

if [ -f /etc/x11vnc/passwd ]; then
    ok "/etc/x11vnc/passwd 已設定"
else
    warn "/etc/x11vnc/passwd 不存在（需設密碼）"
fi

# === 連線資訊 ===
hdr "連線資訊"
ips=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2": "$4}' | cut -d/ -f1)
if [ -n "$ips" ]; then
    while IFS= read -r line; do
        info "VNC client → ${line%%:*}:5900   ($line)"
    done <<< "$ips"
else
    warn "未抓到 IP（檢查網路）"
fi

echo ""
