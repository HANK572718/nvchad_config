# 系統工具設定：tmux + jumpfwd（跨機器複製指南）

把這台樹莓派上兩套「終端系統工具」的**設定方式**與**目前狀態**打包成腳本＋文件，
方便其他 Linux 機器（含 x86_64 桌機／伺服器）直接參照本機、快速設成一樣的環境。

| 工具 | 是什麼 | 為何可攜到 x86_64 |
|------|--------|-------------------|
| **tmux** | 終端多工器（分割視窗、session 保存、免 GUI 多工） | 純文字設定檔 + tpm 插件，與 CPU 架構無關 |
| **jumpfwd (`jf`)** | 用 `socat`(+Tailscale) 集中管理 TCP port 轉發的 Bash CLI | **是 Bash 腳本非編譯二進位**，依賴（`jq`/`socat`…）各發行版皆有 |

> 兩者本機都在 aarch64（Pi）上運行；因為都是**腳本 / 純設定**，複製到 x86_64 完全無相容性問題。

---

## 1. 一鍵複製到其他機器

在目標機器上 clone 本 repo 後（或已有本 nvim 設定），執行：

```bash
# 全部安裝（tmux + jumpfwd）
bash ~/.config/nvim/script/setup-devtools.sh --all

# 或只裝其一
bash ~/.config/nvim/script/setup-devtools.sh --tmux
bash ~/.config/nvim/script/setup-devtools.sh --jumpfwd

# 先看目前狀態（不需 sudo）
bash ~/.config/nvim/script/setup-devtools.sh --status

# 不帶參數 → 互動選單
bash ~/.config/nvim/script/setup-devtools.sh
```

腳本特性：**跨發行版**（自動偵測 `apt`/`dnf`/`pacman`/`zypper`）、**冪等**（可重複執行）、
覆蓋既有設定前會自動 `*.bak.<timestamp>` 備份。

---

## 2. 本機目前狀態（複製對象的基準）

> 這是「參考對象」——其他機器照著設，就會得到與此表一致的環境。

### tmux

| 項目 | 現值 |
|------|------|
| 版本 | tmux 3.5a |
| 設定檔 | `~/.tmux.conf`（本 repo `script/devtools/tmux.conf` 為 source of truth） |
| Plugin manager | tpm（`~/.tmux/plugins/tpm`） |
| 已裝插件 | `tmux-resurrect`（session 保存 / 還原） |

### jumpfwd (`jf`)

| 項目 | 現值 |
|------|------|
| 執行檔 | `~/.local/bin/jf`（Bash，約 990 行） |
| 設定檔 | `~/.config/jumpfwd/config.json` |
| 設備數 / 規則數 | **12 台設備、38 條轉發** |
| 群組分布 | `web`×15、`vnc`×6、`ssh`×5、`rdp`×4、`misc`×4、`smb`×3、`dev`×1 |
| systemd 服務 | `jumpfwd.service`（`--user`，**enabled + active**） |
| linger | 已啟用（未登入時轉發持續運行） |

