# jumpfwd (`jf`)

> 用 **socat + Tailscale** 把區網裡多台機器的服務 port 轉發到這台 Pi 的 localhost，於是從 tailnet 上任何裝置，都能用「Pi 的 Tailscale IP : 本地 port」直接連到那些區網機器。

`jf` 是一支單一檔案的 Bash CLI（約 990 行，`set -euo pipefail`），用來在 homelab 的 Raspberry Pi 上集中管理 TCP port 轉發。

---

## 目錄

- [設計動機](#設計動機)
- [架構與運作原理](#架構與運作原理)
- [相依套件](#相依套件)
- [安裝](#安裝)
- [設定檔 Schema](#設定檔-schema)
- [目標語法](#目標語法)
- [指令總覽](#指令總覽)
- [noVNC](#novnc)
- [scan 與 open](#scan-與-open)
- [systemd 開機自啟](#systemd-開機自啟)
- [本地 port 配置慣例](#本地-port-配置慣例)
- [常見範例](#常見範例)
- [安全注意](#安全注意)

---

## 設計動機

家裡的區網有很多機器（RDP、VNC、SMB、SSH、Web…），但這些服務只在 LAN 內可達。這台 Pi 同時是一個 Tailscale 節點，所以只要：

1. 在 Pi 上用 `socat` 把「某台區網機器的某個 port」監聽在 Pi 的某個 **localhost port**；
2. 透過 Tailscale，從 tailnet 任何裝置連到 **Pi 的 Tailscale IP : 那個本地 port**；

就能把整個區網的服務「投影」到 tailnet 上，而不需要逐台機器都裝 Tailscale。`jf` 就是把這套「建立 / 啟停 / 查狀態 / 掃描 / 自動分配 port」的流程包成一支好用的 CLI。

---

## 架構與運作原理

每一筆 forward 規則，`jf` 都會在背景啟動一個 `socat` 行程：

```bash
socat TCP-LISTEN:<local_port>,reuseaddr,fork TCP:<device_ip>:<remote_port>
```

- `TCP-LISTEN:<local_port>,reuseaddr,fork`：在 Pi 上監聽某個本地 port，`fork` 讓每條連線各自分流，`reuseaddr` 方便重啟。
- `TCP:<device_ip>:<remote_port>`：把連線轉送到區網機器的目標 port。

執行期狀態檔放在使用者家目錄底下：

| 用途 | 路徑 |
|------|------|
| 每筆 forward 的 PID | `~/.local/run/jumpfwd/<name>.pid` |
| 每筆 forward 的 log | `~/.local/log/jumpfwd/<name>.log` |
| noVNC 的 PID | `~/.local/run/novnc/` |

連線路徑示意：

```
tailnet 裝置 ──(Tailscale)──> Pi:本地port ──(socat)──> 區網機器:遠端port
```

---

## 相依套件

| 類別 | 套件 | 說明 |
|------|------|------|
| 必需 | `jq` | 解析 / 操作設定檔 |
| 必需 | `socat` | 實際做 TCP port 轉發 |
| 選用 | `tailscale` | `connect` 顯示 Tailscale IP、自啟在 `tailscaled` 之後 |
| 選用 | `websockify` + `novnc` | `novnc` 指令所需（瀏覽器 VNC） |
| 選用 | `fping` + `nc` | `scan` 指令所需（掃存活主機 + 探測 port） |

```bash
# Debian / Raspberry Pi OS 範例
sudo apt install jq socat
# 選用
sudo apt install tailscale websockify novnc fping netcat-openbsd
```

---

## 安裝

把腳本放到 `~/.local/bin/jf`、加上執行權限，並建立設定檔：

```bash
# 1. 安裝腳本
mkdir -p ~/.local/bin
cp jf ~/.local/bin/jf
chmod +x ~/.local/bin/jf

# 2. 確認 ~/.local/bin 在 PATH 內（多數發行版預設已有）
#    若沒有，將下行加入 ~/.bashrc 後重開 shell：
#    export PATH="$HOME/.local/bin:$PATH"

# 3. 建立設定檔
mkdir -p ~/.config/jumpfwd
cp config.example.json ~/.config/jumpfwd/config.json
# 編輯成你的真實設備與規則
nano ~/.config/jumpfwd/config.json
```

> repo 內含 `jf`（腳本）、`config.example.json`（去識別化範例）、`.gitignore`（忽略個人 `config.json`）、`README.md`。**真實的 `config.json` 不入庫。**

---

## 設定檔 Schema

設定檔位於 `~/.config/jumpfwd/config.json`，分為兩個區塊：`devices` 與 `forwards`。

```json
{
  "devices": {
    "jetson": { "ip": "192.168.168.46", "desc": "Jetson Orin 開發板" },
    "nas":    { "ip": "192.168.168.10", "desc": "群暉 NAS" }
  },
  "forwards": [
    {
      "name": "jetson-rdp",
      "device": "jetson",
      "local_port": 13346,
      "remote_port": 3389,
      "proto": "tcp",
      "desc": "Jetson 遠端桌面",
      "group": "rdp"
    },
    {
      "name": "nas-web",
      "device": "nas",
      "local_port": 18010,
      "remote_port": 5000,
      "proto": "tcp",
      "desc": "NAS 管理介面",
      "group": "web"
    }
  ]
}
```

### `devices`（物件 map：`key -> { ip, desc }`）

| 欄位 | 說明 |
|------|------|
| `key` | 設備代號（如 `jetson`），在 `forwards.device` 與 `device=<key>` 目標語法引用 |
| `ip` | 該設備的區網 IP |
| `desc` | 描述 |

### `forwards`（陣列：每筆一個 forward 規則）

| 欄位 | 說明 |
|------|------|
| `name` | 規則名稱（唯一），可作 `<name>` 目標 |
| `device` | 對應 `devices` 的 key |
| `local_port` | 在 Pi 上監聽的本地 port |
| `remote_port` | 區網機器上的目標 port |
| `proto` | 通訊協定（`tcp`） |
| `desc` | 描述 |
| `group` | 群組分類，用於 `group=<g>` 目標語法 |

### `group` 慣例

| group | 用途 |
|-------|------|
| `rdp` | 遠端桌面 |
| `vnc` | VNC（亦供 `novnc` 使用） |
| `smb` | 檔案分享 |
| `ssh` | SSH |
| `web` | HTTP/HTTPS 服務 |
| `dev` | 開發用途 |
| `misc` | 其他 |

---

## 目標語法

多數指令都接受「目標」參數，用來指定要作用在哪些 forward 上：

| 目標 | 意義 |
|------|------|
| （空白） | 全部 forward |
| `<name>` | 單筆規則 |
| `group=<g>` | 整個群組 |
| `device=<key>` | 該設備的全部規則 |

```bash
jf start                 # 啟動全部
jf start jetson-rdp      # 只啟動單筆
jf start group=rdp       # 啟動整個 rdp 群組
jf start device=jetson   # 啟動 jetson 的全部規則
```

---

## 指令總覽

| 指令 | 說明 |
|------|------|
| `jf status` | 顯示各 forward 的執行狀態 |
| `jf start [目標]` | 啟動 forward（背景跑 socat、記錄 PID） |
| `jf stop [目標]` | 停止 forward |
| `jf restart [目標]` | 重啟 forward |
| `jf list` | 列出所有設定的 forward 規則 |
| `jf connect` | 顯示 Pi 的 Tailscale IP，以及每筆 forward 的連線 port |
| `jf add` | 互動式新增一筆 forward 規則 |
| `jf remove [目標]` | 移除 forward 規則 |
| `jf log [目標]` | `tail -f` 對應的 log 檔 |
| `jf install` | 安裝 systemd `--user` 服務 `jumpfwd.service`（開機自啟） |
| `jf uninstall` | 移除該 systemd 服務 |
| `jf menu` | 互動式 TUI 選單 |
| `jf scan` | 用 `fping` 掃子網存活主機 + `nc` 探測常見 port，建議並自動新增 forward 規則 |
| `jf open <ip> [groups...]` | 依 IP 啟動某設備的轉發 |
| `jf novnc start\|stop\|status` | 用 websockify 為 vnc 群組啟動瀏覽器 VNC |

---

## noVNC

`jf novnc` 用 `websockify` 為 `vnc` 群組的規則啟動瀏覽器可用的 VNC（noVNC）。

- WebSocket port 規則：**`ws_port = local_port + 1000`**
- 連線網址：**`http://<tailscale-ip>:<ws_port>/vnc.html`**

```bash
jf novnc start    # 為 vnc 群組起 websockify
jf novnc status   # 查看狀態
jf novnc stop     # 停止
```

例如某筆 vnc 規則 `local_port` 為 `15946`，則 `ws_port` 為 `16946`，瀏覽器開 `http://<tailscale-ip>:16946/vnc.html`。

> noVNC 的 PID 檔放在 `~/.local/run/novnc/`。

---

## scan 與 open

### `jf scan`

用 `fping` 掃整個子網找出存活主機，再用 `nc` 探測常見 port，依結果**建議並自動新增** forward 規則（本地 port 依下方慣例自動分配，並自動避開衝突）。

```bash
jf scan
```

### `jf open`

依 IP 啟動某設備的轉發，可選擇只開某些群組：

```bash
jf open 192.168.168.46            # 開該 IP 全部
jf open 192.168.168.46 rdp vnc    # 只開 rdp 與 vnc 群組
```

---

## systemd 開機自啟

`jf install` 會建立一個 systemd `--user` 服務 `jumpfwd.service`，其 `ExecStart=jf start`，並設定為**開機時、在 `tailscaled` 之後**自動啟動全部 forward。

```bash
jf install      # 安裝並啟用服務
jf uninstall    # 停用並移除
```

安裝後可用標準 systemd 指令檢視：

```bash
systemctl --user status jumpfwd.service
journalctl --user -u jumpfwd.service -f
```

> 若希望使用者未登入時服務也能持續執行，需啟用 lingering：`sudo loginctl enable-linger $USER`。

---

## 本地 port 配置慣例

`scan` 與 `add` 自動分配本地 port 時，依群組採用以下前綴（`xx` 為設備 IP 末碼），並自動避開已被佔用的 port：

| 群組 | 前綴 | 範例（IP 末碼 46） |
|------|------|-------------------|
| RDP | `133xx` | `13346` |
| VNC | `159xx` | `15946` |
| SSH | `122xx` | `12246` |
| SMB | `145xx` | `14546` |
| HTTP | `180xx` | `18046` |
| HTTPS | `144xx` | `14446` |

---

## 常見範例

```bash
jf start group=rdp                       # 啟動所有 RDP 轉發
jf start device=jetson                   # 啟動 jetson 的全部轉發
jf status                                # 看目前狀態
jf connect                               # 看 Tailscale IP 與各連線 port
jf novnc start                           # 起瀏覽器 VNC
jf scan                                  # 掃網段並自動建規則
jf open 192.168.168.46 rdp vnc           # 依 IP 啟動 rdp / vnc 轉發
```

---

## 安全注意

- `jf` 監聽的 port 只透過 **Tailscale** 對 tailnet 內的裝置提供存取，請確保你的 tailnet 成員與 ACL 設定得當。
- **不要**把這些本地 port 透過 NAT、port forwarding 或公網介面暴露到 Internet。
- noVNC 的網址同樣只應在 tailnet 內使用，不要對公網開放。
- 真實的 `~/.config/jumpfwd/config.json` 含有內部 IP 與服務資訊，**不要入庫**（repo 已在 `.gitignore` 忽略，僅提供去識別化的 `config.example.json`）。

