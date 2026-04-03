# Jetson Orin Nano 遠端桌面 + 顯示設定

## 快速上手（新機器只需這三步）

### 前置：關閉 Wayland，啟用自動登入（一次性手動設定）

```bash
sudo nano /etc/gdm3/custom.conf
```

```ini
[daemon]
WaylandEnable=false
AutomaticLoginEnable=true
AutomaticLogin=nvidia
```

### 執行兩支腳本，全部搞定

```bash
# 1. VNC Server（x11vnc + systemd service）
sudo bash ~/.config/nvim/script/setup_x11vnc.sh

# 2. 顯示設定（xorg.conf + 開機自動套用 60Hz）
sudo bash ~/.config/nvim/script/setup-display.sh
```

部署完成後重開機，VNC port 5900 即可連線，實體螢幕亦會正常顯示。

### 讓所有本機用戶可執行 GUI 程式（Qt / X11）

```bash
# 一次性：允許所有本機用戶存取 X display
echo 'DISPLAY=:0' | sudo tee -a /etc/environment
```

setup-display.sh 部署後，開機 autostart 會自動執行 `xhost +local:`，
無需額外設定。若在此之前需要手動套用：

```bash
DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority xhost +local:
```

### AnyDesk（選用，ARM64 需手動安裝）

```bash
# 從官網下載 ARM64 .deb（https://anydesk.com/en/downloads/linux）
wget https://download.anydesk.com/linux/anydesk_<版本>_arm64.deb
sudo dpkg -i anydesk_<版本>_arm64.deb && sudo apt-get install -f
sudo systemctl enable --now anydesk
```

> 無人值守密碼**只能透過 GUI 設定**（CLI `--set-password` 在 v8 無效）。詳見文末 AnyDesk 章節。

### 硬體注意事項

| 連接器 | 顯示輸出 |
|--------|----------|
| DisplayPort（全尺寸 DP） | ✅ 唯一顯示輸出，接 HDMI 螢幕須用 DP→HDMI 轉接器 |
| USB-C | ❌ 僅 USB 資料，不支援顯示（NVIDIA 官方確認） |

> 雙螢幕唯一方案：**DisplayPort MST Hub**（主動式分流器）。

---

---

# 詳細部署說明

## 環境資訊

- 裝置：NVIDIA Jetson Orin Nano (aarch64)，Ubuntu 22.04.5 LTS
- 主機名稱：yuan-6n0cnx
- VNC 密碼：存放於 `/etc/x11vnc/passwd`
- AnyDesk 密碼：存放於 `/etc/anydesk/system.conf`（勿明文記錄）

---

## Step 1：關閉 Wayland，啟用自動登入

```bash
sudo nano /etc/gdm3/custom.conf
```

```ini
[daemon]
WaylandEnable=false
AutomaticLoginEnable=true
AutomaticLogin=nvidia
```

> **原因**：x11vnc 與 AnyDesk 均依賴 X11，Wayland 下無法截取畫面。
> 自動登入確保重開機後 nvidia user session 立即建立，VNC 不需等待手動登入。

---

## Step 2：部署 VNC Server

```bash
sudo bash ~/.config/nvim/script/setup_x11vnc.sh
```

腳本會自動完成：安裝 x11vnc、設定密碼、部署 wrapper script、建立並啟動 systemd service。

> **原始碼**：`~/.config/nvim/script/x11vnc-wrapper.sh`
> Wrapper 每 3 秒偵測 active VT 上的 Xorg 狀態，自動追蹤 display 編號與 Xauthority 路徑變化，支援登入/登出/切換帳號不斷線。

---

## Step 3：部署顯示設定

```bash
sudo bash ~/.config/nvim/script/setup-display.sh
```

腳本會自動完成：備份並部署 `configs/xorg.conf`、部署 `display-mode.sh`、設定開機 autostart。

重開機後自動套用。或立即套用（不需重開機）：

```bash
/usr/local/bin/display-mode.sh
```

> **為何需要此腳本**：Driver 預設選螢幕最高刷新率（可能 120Hz），被動式 DP→HDMI 轉接器最高只支援 60Hz，導致螢幕顯示 "No Signal"。此腳本強制設為 60Hz 解決此問題。

---

## 腳本一覽

| 腳本 | 用途 | 部署位置 |
|------|------|----------|
| `script/setup_x11vnc.sh` | 部署 VNC server | 執行一次即可 |
| `script/setup-display.sh` | 部署顯示設定 + 60Hz 修正 | 執行一次即可 |
| `script/x11vnc-wrapper.sh` | VNC 動態追蹤核心邏輯 | → `/usr/local/bin/` |
| `script/display-mode.sh` | 強制 DP-0 @ 60Hz | → `/usr/local/bin/` |
| `script/display-mode-autostart.sh` | 開機自動套用 60Hz | → `/usr/local/bin/` |
| `configs/xorg.conf` | 系統 xorg 設定範本 | → `/etc/X11/xorg.conf` |

---

---

