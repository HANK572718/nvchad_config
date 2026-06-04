# setup-screen.sh — 螢幕 / 顯示 / VNC 一鍵設定

跨平台、互動式、可重跑。一個進入點搞定：
強制 X11 session、平台自適應的顯示設定、x11vnc VNC server。

> 上游入口：`~/.config/nvim/script/setup-screen.sh`
> 子腳本：`~/.config/nvim/script/sub/`
> 設定檔：`~/.config/nvim/configs/`

---

## 1. 支援平台

| 平台代號 | 偵測條件 | xorg.conf | force-X11 | VNC |
|---|---|---|---|---|
| `jetson-orin`    | `/proc/device-tree/model` 含 `Orin`                  | ✅ 部署 `xorg.conf.jetson-orin`（1080p@60Hz） | GDM | ✅ |
| `jetson-legacy`  | `/etc/nv_tegra_release` 或 model 含 `jetson`/`tegra` | ❌ 跳過（HDMI 直出，L4T 驅動自動偵測） | GDM/LightDM | ✅ |
| `raspberry-pi`   | model 含 `Raspberry`                                 | ❌ 跳過 | `raspi-config nonint do_wayland W1` | ✅ |
| `nvidia-desktop` | `lspci` 找到 NVIDIA VGA/3D                           | ❌ 跳過（自動清掉誤部署的 Jetson 殘留） | GDM/SDDM | ✅ |
| `amd`            | `lspci` 找到 AMD/ATI/Radeon                          | ❌ 跳過 | GDM/SDDM | ✅ |
| `intel`          | `lspci` 找到 Intel                                   | ❌ 跳過 | GDM/SDDM | ✅ |
| `unknown`        | 以上皆非                                              | ❌ 跳過 | 嘗試 GDM/SDDM | ✅ |

---

## 2. 快速上手

最常見的情境（全新機器、想全部裝起來）：

```bash
sudo bash ~/.config/nvim/script/setup-screen.sh --all
sudo reboot
```

或想互動選：

```bash
sudo bash ~/.config/nvim/script/setup-screen.sh
# 選 2（一次問完），全部按 Enter 接受預設值即可
```

想先看目前狀態（不需 sudo）：

```bash
bash ~/.config/nvim/script/setup-screen.sh --status
```

---

## 3. CLI 參數一覽

| 旗標 | 動作 |
|---|---|
| `-a`, `--all` | x11 + display + VNC 全部部署 |
| `-x`, `--x11` | 只強制 display manager 走 X11 |
| `-d`, `--display` | 只裝 display 設定 |
| `-v`, `--vnc` | 只裝 VNC server |
| `-s`, `--status` | 顯示當前狀態（X11/Wayland、VNC、平台）— 不需 sudo |
| `--no-x11` | 搭配 `--all` 用，跳過 X11 強制 |
| `--reset-vnc-password` | 重設 `/etc/x11vnc/passwd` |
| `-r`, `--reboot` | 部署完自動重開機 |
| `-h`, `--help` | 顯示說明 |

不帶任何參數 → 進入互動選單：

- **逐步互動**：問一個做一個，看每步輸出再決定下一步
- **一次問完**：先把所有問題列出來，按 Y 後依序執行（適合熟悉流程後的快速操作）

---

## 4. 各步驟做了什麼

### `--x11`（force-x11.sh）

把 display manager 切到 X11，讓 x11vnc 在 Wayland 預設的平台也能用。**冪等**，可重跑。

- **GDM / GDM3**（Ubuntu / Jetson）：在 `/etc/gdm3/custom.conf` 的 `[daemon]` 段寫入 `WaylandEnable=false`。聰明處理「已是 false / 被註解 / 缺 [daemon] 段」三種狀態。
- **SDDM**（KDE）：寫 `/etc/sddm.conf.d/10-force-x11.conf`，內容為 `[General] DisplayServer=x11`。
- **Raspberry Pi**：呼叫 `sudo raspi-config nonint do_wayland W1` 切回 X11（Pi OS Bookworm 之後預設是 labwc/wayfire Wayland）。
- **LightDM**：本來就是 X11，不需動作。

> 變更需要下一次登入或重開機才生效。

### `--display`（setup-display.sh）

依平台決定要不要部署 xorg.conf；其餘平台只裝 autostart 跑 `xhost +local:`。

- **jetson-orin**：
  - 部署 `configs/xorg.conf.jetson-orin` 到 `/etc/X11/xorg.conf`。內含 `Option "ConnectedMonitor" "DP-0"` 與 `Modeline 1920x1080` — 強制 60Hz，解決 Orin Nano 的 DP→HDMI 被動轉接器無法傳輸 >60Hz 訊號的問題。
  - 部署 `/usr/local/bin/display-mode.sh`：開機 autostart 動態抓 connected output 套 1080p@60Hz。
