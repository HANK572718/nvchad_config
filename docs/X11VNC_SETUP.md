# 快速部署指南（從零開始設定相同環境）

## 環境資訊
- 裝置：NVIDIA Jetson (aarch64)，Ubuntu 22.04.5 LTS
- 主機名稱：yuan-6n0cnx
- IP：192.168.137.124 / 192.168.55.1
- 使用者：nvidia（UID 1000）、suser（UID 1001）
- VNC 密碼：存放於 `/etc/x11vnc/passwd`
- AnyDesk 密碼：存放於 `/etc/anydesk/system.conf`（勿明文記錄）

---

## Step 1：關閉 Wayland，啟用自動登入

```bash
sudo nano /etc/gdm3/custom.conf
```

內容：
```ini
[daemon]
WaylandEnable=false
AutomaticLoginEnable=true
AutomaticLogin=nvidia
```

---

## Step 2：設定 xorg.conf（NVIDIA headless + 有螢幕兩用）

```bash
sudo nano /etc/X11/xorg.conf
```

內容：
```
Section "Module"
    Disable     "dri"
    SubSection  "extmod"
        Option  "omit xfree86-dga"
    EndSubSection
EndSection

Section "Device"
    Identifier  "Tegra0"
    Driver      "nvidia"
    Option      "AllowEmptyInitialConfiguration" "true"
    Option      "ConnectedMonitor" "DP-0"
    Option      "ModeValidation" "AllowNonEdidModes, NoEdidMaxPClkCheck, NoMaxPClkCheck"
EndSection

Section "Monitor"
    Identifier  "Monitor0"
    HorizSync   28.0-80.0
    VertRefresh 48.0-75.0
    Modeline    "1920x1080" 148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync
EndSection

Section "Screen"
    Identifier  "Screen0"
    Device      "Tegra0"
    Monitor     "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth   24
        Modes   "1920x1080"
    EndSubSection
EndSection
```

> **重點**：`ConnectedMonitor "DP-0"` 讓 NVIDIA driver 在無 HDMI 時仍建立虛擬 framebuffer，VNC 才有畫面可捕捉。

---

## Step 3：安裝 x11vnc

```bash
sudo apt-get install -y x11vnc
sudo mkdir -p /etc/x11vnc
sudo x11vnc -storepasswd /etc/x11vnc/passwd
```

---

## Step 4：部署 x11vnc wrapper + systemd service

### 方式一：使用設定腳本（推薦）

```bash
sudo bash ~/.config/nvim/script/setup_x11vnc.sh
```

腳本會自動安裝 wrapper script 並建立 service。

### 方式二：手動部署

**Wrapper script**（`/usr/local/bin/x11vnc-wrapper.sh`）：

wrapper 的設計解決了登入/登出時 display 編號和 Xauthority 路徑會變化的問題。它每 3 秒偵測 Xorg 進程的狀態，當偵測到 display 或 auth 變化時自動重啟 x11vnc。

原始碼位於：`~/.config/nvim/script/x11vnc-wrapper.sh`

**Service 檔案**（`/etc/systemd/system/x11vnc.service`）：

```ini
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
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable x11vnc
sudo systemctl start x11vnc
```

---

## Step 5：設定預設解析度 1080p（自動登入後套用）

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/set-resolution.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Set Resolution
Exec=/bin/bash -c "sleep 3 && xrandr --output DP-0 --mode 1920x1080"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

---

## 完成後連線資訊

| 工具 | 連線方式 |
|------|----------|
| VNC | `192.168.137.124:5900` |
| AnyDesk | ID：`637260884` |

---

---

# 問題排查記錄

## 原始狀態說明（設定前的背景）

此台 Jetson 在進行遠端桌面設定之前，已存在以下狀況：

### 原始 AnyDesk 狀況
- AnyDesk 8.0.1 已安裝並設為開機自啟動
- **無人值守密碼遺忘**：使用者推測是當時密碼輸入錯誤導致登入失敗，並非系統問題
- AnyDesk backend 跑在 `gdm` 使用者下（tty1 GDM 登入畫面），不是 nvidia 使用者的桌面 session，因此即使連線成功也只會看到登入畫面而非桌面
- CLI 修改密碼嘗試失敗（詳見問題 5）

