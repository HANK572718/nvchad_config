#!/bin/bash
# setup-display.sh — 部署顯示設定（平台自適應）
#
# 自動偵測平台：
#   jetson-orin    : DP-only。部署 Orin 專用 xorg.conf 解決 DP→HDMI 被動轉接器
#                    無法傳輸 >60Hz 訊號的問題；display-mode.sh 強制 1080p@60Hz
#   jetson-legacy  : Jetson Nano/TX2/Xavier 等舊款，有 HDMI 直出。
#                    不部署 xorg.conf，避免 ConnectedMonitor=DP-0 把 HDMI 鎖死
#   raspberry-pi   : 不部署 xorg.conf，Pi 內建驅動會自動 EDID
#   nvidia-desktop / amd / intel : x86 桌機，全部跳過 xorg.conf，驅動自動處理
#   unknown        : 保守跳過
#
# 通常透過上層 setup-screen.sh 呼叫，亦可單獨執行：
#   sudo bash ~/.config/nvim/script/sub/setup-display.sh
#
# 文件：~/.config/nvim/docs/setup-screen.md

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

AUTOSTART_USER="${SUDO_USER:-${USER}}"
AUTOSTART_HOME=$(getent passwd "$AUTOSTART_USER" | cut -d: -f6)

detect_platform() {
    local model=""
    if [ -r /proc/device-tree/model ]; then
        model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    fi
    case "$model" in
        *Orin*|*orin*)               echo "jetson-orin"; return ;;
        *Raspberry*|*raspberry*)     echo "raspberry-pi"; return ;;
    esac
    if [ -f /etc/nv_tegra_release ] || echo "$model" | grep -qiE 'jetson|tegra'; then
        echo "jetson-legacy"; return
    fi
    local gpu
    gpu=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
    case "$gpu" in
        *NVIDIA*|*nVidia*)            echo "nvidia-desktop" ;;
        *AMD*|*ATI*|*Radeon*)         echo "amd" ;;
        *Intel*)                      echo "intel" ;;
        *)                            echo "unknown" ;;
    esac
}

PLATFORM=$(detect_platform)
echo "=============================="
echo " 偵測到平台：$PLATFORM"
echo "=============================="
echo ""

# === 1. xorg.conf 部署（僅 jetson-orin）===
if [ "$PLATFORM" = "jetson-orin" ]; then
    echo "[1/4] 備份現有 xorg.conf..."
    if [ -f /etc/X11/xorg.conf ]; then
        BACKUP="/etc/X11/xorg.conf.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp /etc/X11/xorg.conf "$BACKUP"
        echo "  已備份至 $BACKUP"
    else
        echo "  /etc/X11/xorg.conf 不存在，跳過備份"
    fi

    echo "[2/4] 部署 Jetson Orin 專用 xorg.conf..."
    sudo cp "$PROJECT_DIR/configs/xorg.conf.jetson-orin" /etc/X11/xorg.conf
    echo "  已部署 /etc/X11/xorg.conf"
else
    echo "[1-2/4] $PLATFORM 平台，跳過 xorg.conf 部署"
    # 主動清除可能誤部署的 Jetson Orin xorg.conf 殘留
    #   - 含 Tegra0 / ConnectedMonitor "DP-0"，會在桌機 + HDMI 螢幕造成 No Signal
    #   - 也會把 Jetson Nano (HDMI 直出) 鎖到不存在的 DP-0 上
    if [ -f /etc/X11/xorg.conf ] && grep -q 'Identifier[[:space:]]*"Tegra0"' /etc/X11/xorg.conf 2>/dev/null; then
        BACKUP="/etc/X11/xorg.conf.tegra-leftover.$(date +%Y%m%d_%H%M%S)"
        sudo mv /etc/X11/xorg.conf "$BACKUP"
        echo "  發現殘留的 Jetson Orin xorg.conf，已移至 $BACKUP（需重開機生效）"
    fi
fi

# === 3. display-mode 腳本（所有平台都裝，腳本內部自我判斷）===
echo "[3/4] 部署 display-mode 腳本..."
sudo cp "$SCRIPT_DIR/display-mode.sh" /usr/local/bin/display-mode.sh
sudo chmod +x /usr/local/bin/display-mode.sh
sudo cp "$SCRIPT_DIR/display-mode-autostart.sh" /usr/local/bin/display-mode-autostart.sh
sudo chmod +x /usr/local/bin/display-mode-autostart.sh
echo "  已部署 /usr/local/bin/display-mode.sh"
echo "  已部署 /usr/local/bin/display-mode-autostart.sh"

# === 4. autostart：登入後執行 xhost +local: ===
echo "[4/4] 設定 autostart..."
AUTOSTART_DIR="$AUTOSTART_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/set-resolution.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Display Mode
Comment=xhost +local: (all platforms); plus 60Hz force on Jetson Orin
Exec=/usr/local/bin/display-mode-autostart.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$AUTOSTART_DIR"
fi
echo "  已寫入 $AUTOSTART_DIR/set-resolution.desktop"

# === 清除舊版的副作用：/etc/environment 的 DISPLAY=:0 ===
# 該設定會讓所有 SSH 登入也帶 DISPLAY=:0，造成 GUI 工具誤連 gdm 的 X server
if grep -q '^DISPLAY=:0$' /etc/environment 2>/dev/null; then
    sudo sed -i '/^DISPLAY=:0$/d' /etc/environment
    echo "  已從 /etc/environment 移除 DISPLAY=:0（會干擾 SSH session）"
fi

echo ""
echo "=============================="
echo " 顯示設定部署完成（平台: $PLATFORM）"
echo ""
case "$PLATFORM" in
    jetson-orin)
        echo " Jetson Orin 模式："
        echo "   - 已部署 Orin 專用 xorg.conf"
        echo "   - 重開機讓 xorg.conf 變更生效：sudo reboot"
        echo "   - 不重開機即時套用：/usr/local/bin/display-mode.sh"
        ;;
    jetson-legacy)
        echo " Jetson Legacy 模式 (Nano/TX2/Xavier 等)："
        echo "   - 未動 xorg.conf，由 L4T 驅動自動 EDID"
        echo "   - autostart 已就緒"
        ;;
    raspberry-pi)
        echo " Raspberry Pi 模式："
        echo "   - 未動 xorg.conf，Pi 驅動自動 EDID"
        echo "   - autostart 已就緒"
        ;;
    nvidia-desktop|amd|intel)
        echo " 桌機模式 ($PLATFORM)："
        echo "   - 未動 xorg.conf，驅動自動 EDID"
        echo "   - 若先前曾誤部署 Jetson xorg.conf，已移至備份檔（需 reboot 生效）"
        ;;
    *)
        echo " 未知平台：建議手動確認 /etc/X11/xorg.conf 是否需要"
        ;;
esac
echo "=============================="
