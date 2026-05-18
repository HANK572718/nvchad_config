#!/bin/bash
# setup_x11vnc.sh — 安裝並啟動 x11vnc 服務
#
# 動作：安裝 x11vnc、設定密碼、安裝 wrapper、啟用 systemd 服務
#
# 通常透過上層 setup-screen.sh 呼叫，亦可單獨執行：
#   sudo bash ~/.config/nvim/script/sub/setup_x11vnc.sh
#
# 環境變數（供上層批次模式傳入）：
#   VNC_RESET_PASSWORD=1   即使密碼已存在也重設

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/5] 安裝 x11vnc（如果尚未安裝）..."
sudo apt-get install -y x11vnc

echo "[2/5] 設定 VNC 密碼..."
sudo mkdir -p /etc/x11vnc
if [ ! -f /etc/x11vnc/passwd ] || [ "${VNC_RESET_PASSWORD:-0}" = "1" ]; then
    sudo x11vnc -storepasswd /etc/x11vnc/passwd
    echo "  密碼已寫入 /etc/x11vnc/passwd"
else
    echo "  密碼檔已存在，跳過（重設請帶 VNC_RESET_PASSWORD=1 重跑）"
fi

echo "[3/5] 安裝 wrapper script..."
sudo cp "$SCRIPT_DIR/x11vnc-wrapper.sh" /usr/local/bin/x11vnc-wrapper.sh
sudo chmod +x /usr/local/bin/x11vnc-wrapper.sh

echo "[4/5] 寫入 systemd service 檔案..."
sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<'EOF'
[Unit]
Description=x11vnc VNC Server
After=graphical-session.target gdm.service
Wants=graphical-session.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/x11vnc-wrapper.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[5/5] 啟用並啟動服務..."
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl restart x11vnc.service

sleep 2
sudo systemctl status x11vnc.service --no-pager | head -15

echo ""
echo "=============================="
echo " VNC Server 已啟動並設為開機自動啟動"
echo " 連線位址: $(hostname -I | awk '{print $1}'):5900"
echo ""
echo " 重點: wrapper 每 3 秒偵測 active VT 的 Xauthority 變化"
echo "   - 登入/登出/切換帳號時自動切換 auth"
echo "=============================="