### 原始無螢幕配置問題
- 系統已預先設有 `/etc/X11/xorg.conf.d/10-dummy.conf`（dummy 虛擬顯示驅動），這是為了讓系統在**無實體螢幕時也能啟動 X11**
- 然而此設定的副作用：**插上 HDMI 螢幕開機後，NVIDIA logo 出現幾秒後畫面即變黑**，因為 dummy driver 完全繞過實體顯示硬體
- nvidia 使用者無圖形 session，只有 GDM greeter session 在運行

### 原始 Wayland 停用原因推估
- `/etc/gdm3/custom.conf` 中設有 `WaylandEnable=false`，強制 GDM 只啟動 X11 session
- **推測原因**：AnyDesk Linux 版對 Wayland 的支援有限，特別是在 Jetson 這類 ARM 平台上。AnyDesk 在 Wayland 下無法直接存取畫面內容（Wayland 的安全模型不允許應用程式任意截取其他 session 的畫面），因此安裝 AnyDesk 時通常需要切換到 X11 才能正常運作
- x11vnc 同樣依賴 X11 架構（透過 X11 protocol 截取畫面），在 Wayland 下無法使用
- 因此 **X11 是這台機器上遠端桌面工具的必要前提**，Wayland 停用屬於正確且必要的設定

---

## 問題 1：有實體螢幕時畫面黑掉

**原因**：系統原本設有 `/etc/X11/xorg.conf.d/10-dummy.conf`，強制使用 `dummy` 虛擬顯示驅動，讓 X11 在無螢幕時可以啟動。但副作用是即使插上 HDMI，實體螢幕也沒有任何輸出。

**解法**：移除 dummy conf，改用 xorg.conf 的 `ConnectedMonitor` 選項讓 NVIDIA driver 自行管理虛擬輸出。

---

## 問題 2：VNC 登入後立刻斷線

**原因**：x11vnc 啟動時使用 GDM greeter 的 Xauthority（`/run/user/128/gdm/Xauthority`）。當使用者透過 VNC 在 GDM 畫面手動登入時，GDM 建立新 session 並更換 Xauthority，x11vnc 失去連線。

**解法**：
1. 啟用 GDM 自動登入（`AutomaticLogin=nvidia`）
2. x11vnc service 改為動態尋找 `/run/user/1000/` 下的 Xauthority，確保抓到 nvidia user 的 session

---

## 問題 3：重開機後 VNC 連線被拒絕（display :1）

**原因**：設定 x11vnc 時誤用 `-display :1`，但 GDM autologin 後 X session 實際在 `:0`（可由 `ls /tmp/.X11-unix/` 確認）。

**規則**：GDM autologin 會直接使用 `:0`，不會開新的 display。

**解法**：改為 `-display :0`。

---

## 問題 4：無 HDMI 時 VNC 顯示 NVIDIA 開機 logo

**原因**：移除 dummy conf 後，NVIDIA driver 在無 HDMI 時雖可啟動 X11（靠 `AllowEmptyInitialConfiguration=true`），但不會建立虛擬 framebuffer，x11vnc 捕捉到的是 kernel 留下的開機畫面。

**解法**：在 xorg.conf Device section 加入：
```
Option "ConnectedMonitor" "DP-0"
Option "ModeValidation" "AllowNonEdidModes, NoEdidMaxPClkCheck, NoMaxPClkCheck"
```
強制 NVIDIA driver 以為 DP-0 永遠有接螢幕，確保虛擬 framebuffer 存在。

---

## 問題 5：AnyDesk 無人值守密碼無法用 CLI 修改

**原因**：AnyDesk v8.0.1 Linux 版的 `anydesk --set-password` 指令會回傳 exit code 51，密碼 hash 未實際寫入 `/etc/anydesk/system.conf`（需 root 寫入）。