- **其餘平台**：
  - 跳過 xorg.conf。若 `/etc/X11/xorg.conf` 含 `Identifier "Tegra0"`（先前在桌機上誤跑 Jetson 設定的殘留），會自動備份移走 — 避免它強制把畫面送到不存在的 DP-0、HDMI 螢幕黑屏。
  - 仍部署 `/usr/local/bin/display-mode*.sh`，腳本內部自我判斷 → no-op。
- **所有平台**：
  - 寫 `~/.config/autostart/set-resolution.desktop`，登入後自動跑 `xhost +local:`（讓本機所有帳號可開 Qt/GUI）。
  - 自動移除 `/etc/environment` 裡的 `DISPLAY=:0`（舊版誤加，會干擾 SSH session）。

### `--vnc`（setup_x11vnc.sh）

- 安裝 `x11vnc` 套件（apt）
- 設定 `/etc/x11vnc/passwd`（首次互動輸入；重跑除非帶 `--reset-vnc-password` 否則沿用）
- 部署 `/usr/local/bin/x11vnc-wrapper.sh`
- 寫 `/etc/systemd/system/x11vnc.service`、`enable` 並 `restart`

---

## 5. x11vnc-wrapper 的工作原理

`/usr/local/bin/x11vnc-wrapper.sh`（以 root 跑）解決「VNC 要跟著目前 active VT 的 Xorg 走」的問題：

1. 讀 `/sys/class/tty/tty0/active` 找 active VT
2. `pgrep -x Xorg` + 看 cmdline 的 `vt<N>` 確認哪一個 Xorg 在 active VT 上
3. 從 cmdline 抽 `-auth` 路徑
4. 用 `ss -xlp` 對 PID → 找它 listen 的 `.X11-unix/X<N>` 取得 display 編號
5. 啟動 `x11vnc -display :N -auth ...` 連上

**關鍵旗標**：

| 旗標 | 為什麼 |
|---|---|
| `-noshm` | 不用 MIT-SHM 共享記憶體。**因為 wrapper 以 root 跑，目標 Xorg 由 gdm/user 啟動，X server 的 SHM 段不允許其他 UID attach**（會回 BadAccess on `X_ShmAttach`，x11vnc 直接退出）。 |
| `-forever` | 不在連線斷開後退出 |
| `-shared` | 允許多 client 同時連 |
| `-noxdamage` | 不用 DAMAGE 擴充（避免某些情境下事件遺漏） |
| `-repeat` | 鍵盤 auto-repeat |
| `-quiet` | 降低 log 量 |

**健康檢查**：迴圈每 3 秒檢查 `kill -0 $VNC_PID`；x11vnc 自己崩了會自動重啟（不必等 VT 變化才觸發）。

---

## 6. 確認當前狀態

```bash
bash ~/.config/nvim/script/setup-screen.sh --status
```

輸出範例（節錄）：

```
== 平台 ==
  代號     : nvidia-desktop
  GPU      : NVIDIA Corporation AD104 [GeForce RTX 4070]

== Session 類型（X11 vs Wayland） ==
  loginctl session 4 (user=nh02 seat=seat0 state=active type=x11)
  ✓ Xorg 進程存在（X11 確定）
  ✓ 結論：當前是 X11（x11vnc 可正常運作）

== Display Manager ==
  default-display-manager : gdm3
  /etc/gdm3/custom.conf:
  !   未設定 WaylandEnable（GDM 預設啟用 Wayland）

== x11vnc 服務 ==
  systemd  : state=active enabled=enabled
  ✓ x11vnc.service 執行中
  ✓ port 5900 listening
```

也可以手動快速檢查：

```bash
# 當前圖形 session 是什麼？
loginctl show-session $(loginctl | awk '$3 ~ /seat/ && $4 == "active" {print $1; exit}') -p Type --value
# → x11 或 wayland

# 有沒有 Xorg？
pgrep -x Xorg && echo "X11 in use"

# VNC 有沒有 listen？
ss -tlnp | grep 5900

# x11vnc 服務狀態
systemctl status x11vnc.service
```

---

## 7. 檔案結構

```
~/.config/nvim/
├── configs/
│   └── xorg.conf.jetson-orin       Jetson Orin 專用 xorg.conf
├── docs/
│   └── setup-screen.md              本文件
└── script/
    ├── setup-screen.sh              ← 唯一上層進入點
    └── sub/
        ├── force-x11.sh             DM 強制 X11
        ├── setup-display.sh         display 設定部署
        ├── setup_x11vnc.sh          x11vnc 安裝
        ├── display-mode.sh          → /usr/local/bin/
        ├── display-mode-autostart.sh→ /usr/local/bin/
        ├── x11vnc-wrapper.sh        → /usr/local/bin/
        └── show-status.sh           --status 實作
```

---

## 8. 部署到外部的檔案

