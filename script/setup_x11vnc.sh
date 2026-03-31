#!/bin/bash
set -e

echo "[1/4] 安裝 x11vnc（如果尚未安裝）..."
sudo apt-get install -y x11vnc

echo "[2/4] 設定 VNC 密碼..."
sudo mkdir -p /etc/x11vnc
if [ ! -f /etc/x11vnc/passwd ]; then
    sudo x11vnc -storepasswd /etc/x11vnc/passwd
    echo "  密碼已建立於 /etc/x11vnc/passwd"
else
    echo "  密碼檔已存在，跳過（如需重設請執行: sudo x11vnc -storepasswd /etc/x11vnc/passwd）"
fi

echo "[3/5] 安裝 wrapper script..."
WRAPPER_SRC="$(dirname "$0")/x11vnc-wrapper.sh"
sudo cp "$WRAPPER_SRC" /usr/local/bin/x11vnc-wrapper.sh
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
sudo systemctl status x11vnc.service --no-pager

echo ""
echo "=============================="
echo " VNC Server 已啟動並設為開機自動啟動"
echo " 連線位址: $(hostname -I | awk '{print $1}'):5900"
echo ""
echo " 重點: wrapper script 每 3 秒偵測 Xauthority 路徑變化"
echo "   - 登入/登出時自動切換 auth，VNC 不會斷線"
echo "   - 不再依賴特定使用者的 Xauthority 路徑"
echo "=============================="