**解法**：透過 VNC 連進桌面，從 AnyDesk GUI 介面手動設定無人值守密碼。

**注意**：密碼 hash 位於 `system.conf` 的 `ad.security.pwd`、`ad.security.permission_profiles._unattended_access.pwd` 及對應 salt 三個欄位，且使用 SHA-256 加鹽。

---

## 問題 6：登出或切換帳號後 VNC 斷線（2026-03-31 suser 帳號修復）

**原因**：舊的 x11vnc service 有三個問題導致登出/切換帳號後 VNC 永久失效：

1. **Xauthority 路徑寫死**：使用 `-auth /run/user/1000/gdm/Xauthority`，登出後該檔案被刪除
2. **`-auth guess` 無效**：GDM greeter 的 Xauthority 在 `/run/user/128/gdm/Xauthority`（UID 128 = gdm），`-auth guess` 找不到
3. **Display 編號會變**：GDM autologin 用 `:0`，但手動登入其他帳號後可能變成 `:1`。ExecStartPre 寫死等待 `/tmp/.X11-unix/X0` 導致啟動失敗

**解法**：改用 wrapper script（`/usr/local/bin/x11vnc-wrapper.sh`），每 3 秒偵測 active VT 上的 Xorg 狀態：
- 讀取 `/sys/class/tty/tty0/active` 取得當前 active VT 編號
- 用 `pgrep -x Xorg` 找到 Xorg 進程，從 `/proc/$pid/cmdline` 的 `vt` 參數比對 VT、`-auth` 參數取得 Xauthority 路徑
- 用 `ss -xlp` 配對該 PID 擁有的 X11 unix socket 取得 display 編號
- 偵測到變化時自動 kill 舊的 x11vnc 並用新參數重啟
- VNC client 端短暫斷線後重連即可

**相關檔案**：
- wrapper 原始碼：`~/.config/nvim/script/x11vnc-wrapper.sh`
- 部署腳本：`~/.config/nvim/script/setup_x11vnc.sh`
- 安裝位置：`/usr/local/bin/x11vnc-wrapper.sh`

---

## 備份檔案位置

| 備份檔 | 原始用途 |
|--------|----------|
| `/etc/X11/xorg.conf.bak` | 移除 ConnectedMonitor 前的 xorg.conf |
| `/etc/X11/xorg.conf.d/10-dummy.conf.bak` | 原始 dummy 虛擬顯示設定 |

---

---

# 圖形與顯示架構概述

## 層次關係

```
┌─────────────────────────────────────────────────────────────┐
│                    遠端桌面工具層                             │
│     AnyDesk                    x11vnc (VNC server)          │
│     （自有加密協定）              （RFB 協定 port 5900）      │
└───────────────┬─────────────────────────┬───────────────────┘
                │                         │
                ▼                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    顯示協定層                                 │
│                                                             │
│   ✅ X11（X Window System）          ✗ Wayland（已停用）    │
│   採用 Client-Server 架構            採用 Compositor 架構   │
│   應用程式透過 X protocol 溝通        合成器直接與 kernel 溝通│
│   畫面可被第三方工具截取              安全隔離，禁止跨程式截圖 │
│   Xauthority cookie 認證             無 Xauthority 機制     │
└───────────────────────────┬─────────────────────────────────┘
                            │（X11 路徑）
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  X Server 層（Xorg）                         │
│   /usr/lib/xorg/Xorg                                        │
│   - 管理 display :0 或 :1（視登入狀態而定）                  │
│   - 維護 Xauthority（MIT-MAGIC-COOKIE 認證）                 │
│   - 負責畫面輸出、鍵盤滑鼠輸入事件                           │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  顯示管理器層（GDM）                          │
│   gdm3                                                      │
│   - 管理登入畫面（greeter session）                          │
│   - 啟動並管理 X server                                      │
│   - 處理 session 切換（greeter → 使用者桌面）                │
│   - 設定檔：/etc/gdm3/custom.conf                           │
│   - GDM 本身可支援 X11 或 Wayland，本機強制 X11             │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  顯示驅動層                                   │
│   NVIDIA Tegra driver（nvidia）                              │
│   - 管理實體 GPU 與顯示輸出（DP-0, DP-1）                   │
│   - 設定檔：/etc/X11/xorg.conf                              │
│   - ConnectedMonitor：強制建立虛擬輸出（headless 用）        │
│   - AllowEmptyInitialConfiguration：無螢幕仍可啟動 Xorg     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kernel / 硬體層                              │
│   tegra DRM kernel module                                   │
│   實體顯示輸出：HDMI/DP → 實體螢幕                           │
└─────────────────────────────────────────────────────────────┘
```

