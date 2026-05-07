# OpenSSH Server 使用指南

本文件說明如何在 Windows 上安裝、設定和使用 OpenSSH Server,以及常用的管理命令。

---

## 📋 目錄

- [安裝與啟用](#安裝與啟用)
- [服務管理](#服務管理)
- [設定檔管理](#設定檔管理)
- [使用者與權限](#使用者與權限)
- [SSH 連線](#ssh-連線)
- [金鑰認證](#金鑰認證)
- [進階設定](#進階設定)
- [故障排除](#故障排除)

---

## 📦 安裝與啟用

### 檢查是否已安裝

```powershell
# 檢查 OpenSSH Server 是否已安裝
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

# 檢查 OpenSSH Client 是否已安裝
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
```

### 安裝 OpenSSH Server

```powershell
# 安裝 OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 安裝 OpenSSH Client（通常已預裝）
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### 確認安裝狀態

```powershell
# 查看安裝狀態（State 應為 Installed）
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*' |
    Select-Object Name, State
```

---

## 🔧 服務管理

### 啟動與停止服務

```powershell
# 啟動 SSH 服務
Start-Service sshd

# 停止 SSH 服務
Stop-Service sshd

# 重新啟動 SSH 服務
Restart-Service sshd

# 查看服務狀態
Get-Service sshd | Select-Object Name, Status, StartType
```

### 設定自動啟動

```powershell
# 設定 SSH 服務為自動啟動
Set-Service -Name sshd -StartupType 'Automatic'

# 確認服務設定
Get-Service sshd | Select-Object Name, Status, StartType

# 同時啟動並設定自動啟動
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd
```

### SSH Agent 服務

```powershell
# SSH Agent 用於管理 SSH 金鑰
# 啟動 SSH Agent
Start-Service ssh-agent

# 設定 SSH Agent 為自動啟動
Set-Service -Name ssh-agent -StartupType 'Automatic'

# 查看 SSH Agent 狀態
Get-Service ssh-agent
```

---

## 🛡️ 防火牆設定

### 開啟 SSH 端口 (22)

```powershell
# 檢查是否已有 SSH 防火牆規則
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

# 手動建立防火牆規則（如果不存在）
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
    -DisplayName "OpenSSH Server (sshd)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Action Allow `
    -Profile Any `
    -Program "%SystemRoot%\System32\OpenSSH\sshd.exe"

# 啟用現有規則
Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP"

# 查看 SSH 相關防火牆規則
Get-NetFirewallRule -DisplayName "*SSH*" | Format-Table DisplayName, Enabled, Direction, Action
```

### 限制連線來源

```powershell
# 只允許特定 IP 連線
New-NetFirewallRule -Name "SSH-Restricted" `
    -DisplayName "SSH (Restricted IP)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -RemoteAddress 192.168.1.100 `
    -Action Allow `
    -Profile Any

# 允許特定子網路
New-NetFirewallRule -Name "SSH-Subnet" `
    -DisplayName "SSH (Local Subnet)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -RemoteAddress 192.168.1.0/24 `
    -Action Allow `
    -Profile Private
```

---

## ⚙️ 設定檔管理

### 設定檔位置

```powershell
# SSH Server 主要設定檔
# 位置: C:\ProgramData\ssh\sshd_config

# 查看設定檔路徑
$sshdConfigPath = "$env:ProgramData\ssh\sshd_config"
Write-Host "SSH 設定檔位置: $sshdConfigPath"

# 檢查設定檔是否存在
if (Test-Path $sshdConfigPath) {
    Write-Host "設定檔存在" -ForegroundColor Green
} else {
    Write-Host "設定檔不存在" -ForegroundColor Red
}
```

### 編輯設定檔

```powershell
# 使用記事本編輯（需要管理員權限）
notepad.exe "$env:ProgramData\ssh\sshd_config"

# 使用 PowerShell ISE 編輯
powershell_ise.exe "$env:ProgramData\ssh\sshd_config"

# 使用 VS Code 編輯
code "$env:ProgramData\ssh\sshd_config"
```

### 常用設定項目

編輯 `sshd_config` 檔案,設定以下項目:

```bash
# 監聽端口（預設 22）
Port 22

# 監聽位址（預設所有介面）
#ListenAddress 0.0.0.0
#ListenAddress ::

# 允許密碼認證（預設 yes）
PasswordAuthentication yes

# 允許公鑰認證（預設 yes）
PubkeyAuthentication yes

# 允許 root 登入（Windows 無此設定）
#PermitRootLogin no

# 允許空密碼（預設 no，不建議啟用）
PermitEmptyPasswords no

# 啟用日誌記錄
SyslogFacility AUTH
LogLevel INFO

# 允許的使用者
#AllowUsers user1 user2

# 拒絕的使用者
#DenyUsers baduser

# 允許的群組
#AllowGroups ssh_users

# 設定閒置逾時（秒）
ClientAliveInterval 300
ClientAliveCountMax 2

# X11 轉發（圖形介面轉發）
X11Forwarding no

# 預設 Shell（Windows）
#Subsystem    sftp    sftp-server.exe
```

### 套用設定變更

```powershell
# 修改設定後,需要重新啟動服務
Restart-Service sshd

# 檢查服務是否正常啟動
Get-Service sshd

# 查看服務啟動日誌
Get-EventLog -LogName Application -Source sshd -Newest 10
```

---

## 👤 使用者與權限

### 查看可登入的使用者

```powershell
# 查看所有本機使用者
Get-LocalUser | Select-Object Name, Enabled | Format-Table

# 查看啟用的使用者
Get-LocalUser | Where-Object { $_.Enabled -eq $true } | Select-Object Name, LastLogon
```

### 建立 SSH 專用使用者

```powershell
# 建立新使用者
$username = "sshuser"
$password = Read-Host "輸入密碼" -AsSecureString
New-LocalUser -Name $username -Password $password -FullName "SSH User" -Description "SSH Access User" -PasswordNeverExpires

# 設定密碼永不過期
Set-LocalUser -Name $username -PasswordNeverExpires $true

# 查看使用者資訊
Get-LocalUser -Name $username | Format-List
```

### 設定使用者權限

```powershell
# 預設情況下,本機使用者即可透過 SSH 登入
# 如需限制特定使用者,編輯 sshd_config

# 加入到遠端桌面使用者群組（非必要）
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "sshuser"

# 加入到管理員群組（謹慎使用）
# Add-LocalGroupMember -Group "Administrators" -Member "sshuser"

# 查看使用者所屬群組
Get-LocalGroup | Where-Object {
    (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\sshuser"
}
```

---

## 🔑 SSH 連線

### 從本機測試連線

```powershell
# 連線到本機 SSH Server
ssh localhost

# 連線到本機 SSH Server（使用 127.0.0.1）
ssh 127.0.0.1

# 指定使用者名稱連線
ssh username@localhost

# 指定端口連線
ssh -p 22 username@localhost
```

### 從遠端連線

```powershell
# 連線到遠端 Windows SSH Server
ssh username@192.168.1.100

# 指定端口連線
ssh -p 22 username@192.168.1.100

# 顯示詳細連線資訊
ssh -v username@192.168.1.100

# 更詳細的除錯資訊
ssh -vv username@192.168.1.100
ssh -vvv username@192.168.1.100
```

### SSH 常用選項

```powershell
# -p: 指定端口
ssh -p 2222 username@host

# -i: 指定金鑰檔案
ssh -i C:\Users\User\.ssh\id_rsa username@host

# -v, -vv, -vvv: 顯示除錯資訊
ssh -v username@host

# -L: 本機端口轉發
ssh -L 8080:localhost:80 username@host

# -R: 遠端端口轉發
ssh -R 9090:localhost:3000 username@host

# -N: 不執行遠端命令（用於端口轉發）
ssh -N -L 8080:localhost:80 username@host

# -f: 背景執行
ssh -f -N -L 8080:localhost:80 username@host
```

### 執行遠端命令

```powershell
# 執行單一命令
ssh username@host "Get-Service | Select-Object -First 5"

# 執行多個命令
ssh username@host "cd C:\; dir; Get-Date"

# 執行 PowerShell 命令
ssh username@host "powershell -Command Get-Process"
```

---

## 🔐 金鑰認證設定

### 產生 SSH 金鑰對

```powershell
# 產生 RSA 金鑰對（預設 2048 位元）
ssh-keygen -t rsa -b 4096

# 產生 Ed25519 金鑰對（更安全,推薦）
ssh-keygen -t ed25519

# 指定金鑰檔案名稱和註解
ssh-keygen -t ed25519 -f C:\Users\User\.ssh\id_ed25519_work -C "work@email.com"

# 產生金鑰時不設定密碼（不安全,不建議）
ssh-keygen -t ed25519 -N ""
```

### 查看金鑰

```powershell
# 查看公鑰內容
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"

# 查看私鑰檔案（不要洩漏！）
# Get-Content "$env:USERPROFILE\.ssh\id_rsa"

# 列出所有金鑰
Get-ChildItem "$env:USERPROFILE\.ssh" | Format-Table Name, Length, LastWriteTime
```

### 設定 Server 端授權金鑰

在 **SSH Server** 端設定:

```powershell
# 1. 確認使用者的 .ssh 目錄存在
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force
}

# 2. 建立 authorized_keys 檔案
$authKeysFile = "$sshDir\authorized_keys"

# 3. 將公鑰內容加入 authorized_keys
# 方法 1: 手動複製公鑰內容
notepad.exe $authKeysFile

# 方法 2: 從檔案複製
$publicKey = Get-Content "C:\path\to\id_ed25519.pub"
Add-Content -Path $authKeysFile -Value $publicKey

# 4. 設定檔案權限（重要！）
# 移除繼承的權限
icacls.exe $authKeysFile /inheritance:r

# 只允許 SYSTEM 和當前使用者讀取
icacls.exe $authKeysFile /grant "SYSTEM:(F)"
icacls.exe $authKeysFile /grant "${env:USERNAME}:(F)"
```

### 管理員帳號的特殊設定

如果要為**管理員帳號**設定金鑰認證:

```powershell
# 管理員的授權金鑰檔案位置不同
$adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"

# 將公鑰加入管理員授權金鑰檔案
$publicKey = Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
Set-Content -Path $adminAuthKeys -Value $publicKey

# 設定檔案權限
icacls.exe $adminAuthKeys /inheritance:r
icacls.exe $adminAuthKeys /grant "SYSTEM:(F)"
icacls.exe $adminAuthKeys /grant "BUILTIN\Administrators:(F)"
```

### 從 Client 複製公鑰到 Server

```powershell
# Windows 沒有內建 ssh-copy-id,需手動複製

# 方法 1: 使用 SCP 複製（需先啟用密碼認證）
scp "$env:USERPROFILE\.ssh\id_ed25519.pub" username@host:C:\Users\username\.ssh\authorized_keys

# 方法 2: 透過 SSH 直接寫入
type "$env:USERPROFILE\.ssh\id_ed25519.pub" | ssh username@host "cat >> .ssh/authorized_keys"

# 方法 3: 手動複製（最可靠）
# 1. 查看公鑰內容
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
# 2. 複製內容
# 3. SSH 登入到 Server
ssh username@host
# 4. 在 Server 上貼上到 authorized_keys
# notepad C:\Users\username\.ssh\authorized_keys
```

### 測試金鑰認證

```powershell
# 使用金鑰登入（應該不需要密碼）
ssh username@host

# 指定金鑰檔案登入
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" username@host

# 顯示詳細認證過程
ssh -v username@host
```

### SSH Agent 管理金鑰

```powershell
# 啟動 SSH Agent 服務
Start-Service ssh-agent
Set-Service -Name ssh-agent -StartupType 'Automatic'

# 將金鑰加入 SSH Agent
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
ssh-add "$env:USERPROFILE\.ssh\id_rsa"

# 列出已加入的金鑰
ssh-add -l

# 刪除所有金鑰
ssh-add -D

# 刪除特定金鑰
ssh-add -d "$env:USERPROFILE\.ssh\id_ed25519"
```

---

## 🔬 進階設定

### 更改 SSH 預設端口

編輯 `sshd_config`:

```powershell
# 1. 編輯設定檔
notepad "$env:ProgramData\ssh\sshd_config"

# 2. 修改 Port 設定
# Port 2222

# 3. 重新啟動服務
Restart-Service sshd

# 4. 更新防火牆規則
Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
    -DisplayName "OpenSSH Server (Custom Port)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 2222 `
    -Action Allow `
    -Profile Any

# 5. 測試連線
ssh -p 2222 username@localhost
```

### 停用密碼認證（僅金鑰）

```powershell
# 1. 確保金鑰認證已設定完成並測試成功
# 2. 編輯 sshd_config
notepad "$env:ProgramData\ssh\sshd_config"

# 3. 修改以下設定
# PasswordAuthentication no
# PubkeyAuthentication yes

# 4. 重新啟動服務
Restart-Service sshd
```

### 限制登入使用者

編輯 `sshd_config`:

```bash
# 只允許特定使用者
AllowUsers user1 user2 admin

# 拒絕特定使用者
DenyUsers baduser

# 只允許特定群組
AllowGroups ssh_users administrators

# 拒絕特定群組
DenyGroups guests
```

### 設定 SSH Banner

```powershell
# 1. 建立 banner 檔案
$bannerFile = "$env:ProgramData\ssh\banner.txt"
@"
*********************************************
*  WARNING: Authorized Access Only         *
*  All activity is monitored and logged    *
*********************************************
"@ | Set-Content -Path $bannerFile

# 2. 編輯 sshd_config
notepad "$env:ProgramData\ssh\sshd_config"

# 3. 加入以下設定
# Banner C:/ProgramData/ssh/banner.txt

# 4. 重新啟動服務
Restart-Service sshd
```

### SSH 隧道與端口轉發

```powershell
# 本機端口轉發（Local Port Forwarding）
# 將本機 8080 轉發到遠端的 80
ssh -L 8080:localhost:80 username@remote_host

# 遠端端口轉發（Remote Port Forwarding）
# 將遠端 9090 轉發到本機的 3000
ssh -R 9090:localhost:3000 username@remote_host

# 動態端口轉發（SOCKS 代理）
ssh -D 1080 username@remote_host

# 背景執行隧道
ssh -f -N -L 8080:localhost:80 username@remote_host
```

---

## 📊 日誌與監控

### 查看 SSH 日誌

```powershell
# 查看最近的 SSH 相關事件
Get-EventLog -LogName Application -Source sshd -Newest 20

# 查看特定時間範圍的日誌
Get-EventLog -LogName Application -Source sshd -After (Get-Date).AddHours(-1)

# 查看錯誤日誌
Get-EventLog -LogName Application -Source sshd -EntryType Error -Newest 10

# 匯出日誌到 CSV
Get-EventLog -LogName Application -Source sshd -Newest 100 |
    Select-Object TimeGenerated, EntryType, Message |
    Export-Csv -Path "C:\Logs\ssh_log.csv" -NoTypeInformation -Encoding UTF8
```

### 查看目前 SSH 連線

```powershell
# 查看所有 SSH 連線（端口 22）
Get-NetTCPConnection -LocalPort 22 | Where-Object { $_.State -eq "Established" } |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess

# 查看連線的程序資訊
Get-NetTCPConnection -LocalPort 22 | Where-Object { $_.State -eq "Established" } |
    ForEach-Object {
        $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            RemoteIP = $_.RemoteAddress
            RemotePort = $_.RemotePort
            Process = $process.ProcessName
            PID = $_.OwningProcess
        }
    }
```

### 監控 SSH 服務

```powershell
# 持續監控 SSH 連線
while ($true) {
    Clear-Host
    Write-Host "=== SSH 連線監控 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -ForegroundColor Cyan

    Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Established" } |
        Select-Object RemoteAddress, RemotePort, State |
        Format-Table -AutoSize

    Start-Sleep -Seconds 5
}
```

---

## 🛠️ 故障排除

### 常見問題診斷

#### 1. 無法啟動 SSH 服務

```powershell
# 檢查服務狀態
Get-Service sshd

# 查看錯誤訊息
Get-EventLog -LogName Application -Source sshd -EntryType Error -Newest 5

# 檢查設定檔語法
# sshd -t  # （Windows OpenSSH 可能不支援）

# 重新安裝 OpenSSH Server
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

#### 2. 無法連線到 SSH Server

```powershell
# 檢查服務是否運作
Get-Service sshd | Select-Object Name, Status, StartType

# 檢查端口是否監聽
Get-NetTCPConnection -LocalPort 22

# 測試本機連線
ssh localhost

# 測試網路連通性
Test-NetConnection -ComputerName 192.168.1.100 -Port 22

# 檢查防火牆規則
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP"

# 檢查 Windows Defender 防火牆狀態
Get-NetFirewallProfile | Select-Object Name, Enabled
```

#### 3. 金鑰認證失敗

```powershell
# 使用詳細模式連線,查看錯誤訊息
ssh -vvv username@host

# 檢查授權金鑰檔案權限
icacls "$env:USERPROFILE\.ssh\authorized_keys"

# 檢查授權金鑰檔案內容
Get-Content "$env:USERPROFILE\.ssh\authorized_keys"

# 重新設定權限
$authKeysFile = "$env:USERPROFILE\.ssh\authorized_keys"
icacls.exe $authKeysFile /inheritance:r
icacls.exe $authKeysFile /grant "SYSTEM:(F)"
icacls.exe $authKeysFile /grant "${env:USERNAME}:(F)"

# 管理員帳號檢查
$adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
icacls.exe $adminAuthKeys
```

#### 4. 密碼認證失敗

```powershell
# 檢查使用者是否存在且已啟用
Get-LocalUser -Name username | Format-List Name, Enabled, PasswordExpires

# 檢查 sshd_config 設定
Get-Content "$env:ProgramData\ssh\sshd_config" | Select-String "PasswordAuthentication"

# 重設使用者密碼
$password = Read-Host "輸入新密碼" -AsSecureString
Set-LocalUser -Name username -Password $password
```

#### 5. 連線逾時

```powershell
# 檢查網路連通性
Test-Connection -ComputerName 192.168.1.100

# 測試特定端口
Test-NetConnection -ComputerName 192.168.1.100 -Port 22

# 檢查路由
tracert 192.168.1.100

# 使用 telnet 測試端口（需安裝 Telnet Client）
telnet 192.168.1.100 22
```

### 重置 SSH 設定

```powershell
# 1. 停止服務
Stop-Service sshd

# 2. 備份現有設定
$backupPath = "$env:ProgramData\ssh\sshd_config.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item "$env:ProgramData\ssh\sshd_config" $backupPath

# 3. 刪除設定檔
Remove-Item "$env:ProgramData\ssh\sshd_config" -Force

# 4. 重新安裝 OpenSSH Server
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 5. 啟動服務
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```

---

## 🧪 測試與驗證

### 完整測試流程

```powershell
# 1. 檢查安裝狀態
Write-Host "=== 1. 檢查 OpenSSH 安裝 ===" -ForegroundColor Cyan
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'

# 2. 檢查服務狀態
Write-Host "`n=== 2. 檢查服務狀態 ===" -ForegroundColor Cyan
Get-Service sshd, ssh-agent | Format-Table Name, Status, StartType

# 3. 檢查端口監聽
Write-Host "`n=== 3. 檢查端口監聽 ===" -ForegroundColor Cyan
Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, State

# 4. 檢查防火牆規則
Write-Host "`n=== 4. 檢查防火牆規則 ===" -ForegroundColor Cyan
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue |
    Format-Table DisplayName, Enabled, Direction, Action

# 5. 測試本機連線
Write-Host "`n=== 5. 測試本機連線 ===" -ForegroundColor Cyan
Test-NetConnection -ComputerName localhost -Port 22

# 6. 查看設定檔
Write-Host "`n=== 6. 檢查設定檔 ===" -ForegroundColor Cyan
if (Test-Path "$env:ProgramData\ssh\sshd_config") {
    Write-Host "設定檔存在" -ForegroundColor Green
} else {
    Write-Host "設定檔不存在" -ForegroundColor Red
}
```

---

## ⚠️ 安全性建議

### 基本安全措施

1. **使用強密碼**: 確保所有 SSH 使用者都使用強密碼
2. **金鑰認證**: 優先使用金鑰認證,停用密碼認證
3. **更改預設端口**: 將 SSH 端口從 22 改為其他端口
4. **限制使用者**: 使用 AllowUsers 限制可登入的使用者
5. **防火牆規則**: 限制 SSH 連線的來源 IP
6. **定期更新**: 保持 Windows 和 OpenSSH 更新到最新版本
7. **監控日誌**: 定期檢查 SSH 登入日誌

### 進階安全設定

編輯 `sshd_config`:

```bash
# 停用密碼認證（僅金鑰）
PasswordAuthentication no
PubkeyAuthentication yes

# 停用空密碼
PermitEmptyPasswords no

# 限制登入嘗試次數
MaxAuthTries 3

# 設定閒置逾時
ClientAliveInterval 300
ClientAliveCountMax 2

# 停用 root 登入（如適用）
# PermitRootLogin no

# 只允許特定使用者
AllowUsers user1 user2

# 啟用詳細日誌
LogLevel VERBOSE
```

### 定期安全檢查

```powershell
# 檢查失敗的登入嘗試
Get-EventLog -LogName Security -InstanceId 4625 -Newest 20 |
    Where-Object { $_.Message -like "*sshd*" } |
    Format-Table TimeGenerated, Message -Wrap

# 檢查成功的登入
Get-EventLog -LogName Security -InstanceId 4624 -Newest 20 |
    Where-Object { $_.Message -like "*sshd*" } |
    Format-Table TimeGenerated, Message -Wrap

# 列出所有授權金鑰
Get-Content "$env:USERPROFILE\.ssh\authorized_keys"
Get-Content "$env:ProgramData\ssh\administrators_authorized_keys"
```

---

## 📚 快速參考

### 安裝與服務管理

```powershell
# 安裝
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 啟動服務
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 防火牆
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any
```

### 連線與金鑰

```powershell
# 連線
ssh username@host

# 產生金鑰
ssh-keygen -t ed25519

# 查看公鑰
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

### 設定檔位置

```
Server 設定檔: C:\ProgramData\ssh\sshd_config
使用者金鑰: C:\Users\<username>\.ssh\authorized_keys
管理員金鑰: C:\ProgramData\ssh\administrators_authorized_keys
Client 設定: C:\Users\<username>\.ssh\config
```

---

## 📖 相關資源

### 官方文件
- [Microsoft - OpenSSH for Windows](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
- [OpenSSH Manual Pages](https://www.openssh.com/manual.html)
- [SSH Key Management](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)

### 相關工具
- PuTTY: Windows SSH Client 替代方案
- WinSCP: 圖形化 SFTP/SCP 工具
- MobaXterm: 整合終端機工具

---

## 📌 版本資訊

- **建立日期**: 2025-01-19
- **適用系統**: Windows 10 (1809+), Windows 11, Windows Server 2019+
- **OpenSSH 版本**: OpenSSH_for_Windows_8.1+

---

**祝設定順利！** 🚀
