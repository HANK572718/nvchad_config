#!/bin/bash
set -e

echo "[1/3] 寫入 systemd service 檔案..."
sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<EOF
[Unit]
Description=x11vnc VNC Server for display :0
After=graphical.target lightdm.service
Wants=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :0 -auth /var/run/lightdm/root/:0 -rfbauth /home/nh/.vnc/passwd -forever -noxdamage -repeat -rfbport 5900 -o /home/nh/.vnc/x11vnc.log
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

echo "[2/3] 啟用並啟動服務..."
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl start x11vnc.service

echo "[3/3] 確認狀態..."
sleep 2
sudo systemctl status x11vnc.service --no-pager

echo ""
echo "=============================="
echo " VNC Server 已啟動並設為開機自動啟動"
echo " 連線位址: $(hostname -I | awk '{print $1}'):5900"
echo "=============================="