## 各工具的角色與依賴

| 工具 | 角色 | 依賴 |
|------|------|------|
| **GDM** | 顯示管理器，啟動 Xorg、管理 session | systemd |
| **Xorg** | X server，提供 display :0 或 :1 | NVIDIA driver、GDM |
| **Xauthority** | MIT-MAGIC-COOKIE 認證檔，控制誰可以連接 X server | Xorg session |
| **x11vnc** | 截取 X11 framebuffer 透過 VNC 協定傳出 | Xorg（需要正確 Xauthority）|
| **x11vnc-wrapper** | 監控 active VT 的 Xorg 狀態，自動重啟 x11vnc 以追蹤 auth/display 變化 | /sys/class/tty、pgrep、ss、x11vnc |
| **AnyDesk** | 截取 X11 畫面透過自有協定傳出 | X11（Wayland 不支援）|
| **NVIDIA Tegra driver** | 驅動 GPU，管理實體顯示輸出 | kernel DRM module |

## Xauthority 的重要性

Xauthority 是 X11 的認證機制，x11vnc 必須持有正確的 cookie 才能連接 X server：

- **GDM greeter session**：Xauthority 在 `/run/user/128/gdm/Xauthority`（uid 128 = gdm）
- **nvidia 使用者 session**：Xauthority 在 `/run/user/1000/gdm/Xauthority`（uid 1000 = nvidia）
- session 切換時 Xauthority 會更換 → x11vnc-wrapper 會自動偵測並重啟 x11vnc

## X11 與 Wayland 的異同

### 共同點
- 兩者都是 Linux 桌面環境的**顯示協定**，負責管理視窗、畫面輸出與輸入事件
- 都需要搭配 GDM 等顯示管理器啟動
- 上層的桌面環境（GNOME、KDE 等）在兩者之上都可以運行

### 主要差異

| 面向 | X11 | Wayland |
|------|-----|---------|
| **架構** | Client-Server：應用程式透過 X protocol 向 X server 請求顯示 | Compositor 架構：合成器直接與 kernel DRM/KMS 溝通，無獨立 server |
| **安全性** | 較低：任何程式只要有 Xauthority cookie 就能截取整個螢幕畫面 | 較高：每個 app 只能看到自己的畫面，無法跨程式截圖 |
| **效能** | 較舊，繪圖路徑較長，有額外的 protocol 轉換開銷 | 較新，路徑更短，理論上延遲更低 |
| **遠端桌面工具** | x11vnc、AnyDesk 等工具可直接截取畫面 | 需要 wayvnc、pipewire screencast 等專屬支援 |
| **Xauthority** | 有，用 MIT-MAGIC-COOKIE 控制存取 | 無此機制，改由 compositor 控制 |
| **成熟度** | 數十年歷史，相容性最廣 | 較新，部分工具支援仍不完整（如 ARM 平台）|

### 本機選用 X11 的原因
Wayland 的高安全性設計反而成為遠端桌面的障礙：
- **x11vnc** 完全依賴 X11 截圖能力，在 Wayland 下無法運作
- **AnyDesk** 在 Linux Wayland 上支援有限，Jetson ARM 平台尤其不穩定
- 因此停用 Wayland（`WaylandEnable=false`）是讓遠端桌面工具正常運作的必要條件

> 若未來需要切換回 Wayland，遠端桌面工具需全部換成支援 Wayland 的替代方案（如 wayvnc + pipewire）。