# 硬體規格

## 顯示輸出

| 連接器 | 顯示輸出 | 說明 |
|--------|----------|------|
| **DisplayPort（全尺寸 DP）** | ✅ | 唯一顯示輸出，接 HDMI 螢幕需用 DP→HDMI 轉接器 |
| USB-C | ❌ | 僅 USB 資料/電源，不支援 DP Alt Mode（NVIDIA 官方確認） |
| DP-1 (DFP-1 TMDS) | ❌ | 內部介面，無實體連接器，不可使用 |

## USB-C 支援功能

| 功能 | 支援 |
|------|------|
| 滑鼠、鍵盤、隨身碟 | ✅ |
| USB 相機（UVC/V4L2） | ✅ |
| USB Hub | ✅ |
| 顯示輸出（DP Alt Mode） | ❌ |
| 電源輸入（USB PD） | ❌（只能用電源孔） |

## 雙螢幕方案

USB-C 無法輸出影像。唯一雙螢幕方法：購買 **DisplayPort MST Hub（主動式分流器）**，插入 DP 孔，可分接 2+ 台螢幕。

---

---

# 問題排查記錄

## 原始狀態說明

此台 Jetson 在設定前已存在以下狀況：

- AnyDesk 8.0.1 已安裝但無人值守密碼遺忘（CLI 修改無效，詳見問題 5）
- 系統有 `/etc/X11/xorg.conf.d/10-dummy.conf`（dummy 虛擬顯示驅動），讓 X11 在無螢幕時能啟動，但副作用是接上螢幕後畫面仍黑屏
- Wayland 已停用（`WaylandEnable=false`），為 AnyDesk 需求

---

## 問題 1：有實體螢幕時畫面黑掉

**原因**：`10-dummy.conf` 強制使用 dummy 虛擬顯示驅動，即使插上螢幕也無任何輸出。

**解法**：移除 dummy conf，改用 xorg.conf 的 `ConnectedMonitor` 選項。

---

## 問題 2：VNC 登入後立刻斷線

**原因**：x11vnc 使用 GDM greeter 的 Xauthority，手動登入後 GDM 更換 Xauthority，x11vnc 失效。

**解法**：啟用 GDM 自動登入（`AutomaticLogin=nvidia`）+ 動態偵測 Xauthority。

---

## 問題 3：重開機後 VNC 連線被拒絕

**原因**：寫死 `-display :1`，但 GDM autologin 後 X session 實際在 `:0`。

**解法**：改為動態偵測 display 編號（x11vnc-wrapper.sh）。

---

## 問題 4：無螢幕時 VNC 顯示開機 logo

**原因**：無 HDMI 時 NVIDIA driver 不建立虛擬 framebuffer，x11vnc 捕捉到 kernel 留下的畫面。

**解法**：在 xorg.conf 加入 `ConnectedMonitor "DP-0"` 強制建立虛擬 framebuffer。

---

## 問題 5：AnyDesk 無人值守密碼無法用 CLI 修改

**原因**：`anydesk --set-password` 在 v8.0.1 Linux 回傳 exit code 51，密碼未實際寫入。

**解法**：透過 VNC 連進桌面，從 AnyDesk GUI 手動設定。

---

## 問題 6：登出或切換帳號後 VNC 斷線

**原因**：Xauthority 路徑寫死、`-auth guess` 無效、display 編號會變（`:0` → `:1`）。

**解法**：x11vnc-wrapper.sh 每 3 秒偵測 active VT 上的 Xorg 狀態，自動重啟 x11vnc。

---

## 問題 7：實體螢幕無畫面（No Signal）

**原因**：Driver 自動選螢幕最高刷新率（119.88Hz），被動式 DP→HDMI 轉接器只支援 60Hz。

**解法**：`/usr/local/bin/display-mode.sh` 強制 DP-0 @ 60Hz，由 autostart 在每次登入後自動套用。

