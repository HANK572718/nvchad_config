#!/bin/bash
# setup-display.sh — 一鍵部署顯示設定（DP-0 60Hz 修正）
#
# 部署內容：
#   - configs/xorg.conf → /etc/X11/xorg.conf（備份舊的）
#   - script/display-mode.sh → /usr/local/bin/display-mode.sh
#   - script/display-mode-autostart.sh → /usr/local/bin/display-mode-autostart.sh
#   - ~/.config/autostart/set-resolution.desktop（取代舊的）
#   - /etc/environment 加入 DISPLAY=:0（全域，讓所有用戶可執行 GUI 程式）
#
# 使用方式：
#   sudo bash ~/.config/nvim/script/setup-display.sh
#
# 背景說明：
#   Jetson Orin Nano 只有 DisplayPort 輸出，接 HDMI 螢幕需用 DP→HDMI 轉接器。
#   Driver 預設選螢幕最高頻率（可能 120Hz），被動式轉接器無法傳輸導致無畫面。
#   此腳本部署 60Hz 強制設定，並在每次開機後自動套用。

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

AUTOSTART_USER="${SUDO_USER:-${USER}}"
AUTOSTART_HOME=$(getent passwd "$AUTOSTART_USER" | cut -d: -f6)

echo "[1/5] 備份現有 xorg.conf..."
if [ -f /etc/X11/xorg.conf ]; then
    BACKUP="/etc/X11/xorg.conf.bak.$(date +%Y%m%d_%H%M%S)"
    sudo cp /etc/X11/xorg.conf "$BACKUP"
    echo "  已備份至 $BACKUP"
else
    echo "  /etc/X11/xorg.conf 不存在，跳過備份"
fi

echo "[2/5] 部署 xorg.conf..."
sudo cp "$PROJECT_DIR/configs/xorg.conf" /etc/X11/xorg.conf
echo "  已部署 /etc/X11/xorg.conf"

echo "[3/5] 部署 display-mode 腳本..."
sudo cp "$SCRIPT_DIR/display-mode.sh" /usr/local/bin/display-mode.sh
sudo chmod +x /usr/local/bin/display-mode.sh
sudo cp "$SCRIPT_DIR/display-mode-autostart.sh" /usr/local/bin/display-mode-autostart.sh
sudo chmod +x /usr/local/bin/display-mode-autostart.sh
echo "  已部署 /usr/local/bin/display-mode.sh"
echo "  已部署 /usr/local/bin/display-mode-autostart.sh"

echo "[4/5] 設定全域 DISPLAY 環境變數..."
if grep -q "^DISPLAY=" /etc/environment 2>/dev/null; then
    echo "  DISPLAY 已存在，跳過"
else
    echo "DISPLAY=:0" >> /etc/environment
    echo "  已加入 DISPLAY=:0 至 /etc/environment"
fi

echo "[5/5] 設定 autostart..."
AUTOSTART_DIR="$AUTOSTART_HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/set-resolution.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Display Mode
Comment=Force DP-0 to 60Hz for DP-to-HDMI adapter compatibility
Exec=/usr/local/bin/display-mode-autostart.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER" "$AUTOSTART_DIR"
fi
echo "  已寫入 $AUTOSTART_DIR/set-resolution.desktop"

echo ""
echo "=============================="
echo " 顯示設定部署完成"
echo ""
echo " 立即套用（不需重開機）："
echo "   /usr/local/bin/display-mode.sh"
echo ""
echo " 若要讓 xorg.conf 變更生效，需重開機："
echo "   sudo reboot"
echo ""
echo " 說明："
echo "   - 只有 DisplayPort 孔可輸出影像（USB-C 不支援顯示）"
echo "   - 接 HDMI 螢幕請用 DP→HDMI 轉接器"
echo "   - 每次開機後自動套用 1920x1080@60Hz"
echo "   - 所有本機用戶可執行 GUI/Qt 程式（xhost +local: 已設定）"
echo "=============================="