| 安裝來源 | 目的位置 |
|---|---|
| `script/sub/display-mode.sh` | `/usr/local/bin/display-mode.sh` |
| `script/sub/display-mode-autostart.sh` | `/usr/local/bin/display-mode-autostart.sh` |
| `script/sub/x11vnc-wrapper.sh` | `/usr/local/bin/x11vnc-wrapper.sh` |
| `configs/xorg.conf.jetson-orin`（僅 jetson-orin） | `/etc/X11/xorg.conf` |
| autostart desktop entry | `~/.config/autostart/set-resolution.desktop` |
| systemd unit（vnc 步驟）| `/etc/systemd/system/x11vnc.service` |
| VNC 密碼 | `/etc/x11vnc/passwd` |
| force-x11 寫入點 | `/etc/gdm3/custom.conf` / `/etc/sddm.conf.d/10-force-x11.conf` |

---

## 9. 常見故障排查

### 螢幕黑屏 / No Signal（重開機後）

通常是 `/etc/X11/xorg.conf` 內容跟硬體對不上（最常見：把 Jetson Orin 的設定誤套到桌機 + HDMI）。

```bash
# 1. 確認是不是 Tegra 殘留
grep -l 'Identifier.*"Tegra0"' /etc/X11/xorg.conf

# 2. 若是，移走它就好
sudo mv /etc/X11/xorg.conf /etc/X11/xorg.conf.disabled.$(date +%s)
sudo reboot
```

或直接跑 `sudo bash setup-screen.sh --display` — 在非 jetson-orin 平台上會自動偵測並移除殘留。

### VNC 連得到但畫面是黑的 / x11vnc 一直 restart

通常是 `BadAccess on X_ShmAttach`。已透過 wrapper 的 `-noshm` 解決；若仍見到該錯誤，確認部署到 `/usr/local/bin/` 的 wrapper 是最新版：

```bash
sudo cp ~/.config/nvim/script/sub/x11vnc-wrapper.sh /usr/local/bin/x11vnc-wrapper.sh
sudo systemctl restart x11vnc.service
```

### VNC 連不上 / port 5900 沒人 listen

```bash
bash ~/.config/nvim/script/setup-screen.sh --status     # 一覽
sudo journalctl -u x11vnc.service -n 50 --no-pager      # 看 x11vnc log
sudo systemctl restart x11vnc.service
```

### 重開機後變回 Wayland（VNC 又掛）

`force-x11.sh` 跑過了但 GDM 改回去？看一下：

```bash
grep WaylandEnable /etc/gdm3/custom.conf
```

應該要看到 `WaylandEnable=false`。沒有 → 再跑一次 `sudo bash setup-screen.sh --x11`。

### SSH 進來執行 GUI 程式吐 `Cannot open display`

在桌面端登入後，autostart 跑的 `xhost +local:` 應該已經讓本機所有 UID 都能用 X。

```bash
# SSH 進來這樣跑
export DISPLAY=:0
xeyes
```

如果 autostart 還沒跑（沒登入過桌面），可手動：

```bash
sudo xhost +local:    # 從一個有 DISPLAY 的 session 執行
```

---

## 10. 維護備忘

- 加新平台：改 `sub/setup-display.sh`、`sub/display-mode.sh`、`sub/show-status.sh` 三處的 `detect_platform()`（目前是各自重複，保持一致）
- 加新 DM 的 X11 強制：擴充 `sub/force-x11.sh`
- 修改 xorg.conf 內容：編 `configs/xorg.conf.jetson-orin`（請保留 backup 機制；setup-display.sh 會自動 timestamp 備份既有 xorg.conf）
- 加新互動問題：在 `setup-screen.sh` 的 `mode_step` 和 `mode_batch` 兩處都要加（也要記得加對應 CLI 旗標）

---

## 11. 歷史教訓（為何如此設計）

| 踩過的雷 | 防護機制 |
|---|---|
| Jetson Orin 專用 xorg.conf 被誤套到 RTX 4070 桌機 → HDMI No Signal | `setup-display.sh` 用 `detect_platform()` 把關，只在 `jetson-orin` 部署；非 jetson-orin 主動清掉 Tegra 殘留 |
| `Option "ConnectedMonitor" "DP-0"` 在 Jetson Nano（HDMI 直出）也會壞 | 明確區分 `jetson-orin` vs `jetson-legacy`，只有 Orin 套 |
| `DISPLAY=:0` 寫進 `/etc/environment` → SSH session 跟著繼承，造成 GUI 工具誤連 GDM 的 X server | `setup-display.sh` 主動把它移除 |
| x11vnc 在 GDM Xorg 下 BadAccess 死亡 | wrapper 加 `-noshm` + 進程健康檢查自動重啟 |
| x11vnc-wrapper 早期版本只在 VT 變化時重啟，x11vnc 自己 crash 後沒人發現 | wrapper 改成迴圈內額外 `kill -0` 檢查 |
| Wayland 平台連不上 VNC | 加 `force-x11.sh` 統一處理 GDM/SDDM/raspi-config |
