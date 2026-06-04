# SSH Key-Based Login Guide

不使用帳號密碼，改用金鑰對進行身份驗證的完整設定流程，以及多台設備的安全管理方式。

---

## 目錄

1. [基本概念](#基本概念)
2. [Client 端設定](#client-端設定)
3. [Server 端設定](#server-端設定)
4. [測試連線](#測試連線)
5. [管理多台設備](#管理多台設備)
6. [安全強化建議](#安全強化建議)
7. [常見問題排查](#常見問題排查)

---

## 基本概念

SSH key 登入使用**非對稱加密**：

```
私鑰 (id_ed25519)     → 只留在你的電腦，絕對不外流
公鑰 (id_ed25519.pub) → 複製到要登入的遠端伺服器
```

登入時，伺服器確認「你持有對應私鑰」而非驗證密碼。
私鑰留在自己手中，攻擊者就算拿到伺服器也無法偽造登入。

### 金鑰演算法選擇

| 演算法 | 推薦程度 | 說明 |
|--------|---------|------|
| `ed25519` | ✅ **首選** | 現代、短小、快速、安全 |
| `ecdsa`   | ✅ 可用 | 需要指定 `-b 256/384/521` |
| `rsa`     | ⚠️ 舊版相容 | 需 `-b 4096`，較大 |
| `dsa`     | ❌ 禁用 | 已廢棄 |

---

## Client 端設定

### 1. 生成金鑰對

```powershell
# 推薦：ed25519（Windows / Linux / macOS 通用）
ssh-keygen -t ed25519 -C "your_label_here"

# 指定路徑（管理多個金鑰時必做）
ssh-keygen -t ed25519 -f "$HOME\.ssh\id_ed25519_server1" -C "server1-2025"
```

執行後：
- 輸入 passphrase（強烈建議設定，即使私鑰外洩也需要密碼才能使用）
- 生成 `id_ed25519`（私鑰）和 `id_ed25519.pub`（公鑰）

### 2. `~/.ssh/` 目錄結構

```
~/.ssh/
├── config                  ← 連線設定（主機別名、指定金鑰）
├── id_ed25519              ← 私鑰（chmod 600，不可給他人）
├── id_ed25519.pub          ← 公鑰（可公開，複製到伺服器）
├── id_ed25519_work         ← 工作用私鑰
├── id_ed25519_work.pub
├── known_hosts             ← 已知伺服器指紋（自動維護）
└── known_hosts.old
```

### 3. SSH Config 設定多台主機

`~/.ssh/config` 讓你用別名連線，並自動選擇正確金鑰：

```sshconfig
# ── 基本範例 ─────────────────────────────────────────
Host homeserver
    HostName 192.168.1.100
    User      alice
    Port      22
    IdentityFile ~/.ssh/id_ed25519_home

Host workserver
    HostName work.example.com
    User      alice
    Port      2222
    IdentityFile ~/.ssh/id_ed25519_work

# ── 透過跳板機（Jump Host）連到內網 ─────────────────
Host internal-db
    HostName 10.0.0.50
    User      dbadmin
    ProxyJump homeserver          # 先 SSH 到 homeserver 再跳

# ── 全域預設（套用所有 Host）────────────────────────
Host *
    ServerAliveInterval 60        # 每 60 秒送心跳，防中斷
    ServerAliveCountMax 3
    AddKeysToAgent yes            # 自動加入 ssh-agent
    IdentitiesOnly yes            # 只用 IdentityFile，不亂試其他金鑰
```

設定後直接用別名連線：

```powershell
ssh homeserver      # 等同 ssh -i ~/.ssh/id_ed25519_home -p 22 alice@192.168.1.100
ssh workserver
ssh internal-db
```

### 4. ssh-agent（避免每次輸入 passphrase）

```powershell
# Windows：啟動 ssh-agent 服務（一次性設定）
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent

# 新增私鑰（輸入一次 passphrase 後本次 session 都不再問）
ssh-add ~/.ssh/id_ed25519_home
ssh-add ~/.ssh/id_ed25519_work

# 查看已載入的金鑰
ssh-add -l
```

---

## Server 端設定

### 1. 將公鑰複製到伺服器

**方法 A：ssh-copy-id（Linux server）**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519_home.pub alice@192.168.1.100
```

**方法 B：手動貼上（Windows server / 無 ssh-copy-id）**
```powershell
# Client 端：顯示公鑰
Get-Content ~/.ssh/id_ed25519_home.pub

# Server 端（Windows），以管理員身份執行：
# 若對象是 Administrators 群組成員：
Add-Content "$env:ProgramData\ssh\administrators_authorized_keys" "（貼上公鑰）"
icacls "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:(F)" /grant "SYSTEM:(F)"

# 若對象是一般使用者：
$user = "alice"
$dir  = "C:\Users\$user\.ssh"
New-Item $dir -ItemType Directory -Force
Add-Content "$dir\authorized_keys" "（貼上公鑰）"
icacls $dir              /inheritance:r /grant "${user}:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F"
icacls "$dir\authorized_keys" /inheritance:r /grant "${user}:(F)" /grant "Administrators:(F)" /grant "SYSTEM:(F)"
```

> **Windows 特別說明**：Windows OpenSSH 對 `authorized_keys` 權限非常嚴格。
> 若 ACL 不正確，金鑰登入會靜默失敗，看起來像密碼錯誤。

### 2. sshd_config 關鍵設定

位置：`C:\ProgramData\ssh\sshd_config`（Windows）或 `/etc/ssh/sshd_config`（Linux）

```sshconfig
# 啟用金鑰登入
PubkeyAuthentication yes

# 關閉密碼登入（確認金鑰登入正常後再做這步）
PasswordAuthentication no
ChallengeResponseAuthentication no

# 安全強化
PermitRootLogin prohibit-password    # 禁止以 root + 密碼登入
MaxAuthTries 3                       # 限制嘗試次數，防暴力破解
LoginGraceTime 30                    # 30 秒內未完成登入就斷線

# 保持連線存活
ClientAliveInterval 300
ClientAliveCountMax 2

# 只允許特定使用者（選用）
AllowUsers alice bob
```

套用設定：

```powershell
# Windows
Restart-Service sshd

# Linux
sudo systemctl restart sshd
```

### 3. 驗證設定語法

```powershell
# Windows
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -t

# Linux
sudo sshd -t
```

---

## 測試連線

### 測試流程

```powershell
# 1. 詳細模式連線，觀察認證過程
ssh -v alice@192.168.1.100

# 2. 指定金鑰測試
ssh -i ~/.ssh/id_ed25519_home alice@192.168.1.100

# 3. 用 config 別名
ssh homeserver
```

### 連線成功的 verbose 輸出關鍵訊息

```
debug1: Offering public key: ~/.ssh/id_ed25519_home ED25519 ...
debug1: Server accepts key: ...
debug1: Authentication succeeded (publickey).
```

若出現 `Permission denied (publickey)` 表示：
- 公鑰未正確放到伺服器
- 伺服器端權限設定錯誤（Windows 最常見）
- `sshd_config` 中 `PubkeyAuthentication` 未啟用

---

## 管理多台設備

### 情境一：個人開發者，管理 3~10 台主機

**建議結構：每台主機一把金鑰**

```
~/.ssh/
├── config
├── id_ed25519_home          ← 家用 NAS / 路由器
├── id_ed25519_vps_us        ← 美國 VPS
├── id_ed25519_vps_tw        ← 台灣 VPS
├── id_ed25519_work_laptop   ← 公司筆電
└── known_hosts
```

優點：一把金鑰洩漏只影響一台主機。
缺點：金鑰數量多，需要管理。

**config 範例：**

```sshconfig
Host nas
    HostName 192.168.1.10
    User     admin
    IdentityFile ~/.ssh/id_ed25519_home

Host vps-us
    HostName 12.34.56.78
    User     ubuntu
    IdentityFile ~/.ssh/id_ed25519_vps_us

Host vps-tw
    HostName 98.76.54.32
    User     ubuntu
    IdentityFile ~/.ssh/id_ed25519_vps_tw
```

---

### 情境二：需要從多台電腦登入同一台伺服器

在伺服器的 `authorized_keys` 放**多把公鑰**，每行一把：

```
ssh-ed25519 AAAA...home_desktop home-desktop-2025
ssh-ed25519 AAAA...work_laptop  work-laptop-2025
ssh-ed25519 AAAA...phone_termux phone-termux-2025
```

撤銷某裝置的存取：直接刪除對應那行。

---

### 情境三：多人共用伺服器

每個人生成自己的金鑰，管理員將各人公鑰加到對應帳號的 `authorized_keys`：

```
/home/alice/.ssh/authorized_keys  ← alice 的公鑰
/home/bob/.ssh/authorized_keys    ← bob 的公鑰
C:\ProgramData\ssh\administrators_authorized_keys  ← Windows 管理員公鑰
```

**不要共用私鑰**：每個人持有自己的私鑰。

---

### 金鑰輪換（定期更換）

建議每 1~2 年輪換一次，或人員異動時立即輪換：

```powershell
# 1. 在 Client 生成新金鑰
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_home_new -C "home-2026"

# 2. 將新公鑰加到所有目標 server
# （此時新舊金鑰都可登入）

# 3. 測試新金鑰可正常登入

# 4. 從 server 的 authorized_keys 刪除舊公鑰

# 5. 刪除舊私鑰（或封存）
```

---

## 安全強化建議

### Client 端

| 項目 | 建議做法 |
|------|---------|
| Passphrase | **必須設定**，即使私鑰被竊也需要解密 |
| 私鑰權限 | `600`（只有自己可讀，Windows 用 icacls 控制） |
| 金鑰備份 | 加密後備份到離線媒體（不要備份到雲端） |
| `IdentitiesOnly yes` | 防止 ssh-agent 把所有金鑰一一試到伺服器（暴露金鑰清單） |
| `known_hosts` | 不要用 `StrictHostKeyChecking no`，應驗證指紋 |

### Server 端

| 項目 | 建議做法 |
|------|---------|
| 停用密碼登入 | `PasswordAuthentication no` |
| 停用 root 密碼登入 | `PermitRootLogin prohibit-password` |
| 限制使用者 | `AllowUsers alice bob`，只允許需要的帳號 |
| 更改 Port | 改成非 22（減少自動掃描攻擊，不是真正安全措施）|
| Fail2ban / 防護 | Linux 裝 fail2ban；Windows 用 Event Log + 防火牆規則 |
| 定期審查 authorized_keys | 移除離職員工、舊裝置的公鑰 |
| 使用 ed25519 | 禁用弱演算法：`HostKeyAlgorithms` 設定 |

### 禁用弱演算法（sshd_config 進階設定）

```sshconfig
# 只允許現代演算法
HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp256
KexAlgorithms curve25519-sha256,ecdh-sha2-nistp256
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,chacha20-poly1305@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
```

---

## 常見問題排查

### Permission denied (publickey)

**Windows Server 最常見原因：authorized_keys 權限不正確**

```powershell
# 修復 administrators_authorized_keys
icacls "$env:ProgramData\ssh\administrators_authorized_keys" `
    /inheritance:r /grant "Administrators:(F)" /grant "SYSTEM:(F)"

# 修復一般使用者
$u = "alice"
icacls "C:\Users\$u\.ssh" /inheritance:r /grant "${u}:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F"
icacls "C:\Users\$u\.ssh\authorized_keys" /inheritance:r /grant "${u}:(F)" /grant "Administrators:(F)" /grant "SYSTEM:(F)"
```

**診斷步驟：**

```powershell
# 1. 客戶端詳細輸出
ssh -vvv user@host 2>&1 | Select-String "key|auth|debug1"

# 2. 伺服器端日誌（Windows）
Get-EventLog -LogName Application -Source *ssh* -Newest 20 |
    Select-Object TimeGenerated, Message

# 3. 確認 sshd_config 設定生效
ssh -v user@host 2>&1 | Select-String "PasswordAuthentication|PubkeyAuthentication"
```

### known_hosts 警告（Host key changed）

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
```

可能原因：主機重裝、IP 被重新指派、或中間人攻擊。

**確認無誤後移除舊紀錄：**

```powershell
# 移除特定主機的 known_hosts 記錄
ssh-keygen -R 192.168.1.100
ssh-keygen -R homeserver

# 或手動編輯 ~/.ssh/known_hosts 刪除對應行
```

### ssh-agent 無法找到金鑰

```powershell
# 確認 service 在跑
Get-Service ssh-agent | Select Status, StartType

# 重新加入金鑰
ssh-add ~/.ssh/id_ed25519_home
```

---

## 快速備忘

```powershell
# 生成金鑰
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_HOST -C "HOST-$(Get-Date -Format yyyy)"

# 複製公鑰到剪貼簿
Get-Content ~/.ssh/id_ed25519_HOST.pub | Set-Clipboard

# 測試連線（詳細模式）
ssh -v -i ~/.ssh/id_ed25519_HOST user@host

# 查看伺服器指紋（在 server 執行）
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key          # Linux
ssh-keygen -lf "$env:ProgramData\ssh\ssh_host_ed25519_key"  # Windows

# 管理 ssh-agent
ssh-add -l            # 列出已載入金鑰
ssh-add -D            # 移除所有金鑰
ssh-add ~/.ssh/id_ed25519_HOST  # 加入金鑰
```
