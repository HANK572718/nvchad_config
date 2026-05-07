# Windows 防火牆設定指南

本文件說明如何使用 PowerShell 管理 Windows 防火牆規則。

---

## 📋 目錄

- [基本防火牆管理](#基本防火牆管理)
- [防火牆規則操作](#防火牆規則操作)
- [端口管理](#端口管理)
- [特定服務設定](#特定服務設定)
- [進階設定](#進階設定)
- [故障排除](#故障排除)

---

## 🔧 基本防火牆管理

### 查看防火牆狀態

```powershell
# 查看所有設定檔的防火牆狀態
Get-NetFirewallProfile | Select-Object Name, Enabled

# 查看特定設定檔狀態
Get-NetFirewallProfile -Name Domain,Public,Private | Format-Table Name, Enabled

# 詳細狀態資訊
Get-NetFirewallProfile | Format-List Name, Enabled, DefaultInboundAction, DefaultOutboundAction
```

### 啟用/停用防火牆

```powershell
# 啟用所有設定檔的防火牆
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# 停用所有設定檔的防火牆（不建議！）
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# 啟用特定設定檔
Set-NetFirewallProfile -Name Domain -Enabled True
Set-NetFirewallProfile -Name Public -Enabled True
Set-NetFirewallProfile -Name Private -Enabled True
```

### 設定預設動作

```powershell
# 設定輸入連線預設為封鎖
Set-NetFirewallProfile -DefaultInboundAction Block

# 設定輸出連線預設為允許
Set-NetFirewallProfile -DefaultOutboundAction Allow

# 針對特定設定檔
Set-NetFirewallProfile -Name Public -DefaultInboundAction Block -DefaultOutboundAction Allow
```

---

## 🛡️ 防火牆規則操作

### 查看防火牆規則

```powershell
# 查看所有規則
Get-NetFirewallRule

# 查看已啟用的規則
Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' } | Format-Table DisplayName, Direction, Action

# 查看特定名稱的規則
Get-NetFirewallRule -DisplayName "*SSH*"

# 查看輸入規則
Get-NetFirewallRule -Direction Inbound | Format-Table DisplayName, Enabled, Action

# 查看輸出規則
Get-NetFirewallRule -Direction Outbound | Format-Table DisplayName, Enabled, Action

# 查看特定端口的規則
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*22*" } | Format-Table
```

### 新增防火牆規則

```powershell
# 允許特定 TCP 端口（輸入）
New-NetFirewallRule -DisplayName "Allow Port 8080" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8080 `
    -Action Allow `
    -Profile Any

# 允許特定 UDP 端口（輸入）
New-NetFirewallRule -DisplayName "Allow UDP 123" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 123 `
    -Action Allow `
    -Profile Any

# 允許特定程式
New-NetFirewallRule -DisplayName "Allow Python App" `
    -Direction Inbound `
    -Program "C:\Python311\python.exe" `
    -Action Allow `
    -Profile Any

# 允許特定 IP 範圍
New-NetFirewallRule -DisplayName "Allow From Subnet" `
    -Direction Inbound `
    -RemoteAddress 192.168.1.0/24 `
    -Action Allow `
    -Profile Any

# 封鎖特定端口
New-NetFirewallRule -DisplayName "Block Port 445" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 445 `
    -Action Block `
    -Profile Any
```

### 修改現有規則

```powershell
# 啟用規則
Enable-NetFirewallRule -DisplayName "Allow Port 8080"

# 停用規則
Disable-NetFirewallRule -DisplayName "Allow Port 8080"

# 修改規則動作
Set-NetFirewallRule -DisplayName "Allow Port 8080" -Action Block

# 修改規則適用的設定檔
Set-NetFirewallRule -DisplayName "Allow Port 8080" -Profile Domain,Private
```

### 刪除防火牆規則

```powershell
# 刪除特定名稱的規則
Remove-NetFirewallRule -DisplayName "Allow Port 8080"

# 刪除多個規則（使用萬用字元）
Remove-NetFirewallRule -DisplayName "Test Rule*"

# 確認後刪除
$ruleName = "Allow Port 8080"
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    Remove-NetFirewallRule -DisplayName $ruleName
    Write-Host "已刪除規則: $ruleName" -ForegroundColor Green
}
```

---

## 🔌 端口管理

### 常用服務端口設定

```powershell
# HTTP (80)
New-NetFirewallRule -DisplayName "HTTP Server (Port 80)" `
    -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -Profile Any

# HTTPS (443)
New-NetFirewallRule -DisplayName "HTTPS Server (Port 443)" `
    -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -Profile Any

# SSH (22)
New-NetFirewallRule -DisplayName "SSH Server (Port 22)" `
    -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any

# RDP (3389)
New-NetFirewallRule -DisplayName "Remote Desktop" `
    -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Profile Private,Domain

# FTP (20, 21)
New-NetFirewallRule -DisplayName "FTP Data (Port 20)" `
    -Direction Inbound -Protocol TCP -LocalPort 20 -Action Allow -Profile Any

New-NetFirewallRule -DisplayName "FTP Control (Port 21)" `
    -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow -Profile Any

# MySQL (3306)
New-NetFirewallRule -DisplayName "MySQL Database" `
    -Direction Inbound -Protocol TCP -LocalPort 3306 -Action Allow -Profile Private

# PostgreSQL (5432)
New-NetFirewallRule -DisplayName "PostgreSQL Database" `
    -Direction Inbound -Protocol TCP -LocalPort 5432 -Action Allow -Profile Private
```

### 多端口設定

```powershell
# 允許多個連續端口
New-NetFirewallRule -DisplayName "Web Services" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8000-8100 `
    -Action Allow `
    -Profile Any

# 允許多個不連續端口（需分別建立）
@(8080, 8888, 9000) | ForEach-Object {
    New-NetFirewallRule -DisplayName "Allow Port $_" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $_ `
        -Action Allow `
        -Profile Any
}
```

---

## 🎯 特定服務設定

### NTP 時間同步服務 (UDP 123)

```powershell
# 允許 NTP Server 輸入
New-NetFirewallRule -DisplayName "NTP Server (UDP-In)" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 123 `
    -Action Allow `
    -Profile Any

# 允許 NTP Client 輸出
New-NetFirewallRule -DisplayName "NTP Client (UDP-Out)" `
    -Direction Outbound `
    -Protocol UDP `
    -RemotePort 123 `
    -Action Allow `
    -Profile Any
```

### OpenSSH Server (TCP 22)

```powershell
# OpenSSH Server 輸入規則
New-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -Program "%SystemRoot%\System32\OpenSSH\sshd.exe" `
    -Action Allow `
    -Profile Any

# 檢查現有 SSH 規則
Get-NetFirewallRule -DisplayName "*ssh*" | Format-Table DisplayName, Enabled, Direction, Action
```

### 檔案與印表機共用

```powershell
# 啟用檔案與印表機共用規則
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"

# 停用檔案與印表機共用規則
Disable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
```

### 遠端桌面 (RDP)

```powershell
# 允許遠端桌面連線
New-NetFirewallRule -DisplayName "Remote Desktop - User Mode (TCP-In)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 3389 `
    -Action Allow `
    -Profile Private,Domain

# 或啟用內建規則
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

### Ping (ICMP)

```powershell
# 允許 ICMPv4 Echo Request (Ping)
New-NetFirewallRule -DisplayName "Allow ICMPv4 Ping" `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -Action Allow `
    -Profile Any

# 允許 ICMPv6 Echo Request
New-NetFirewallRule -DisplayName "Allow ICMPv6 Ping" `
    -Direction Inbound `
    -Protocol ICMPv6 `
    -IcmpType 128 `
    -Action Allow `
    -Profile Any

# 或啟用內建規則
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
```

---

## 🔬 進階設定

### 依 IP 位址設定

```powershell
# 只允許特定 IP
New-NetFirewallRule -DisplayName "Allow SSH from Specific IP" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 22 `
    -RemoteAddress 192.168.1.100 `
    -Action Allow `
    -Profile Any

# 允許特定子網路
New-NetFirewallRule -DisplayName "Allow from Local Subnet" `
    -Direction Inbound `
    -RemoteAddress 192.168.1.0/24 `
    -Action Allow `
    -Profile Private

# 封鎖特定 IP
New-NetFirewallRule -DisplayName "Block Suspicious IP" `
    -Direction Inbound `
    -RemoteAddress 203.0.113.0 `
    -Action Block `
    -Profile Any

# 允許多個 IP
New-NetFirewallRule -DisplayName "Allow Multiple IPs" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8080 `
    -RemoteAddress 192.168.1.100,192.168.1.101,192.168.1.102 `
    -Action Allow `
    -Profile Any
```

### 依程式路徑設定

```powershell
# 允許特定程式的輸入連線
New-NetFirewallRule -DisplayName "Allow Python Server" `
    -Direction Inbound `
    -Program "C:\Python311\python.exe" `
    -Action Allow `
    -Profile Any

# 封鎖特定程式的輸出連線
New-NetFirewallRule -DisplayName "Block App Internet Access" `
    -Direction Outbound `
    -Program "C:\Apps\SomeApp.exe" `
    -Action Block `
    -Profile Any
```

### 依服務名稱設定

```powershell
# 允許特定 Windows 服務
New-NetFirewallRule -DisplayName "Allow W32Time Service" `
    -Direction Inbound `
    -Service W32Time `
    -Action Allow `
    -Profile Any
```

### 規則優先順序與群組

```powershell
# 建立具有群組的規則
New-NetFirewallRule -DisplayName "Web Server Rule 1" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Group "Web Services" `
    -Profile Any

# 停用整個群組
Disable-NetFirewallRule -Group "Web Services"

# 啟用整個群組
Enable-NetFirewallRule -Group "Web Services"

# 刪除整個群組的規則
Remove-NetFirewallRule -Group "Web Services"
```

---

## 🧹 批次管理

### 匯出與備份規則

```powershell
# 匯出所有防火牆規則
Export-FirewallRules

# 備份防火牆設定到檔案
netsh advfirewall export "C:\Backup\firewall_backup.wfw"

# 匯出特定規則到 CSV
Get-NetFirewallRule | Select-Object DisplayName, Direction, Action, Enabled |
    Export-Csv -Path "C:\Backup\firewall_rules.csv" -NoTypeInformation -Encoding UTF8
```

### 匯入與還原規則

```powershell
# 還原防火牆設定
netsh advfirewall import "C:\Backup\firewall_backup.wfw"

# 重置為預設設定
netsh advfirewall reset
```

### 批次建立規則

```powershell
# 批次允許多個端口
$ports = @(8080, 8888, 9000, 9090)
foreach ($port in $ports) {
    New-NetFirewallRule -DisplayName "Allow Port $port" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $port `
        -Action Allow `
        -Profile Any
    Write-Host "已建立規則: Allow Port $port" -ForegroundColor Green
}
```

### 清理規則

```powershell
# 刪除所有含特定關鍵字的規則
Get-NetFirewallRule -DisplayName "*Test*" | Remove-NetFirewallRule

# 刪除所有停用的規則
Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'False' } | Remove-NetFirewallRule

# 安全刪除（確認後刪除）
$rules = Get-NetFirewallRule -DisplayName "*Temp*"
if ($rules) {
    Write-Host "找到 $($rules.Count) 個符合的規則" -ForegroundColor Yellow
    $confirm = Read-Host "確定要刪除嗎？ (Y/N)"
    if ($confirm -eq 'Y') {
        $rules | Remove-NetFirewallRule
        Write-Host "已刪除規則" -ForegroundColor Green
    }
}
```

---

## 🔍 監控與診斷

### 查看防火牆記錄

```powershell
# 啟用防火牆記錄
Set-NetFirewallProfile -Name Public -LogFileName "%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log" `
    -LogMaxSizeKilobytes 4096 `
    -LogAllowed True `
    -LogBlocked True

# 查看記錄檔案
Get-Content "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log" -Tail 50
```

### 測試連線

```powershell
# 測試特定端口是否開啟
Test-NetConnection -ComputerName 192.168.1.100 -Port 22

# 詳細測試
Test-NetConnection -ComputerName 192.168.1.100 -Port 8080 -InformationLevel Detailed

# 測試本機端口
Test-NetConnection -ComputerName localhost -Port 22
```

### 查看目前連線

```powershell
# 查看所有 TCP 連線
Get-NetTCPConnection | Where-Object { $_.State -eq "Established" } |
    Format-Table LocalAddress, LocalPort, RemoteAddress, RemotePort, State

# 查看監聽的端口
Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } |
    Select-Object LocalAddress, LocalPort | Sort-Object LocalPort
```

---

## 🛠️ 故障排除

### 檢查規則衝突

```powershell
# 查看所有啟用的規則
Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' } |
    Format-Table DisplayName, Direction, Action, Profile

# 查看特定端口的所有規則
Get-NetFirewallRule | Get-NetFirewallPortFilter |
    Where-Object { $_.LocalPort -eq 22 } |
    Select-Object -Property * | Format-List
```

### 測試防火牆規則

```powershell
# 臨時停用防火牆進行測試（不建議用於生產環境）
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# 測試完成後立即啟用
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
```

### 常見問題診斷

```powershell
# 1. 檢查防火牆服務是否運作
Get-Service -Name mpssvc | Select-Object Name, Status, StartType

# 2. 檢查特定規則是否存在
Get-NetFirewallRule -DisplayName "Allow SSH" -ErrorAction SilentlyContinue

# 3. 查看規則詳細資訊
Get-NetFirewallRule -DisplayName "Allow SSH" |
    Get-NetFirewallPortFilter |
    Format-List

# 4. 檢查端口是否被佔用
Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue
```

---

## ⚠️ 注意事項

### 安全性建議

1. **最小權限原則**: 只開放必要的端口
2. **限制 IP 範圍**: 盡可能限制來源 IP 位址
3. **定期檢查**: 定期審查防火牆規則
4. **避免停用**: 不要完全停用防火牆
5. **記錄監控**: 啟用防火牆記錄功能

### 操作注意事項

1. ⚠️ **需要管理員權限**: 所有防火牆操作都需要管理員權限
2. ⚠️ **測試環境優先**: 在生產環境前先在測試環境驗證
3. ⚠️ **備份規則**: 修改前先備份現有規則
4. ⚠️ **避免衝突**: 注意規則間的優先順序和衝突
5. ⚠️ **網路中斷風險**: 錯誤的設定可能導致網路連線中斷

### 設定檔說明

Windows 防火牆有三個設定檔:
- **Domain**: 電腦連接到網域時使用
- **Private**: 電腦連接到私人網路時使用
- **Public**: 電腦連接到公共網路時使用

建議針對不同設定檔設定不同的規則,提高安全性。

---

## 📚 快速參考

### 常用命令速查

```powershell
# 查看狀態
Get-NetFirewallProfile | Select-Object Name, Enabled
Get-NetFirewallRule | Format-Table DisplayName, Enabled, Direction, Action

# 新增規則
New-NetFirewallRule -DisplayName "名稱" -Direction Inbound -Protocol TCP -LocalPort 端口 -Action Allow

# 修改規則
Set-NetFirewallRule -DisplayName "名稱" -Action Block
Enable-NetFirewallRule -DisplayName "名稱"
Disable-NetFirewallRule -DisplayName "名稱"

# 刪除規則
Remove-NetFirewallRule -DisplayName "名稱"

# 測試連線
Test-NetConnection -ComputerName IP位址 -Port 端口
```

---

## 📖 相關資源

### 官方文件
- [Microsoft - Windows Defender Firewall](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-firewall/)
- [NetSecurity Module](https://docs.microsoft.com/en-us/powershell/module/netsecurity/)
- [Advanced Firewall Configuration](https://docs.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-contexts)

### 相關工具
- `netsh advfirewall` - 傳統命令列工具
- Windows Defender Firewall with Advanced Security - 圖形化介面
- PowerShell NetSecurity Module - PowerShell 模組

---

## 📌 版本資訊

- **建立日期**: 2025-01-19
- **適用系統**: Windows 10/11, Windows Server 2016+
- **PowerShell 版本**: 5.1+

---

**祝設定順利！** 🔒