> `config.json` 內含內部網段 IP 與服務清單，屬敏感資訊，**不入庫**（見 [§6 安全](#6-安全與設定同步)）。
> repo 只提供去識別化的 `config.example.json`；上表是本機當下的規模摘要。

---

## 3. tmux 設定說明

設定檔：[`script/devtools/tmux.conf`](../script/devtools/tmux.conf) → 部署到 `~/.tmux.conf`。

### 關鍵設定與理由

| 設定 | 作用 | 理由 |
|------|------|------|
| `xterm-keys on` + `escape-time 10` | 正確傳遞 Alt 鍵、縮短 Esc 延遲 | 修正 Neovim 內 `Alt+i` 等被吃掉、`<Esc>` 有延遲 |
| `mouse on` | 滑鼠 / 觸控滾動 | 支援 Blink Shell 等觸控終端 |
| `mode-keys vi` | copy-mode 用 vi 鍵 | 與 Neovim 手感一致 |
| `default-terminal tmux-256color` + `RGB` override | True Color | 讓主題色正確 |
| `base-index 1` / `pane-base-index 1` / `renumber-windows on` | window 從 1 編號並自動重排 | 配合 Alt+數字切換 |

### 按鍵速查

| 按鍵 | 動作 |
|------|------|
| `prefix`（`Ctrl-b`）+ `\|` / `-` | 垂直 / 水平分割（保留當前路徑） |
| `prefix` + `h/j/k/l` | 切換 pane（vim 風格） |
| `prefix` + `r` | 重載 `~/.tmux.conf` |
| `prefix` + `s` | choose-tree（依 session 名稱排序） |
| `Alt+Shift+1..9` | 直接切換 window（**免 prefix**） |
| `Ctrl+Shift+←/→` | 把當前 window 往左 / 右搬並跟隨 |
| `prefix` + `I` | tpm 安裝插件（首次或新增插件時） |
| `prefix` + `Ctrl-s` / `Ctrl-r` | tmux-resurrect 儲存 / 還原 session |

### 插件安裝流程（腳本已自動化）

`--tmux` 會：安裝 tmux → 部署 `~/.tmux.conf` → clone tpm → headless 跑
`~/.tmux/plugins/tpm/bin/install_plugins`。若自動安裝不完整，進 tmux 後按 `prefix + I` 補裝。

---

## 4. jumpfwd (`jf`) 設定說明

> 一句話：用 `socat` 把區網多台機器的服務 port 監聽在本機 localhost，再透過 **Tailscale**，
> 讓 tailnet 上任何裝置用「本機 Tailscale IP : 本地 port」連到那些區網機器——
> 不必逐台裝 Tailscale。

完整手冊隨工具一起 vendored：[`script/devtools/jumpfwd/README.md`](../script/devtools/jumpfwd/README.md)。以下為重點。

### 運作原理

每筆規則背景跑一個 socat：

```bash
socat TCP-LISTEN:<local_port>,reuseaddr,fork  TCP:<device_ip>:<remote_port>
```

執行期狀態：PID 存 `~/.local/run/jumpfwd/<name>.pid`、log 存 `~/.local/log/jumpfwd/<name>.log`。

```
tailnet 裝置 ──(Tailscale)──▶ 本機:本地port ──(socat)──▶ 區網機器:遠端port
```

### 依賴

| 類別 | 套件 | 用途 | 各發行版套件名 |
|------|------|------|----------------|
| **必需** | `jq` | 解析 / 改寫 `config.json` | 各家皆為 `jq` |
| **必需** | `socat` | 實際做 TCP 轉發 | 各家皆為 `socat` |
| 選用 | `tailscale` | `jf connect` 顯示 tailnet IP；服務在 `tailscaled` 之後啟動 | 見 tailscale 官方安裝 |
| 選用 | `websockify` + `novnc` | `jf novnc`（瀏覽器 VNC） | apt: `novnc websockify`／dnf: `novnc python3-websockify`／pacman: AUR |
| 選用 | `fping` + `nc` | `jf scan`（掃區網 + 探 port） | nc：apt `netcat-openbsd`／dnf `nmap-ncat`／pacman `openbsd-netcat` |

`--jumpfwd` 只自動裝**必需**的 `jq`+`socat`；選用依賴會偵測並提示，交由你決定是否安裝。

### 設定檔 Schema（`~/.config/jumpfwd/config.json`）

```json
{
  "devices": {
    "jetson": { "ip": "192.168.168.46", "desc": "Jetson Orin" }
  },
  "forwards": [
    { "name": "jetson-rdp", "device": "jetson",
      "local_port": 13346, "remote_port": 3389,
      "proto": "tcp", "desc": "Jetson 遠端桌面", "group": "rdp" }
  ]
}
```

- `devices`：`key → { ip, desc }`，供 `forwards.device` 與 `device=<key>` 引用。
- `forwards[]`：`name`(唯一) / `device` / `local_port` / `remote_port` / `proto` / `desc` / `group`。
- `group` 慣例：`rdp` / `vnc` / `smb` / `ssh` / `web` / `dev` / `misc`。

### 常用指令

| 指令 | 說明 |
|------|------|
| `jf status` | 各轉發執行狀態 |
| `jf list` | 列出所有規則與設備 |
| `jf start [目標]` / `stop` / `restart` | 啟停（目標見下） |
| `jf connect` | 顯示 Tailscale IP + 每筆連線 port |
| `jf add` / `jf remove <name>` | 互動新增 / 刪除規則 |
| `jf scan [子網] [起] [終]` | 掃區網、建議並自動新增規則 |
| `jf open <ip> [groups...]` | 依 IP 啟動某設備轉發 |
| `jf novnc start\|stop\|status` | 瀏覽器 VNC（ws_port = local_port + 1000） |
| `jf install` / `uninstall` | 安裝 / 移除 systemd `--user` 服務 |
| `jf menu` | 互動式 TUI 選單 |

**目標語法**：（空白）=全部、`<name>`=單筆、`group=rdp`=整個群組、`device=jetson`=該設備全部。

```bash
jf start                 # 全部
jf start group=rdp       # 整個 rdp 群組
jf start device=jetson   # jetson 的全部規則
```

### systemd 開機自啟

`jf install` 會建立 `~/.config/systemd/user/jumpfwd.service`（`ExecStart=jf start`，
`After=tailscaled.service`）。`--jumpfwd` 會詢問是否安裝，並自動 `enable-linger`
（讓你未登入時轉發也持續）。

```bash
systemctl --user status jumpfwd.service
journalctl --user -u jumpfwd.service -f
```

---

## 5. 跨平台（x86_64）注意事項

| 面向 | 說明 |
|------|------|
| 架構 | `jf` 與 `tmux.conf` 皆為腳本 / 純文字，**aarch64 → x86_64 直接可用**，無需重編譯 |
| 發行版 | `setup-devtools.sh` 自動偵測 `apt`/`dnf`/`pacman`/`zypper`；`unknown` 則列出待裝套件請手動安裝 |
| `~/.local/bin` | 若不在 PATH，腳本會寫進 `~/.bashrc` 並提示 `source ~/.bashrc` |
| Tailscale | 選用。無 Tailscale 時 `jf` 仍能在 LAN 內做本地轉發，只是 `connect` 顯示「未連線」 |
| noVNC 路徑 | `jf` 預設 `/usr/share/novnc`；某些發行版路徑不同，需要用到再調整 |

---

## 6. 安全與設定同步

- `jf` 監聽的 port 建議**只經 Tailscale** 對 tailnet 提供存取；**勿**用 NAT / 公網 port forwarding 暴露到 Internet。
- 真實的 `~/.config/jumpfwd/config.json` 含內部 IP 與服務清單，**不要入庫**
  （本 repo 僅提供去識別化的 `config.example.json`）。
- **要把本機這 38 條規則原封搬到另一台？** 別走 git，直接複製設定檔：

  ```bash
  # 從這台 Pi 推到目標機（走 SSH / Tailscale）
  scp ~/.config/jumpfwd/config.json  user@目標機:~/.config/jumpfwd/config.json
  # 目標機上載入服務
  jf install && systemctl --user restart jumpfwd.service
  ```

---

## 7. 檔案結構

```
~/.config/nvim/
├── docs/
│   └── DEVTOOLS_SETUP.md              本文件
└── script/
    ├── setup-devtools.sh              ← 唯一進入點（--all/--tmux/--jumpfwd/--status）
    └── devtools/
        ├── tmux.conf                  tmux 設定（→ ~/.tmux.conf）
        └── jumpfwd/
            ├── jf                     JumpForward CLI（→ ~/.local/bin/jf）
            ├── config.example.json    去識別化範例設定
            └── README.md              jf 完整手冊（vendored 自上游）
```

部署到系統的位置：

| 來源 | 目的 |
|------|------|
| `script/devtools/tmux.conf` | `~/.tmux.conf` |
| `script/devtools/jumpfwd/jf` | `~/.local/bin/jf` |
| `script/devtools/jumpfwd/config.example.json` | `~/.config/jumpfwd/config.json`（僅在不存在時） |
| tpm（git clone） | `~/.tmux/plugins/tpm` |
| `jf install` 產生 | `~/.config/systemd/user/jumpfwd.service` |

---

## 8. 常見故障排查

### `jf: command not found`
`~/.local/bin` 不在 PATH。`source ~/.bashrc` 或重開 shell；或重跑 `setup-devtools.sh --jumpfwd`。

### `需要安裝 jq / socat`
必需依賴缺失：`setup-devtools.sh --jumpfwd` 會自動裝；手動則 `sudo apt install jq socat`（或對應發行版）。

### tmux 插件沒作用（如 resurrect 沒反應）
tpm 沒把插件裝起來。進 tmux 按 `prefix + I`；或重跑 `setup-devtools.sh --tmux`。

### 服務有 enable 但重開機沒自動轉發
多半是未啟用 linger：`sudo loginctl enable-linger $USER`，再 `systemctl --user restart jumpfwd.service`。

### 某筆轉發連不上
`jf status` 看該筆是否運行；`jf log <name>` 看 socat log；確認目標區網機器的服務確實在該 port 監聽。