> **注意**：`ConnectedMonitor` 只能寫 `"DP-0"`，不可加 DP-1。加入後 NVIDIA driver 嘗試建立雙輸出 MetaMode，`Configure crtc 1 failed` → Xorg 崩潰，VNC/AnyDesk 全斷。

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
│   ✅ X11（X Window System）          ✗ Wayland（已停用）    │
│   應用程式透過 X protocol 溝通        安全隔離，禁止跨程式截圖 │
│   Xauthority cookie 認證             無 Xauthority 機制     │
└───────────────────────────┬─────────────────────────────────┘
                            │（X11 路徑）
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  X Server 層（Xorg）                         │
│   - 管理 display :0 或 :1（視登入狀態而定）                  │
│   - 維護 Xauthority（MIT-MAGIC-COOKIE 認證）                 │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  顯示管理器層（GDM）                          │
│   - 啟動 Xorg、管理 session 切換                             │
│   - 設定檔：/etc/gdm3/custom.conf                           │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  顯示驅動層（NVIDIA Tegra）                   │
│   - ConnectedMonitor：強制建立虛擬輸出（headless 用）        │
│   - AllowEmptyInitialConfiguration：無螢幕仍可啟動 Xorg     │
│   - 設定檔：/etc/X11/xorg.conf                              │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kernel / 硬體層                              │
│   tegra DRM kernel module                                   │
│   實體顯示輸出：DisplayPort → 實體螢幕（via DP→HDMI 轉接）  │
└─────────────────────────────────────────────────────────────┘
```

## 各工具角色

| 工具 | 角色 | 依賴 |
|------|------|------|
| **GDM** | 顯示管理器，啟動 Xorg、管理 session | systemd |
| **Xorg** | X server，提供 display | NVIDIA driver、GDM |
| **x11vnc** | 截取 X11 framebuffer 透過 VNC 協定傳出 | Xorg + 正確 Xauthority |
| **x11vnc-wrapper** | 監控 active VT 的 Xorg，自動重啟 x11vnc | /sys/class/tty、pgrep、ss |
| **AnyDesk** | 截取 X11 畫面透過自有協定傳出 | X11（Wayland 不支援）|
| **display-mode.sh** | 強制 DP-0 @ 60Hz，修正轉接器相容問題 | Xorg + xrandr |

## Xauthority 路徑

| Session 類型 | 路徑 |
|-------------|------|
| GDM greeter | `/run/user/128/gdm/Xauthority` |
| nvidia user session | `/run/user/1000/gdm/Xauthority` |
| suser session | `/run/user/1001/gdm/Xauthority` |

Session 切換時 Xauthority 會變更 → x11vnc-wrapper 自動偵測並重啟 x11vnc。

## 為何選用 X11 而非 Wayland

x11vnc 與 AnyDesk 均依賴 X11 截圖能力，Wayland 的安全隔離設計阻止了跨程式畫面截取。Jetson ARM 平台上 AnyDesk 的 Wayland 支援尤其不穩定，因此強制使用 X11（`WaylandEnable=false`）是必要設定。

---

---

# AnyDesk 安裝說明（ARM64 / Jetson）

## 前置條件：必須先關閉 Wayland

AnyDesk 在 Linux Wayland session 下無法截取畫面（Wayland 安全隔離機制所限）。
ARM 平台尤其不穩定，**安裝前務必確認 Wayland 已停用**：

```bash
grep -E "WaylandEnable|AutomaticLogin" /etc/gdm3/custom.conf
```

應顯示：
```
WaylandEnable=false
AutomaticLoginEnable=true
AutomaticLogin=nvidia
```

若尚未設定，先執行 Step 1（關閉 Wayland）再繼續。

---

## 安裝步驟

### 1. 下載 ARM64 版本

AnyDesk 官方提供 ARM64 的 `.deb` 套件，需從官網手動下載（apt repo 目前僅支援 x86_64）：

```bash
# 前往官網下載頁面取得最新 ARM64 .deb 連結
# https://anydesk.com/en/downloads/linux
# 選擇 DEB - ARM 64-bit

# 範例（版本號請以官網為準）：
wget https://download.anydesk.com/linux/anydesk_8.0.1-1_arm64.deb
sudo dpkg -i anydesk_8.0.1-1_arm64.deb

# 修復相依性（若有）：
sudo apt-get install -f
```

> 本機目前版本：`8.0.1 arm64`

### 2. 確認服務狀態

```bash
sudo systemctl enable anydesk
sudo systemctl start anydesk
sudo systemctl status anydesk --no-pager
```

### 3. 取得 AnyDesk ID

```bash
anydesk --get-id
# 或從 AnyDesk GUI 主畫面查看
```

> 本機 AnyDesk ID：`637260884`

---

## 設定無人值守密碼（必須用 GUI）

> ⚠️ **CLI 方式無效**：`anydesk --set-password` 在 v8 Linux 回傳 exit code 51，密碼不會實際寫入。

唯一有效方式：
1. 透過 VNC 或實體螢幕進入桌面
2. 開啟 AnyDesk 應用程式
3. 進入 **設定 → 安全性 → 無人值守存取**
4. 設定密碼並儲存

---

## 確認可連線

從另一台電腦的 AnyDesk 輸入本機 ID（`637260884`），使用無人值守密碼連線。

連線成功後應看到 GNOME 桌面畫面（nvidia user session）。
若看到的是 GDM 登入畫面，代表 autologin 未正確設定（確認 Step 1）。

---

## 常見問題

| 症狀 | 原因 | 解法 |
|------|------|------|
| 連線後看到登入畫面而非桌面 | AnyDesk 連到 GDM greeter session | 確認 `AutomaticLogin=nvidia` 已設定並重開機 |
| 連線後畫面全黑 | Wayland session 啟動 | 確認 `WaylandEnable=false` 並重開機 |
| 無人值守密碼設定失敗 | CLI `--set-password` 在 v8 無效 | 改用 GUI 設定 |
| ARM64 套件找不到 | apt repo 僅有 x86_64 | 從官網手動下載 `.deb` |
