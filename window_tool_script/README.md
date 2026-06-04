# Tool Script 工具腳本使用指南

本目錄包含各種實用的 PowerShell 腳本工具，用於系統管理和維護。

---

## 📁 目錄結構

```
tool_script/
├── re_password.ps1          # Windows 帳號管理工具
└── time_sync/               # 時間同步工具集
    ├── setup_time_server.ps1
    ├── setup_time_client.ps1
    ├── configure_sync_interval.ps1
    ├── verify_time_sync.ps1
    └── reset_time_service.ps1
```

---

## 🔧 1. Windows 帳號管理工具 (re_password.ps1)

### 功能說明
互動式 Windows 本機帳號管理工具，提供建立、修改、查看、刪除帳號等功能。

### 重要語法

#### 啟動腳本
```powershell
# 以管理員身份執行 PowerShell，然後執行：
.\re_password.ps1
```

### 內建功能命令參考

雖然此腳本是互動式的，但以下是腳本內部使用的關鍵 PowerShell 命令，可直接在 PowerShell 中使用：

#### 檢查管理員權限
```powershell
# 檢查當前是否為管理員
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

#### 新增本機帳號
```powershell
# 建立新帳號（密碼永不過期）
$password = Read-Host "Enter password" -AsSecureString
New-LocalUser -Name "username" -Password $password -FullName "Full Name" -Description "Description" -PasswordNeverExpires
Set-LocalUser -Name "username" -PasswordNeverExpires $true
```

#### 修改帳號密碼
```powershell
# 更新帳號密碼
$password = Read-Host "Enter new password" -AsSecureString
Set-LocalUser -Name "username" -Password $password -PasswordNeverExpires $true
```

#### 查看帳號資訊
```powershell
# 列出所有本機帳號
Get-LocalUser | Select-Object Name, Enabled | Format-Table

# 查看特定帳號詳細資訊
Get-LocalUser -Name "username" | Format-List

# 查看帳號完整資訊
Get-LocalUser -Name "username" | Select-Object Name, Enabled, PasswordExpires, PasswordNeverExpires, LastLogon | Format-List
```

#### 遠端桌面權限管理
```powershell
# 加入遠端桌面使用者群組
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "username"

# 查看遠端桌面使用者群組成員
Get-LocalGroupMember -Group "Remote Desktop Users"

# 檢查特定帳號是否在遠端桌面群組中
Get-LocalGroupMember -Group "Remote Desktop Users" | Where-Object {$_.Name -like "*username*"}
```

#### 刪除帳號
```powershell
# 刪除本機帳號（不可逆！）
Remove-LocalUser -Name "username"
```

#### 查看帳號群組成員資格
```powershell
# 查看帳號所屬的所有群組
Get-LocalGroup | Where-Object {
    (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\username"
}
```

#### 帳號統計資訊
```powershell
# 統計帳號數量
$allUsers = Get-LocalUser
$enabledCount = ($allUsers | Where-Object {$_.Enabled -eq $true}).Count
$disabledCount = ($allUsers | Where-Object {$_.Enabled -eq $false}).Count
$neverExpireCount = ($allUsers | Where-Object {$_.PasswordNeverExpires -eq $true}).Count
$neverLoginCount = ($allUsers | Where-Object {$_.LastLogon -eq $null}).Count

Write-Host "總帳號數: $($allUsers.Count)"
Write-Host "已啟用: $enabledCount"
Write-Host "已停用: $disabledCount"
Write-Host "密碼永不過期: $neverExpireCount"
Write-Host "從未登入: $neverLoginCount"
```

### 注意事項
- ⚠️ **必須以系統管理員身分執行**
- ⚠️ 刪除帳號操作無法復原
- ⚠️ 無法刪除當前登入的使用者
- ⚠️ 不建議刪除系統帳號（Administrator, Guest 等）

---

## ⏰ 2. 時間同步工具集 (time_sync/)

### 2.1 設定時間伺服器 (setup_time_server.ps1)

#### 功能說明
將 Windows 電腦設定為 NTP 時間伺服器，提供時間同步服務給其他電腦。

#### 重要語法

```powershell
# 基本執行
.\setup_time_server.ps1

# 指定日誌檔案路徑
.\setup_time_server.ps1 -LogPath "D:\logs\time_server.log"
```

#### 關鍵設定命令
```powershell
# 啟用 NTP Server
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" -Name "Enabled" -Value 1

# 設定允許客戶端查詢
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "AnnounceFlags" -Value 5

# 設定外部時間來源
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "NtpServer" -Value "time.windows.com,0x9 time.google.com,0x9"

# 開啟防火牆 UDP 123 埠
New-NetFirewallRule -DisplayName "NTP Server (UDP-In)" -Direction Inbound -Protocol UDP -LocalPort 123 -Action Allow -Profile Any
```

---

### 2.1.1 獨立時間源伺服器 (setup_win10_ntp_server.ps1)

#### 功能說明
將 Windows 10 設定為**獨立的 NTP 時間源**，不依賴外部時間同步，使用本地時鐘作為時間基準。

#### 重要語法

```powershell
# 基本執行
.\setup_win10_ntp_server.ps1

# 執行並手動設定系統時間
.\setup_win10_ntp_server.ps1 -ManualTime "2025-01-18 18:30:00"
```

#### 參數說明
- `ManualTime`（選用）：手動設定系統時間

#### 關鍵設定命令
```powershell
# 設定為可靠時間源（Stratum 1）
w32tm /config /reliable:YES /update

# 設定為本地時鐘（不依賴外部）
w32tm /config /manualpeerlist:"" /syncfromflags:NO /update

# 啟用 NTP Server
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" -Name "Enabled" -Value 1

# 開啟防火牆 UDP 123 埠
New-NetFirewallRule -DisplayName "NTP Server - Inbound" -Direction Inbound -Protocol UDP -LocalPort 123 -Action Allow -Profile Any
```

#### 適用場景
- ✅ **離線/隔離網路環境**：無法連接互聯網的網路
- ✅ **實驗室環境**：需要獨立時間基準進行測試
- ✅ **受控環境**：時間由管理員手動控制
- ✅ **快速部署**：不需要複雜的日誌和外部依賴

---

### 📊 時間伺服器腳本差異對比

#### setup_win10_ntp_server.ps1 vs setup_time_server.ps1

| 特性 | setup_win10_ntp_server.ps1 | setup_time_server.ps1 |
|------|---------------------------|----------------------|
| **定位** | 獨立時間源（本地時鐘） | 網路時間服務器 |
| **外部時間源** | ❌ 不依賴外部時間 | ✅ 同步 time.windows.com / time.google.com |
| **手動設定時間** | ✅ 支持（可選參數 -ManualTime） | ❌ 不支持 |
| **日誌功能** | ❌ 無日誌系統 | ✅ 完整日誌記錄到檔案 |
| **可靠時間源** | ✅ 設定為可靠源 (reliable:YES) | ❌ 未設定 |
| **Stratum 層級** | 1（頂層時間源） | 2-3（中繼時間服務器） |
| **SyncFromFlags** | NO（不同步外部） | MANUAL（手動同步外部） |
| **ManualPeerList** | "" (空，不使用外部) | time.windows.com, time.google.com |
| **UpdateInterval** | 使用系統預設 | 明確設定為 60 秒 |
| **MaxPhaseCorrection** | 使用系統預設 | 設定為 ±3600 秒（1 小時） |
| **管理員權限檢查** | ❌ 無 | ✅ 有 Test-Administrator 函數 |
| **適用場景** | 離線環境、實驗室 | 線上環境、生產環境 |

#### 核心技術差異

**setup_win10_ntp_server.ps1（獨立時間源）：**
```powershell
# 設定為可靠時間源
w32tm /config /reliable:YES /update

# 不依賴外部時間（本地時鐘）
w32tm /config /manualpeerlist:"" /syncfromflags:NO /update

# 可選：手動設定時間
Set-Date -Date $ManualTime
```

**setup_time_server.ps1（網路時間服務器）：**
```powershell
# 依賴外部時間源
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "NtpServer" -Value "time.windows.com,0x9 time.google.com,0x9"

# 強制與外部時間源同步
w32tm /resync /force

# 完整日誌記錄
Write-Log "message" -Level Info
```

#### 如何選擇？

**使用 setup_win10_ntp_server.ps1，如果你：**
- 🔒 在**隔離網路**或**無法連接互聯網**的環境
- 🧪 需要**獨立的時間基準**進行測試或實驗
- ⚡ 希望**快速部署**，不需要複雜功能
- 🎯 需要**手動控制時間**（可指定精確時間）
- 📍 作為整個網路的**根時間源**（Stratum 1）

**使用 setup_time_server.ps1，如果你：**
- 🌐 能夠**連接互聯網**，需要與標準時間同步
- 🏢 在**生產環境**中，需要詳細的日誌記錄
- 🔄 作為**中繼時間服務器**（從互聯網同步後提供給內網）
- 📊 需要**追蹤操作歷史**和問題診斷
- ✅ 需要**權限檢查**和錯誤處理機制

#### 使用範例對比

**獨立時間源場景（setup_win10_ntp_server.ps1）：**
```powershell
# 場景：工廠隔離網路，手動設定標準時間
.\setup_win10_ntp_server.ps1 -ManualTime "2025-01-18 09:00:00"

# 結果：
# - Stratum 1（頂層時間源）
# - 不依賴外部時間
# - 其他電腦以此為準
```

**網路時間服務器場景（setup_time_server.ps1）：**
```powershell
# 場景：公司內網時間服務器，與互聯網時間同步
.\setup_time_server.ps1 -LogPath "D:\logs\time_server.log"

# 結果：
# - Stratum 2-3（從互聯網同步）
# - 定期與 time.windows.com 同步
# - 提供時間給內網電腦
# - 記錄所有操作到日誌
```

---

### 2.2 設定時間客戶端

#### ⭐ 2.2.1 簡化版設定 (setup_ntp_client_simple.ps1) - **推薦使用**

##### 功能說明
**一步到位**的 NTP 客戶端設定工具，自動完成所有必要配置：
- 連接到指定的時間伺服器
- 自動設定 64 秒高頻率同步（MinPollInterval/MaxPollInterval）
- 無需再執行 configure_sync_interval.ps1

##### 重要語法

```powershell
# 執行腳本後輸入伺服器 IP（最簡單）
.\setup_ntp_client_simple.ps1

# 直接指定伺服器 IP
.\setup_ntp_client_simple.ps1 -ServerIP "192.168.168.199"

# 自訂同步間隔（預設 64 秒）
.\setup_ntp_client_simple.ps1 -ServerIP "192.168.168.199" -SyncInterval 128
```

##### 參數說明
- `ServerIP`（選用）：時間伺服器的 IP 位址，未提供時會提示輸入
- `SyncInterval`（選用）：同步間隔（秒），預設 64 秒，範圍 64-3600

##### 優點
✅ 一個腳本完成所有設定，無需額外步驟
✅ 自動設定正確的輪詢間隔（MinPollInterval/MaxPollInterval）
✅ 互動式輸入，使用更友善
✅ 包含連通性測試和錯誤處理

---

#### 2.2.2 完整版設定 (setup_time_client.ps1)

##### 功能說明
將 Windows 電腦設定為 NTP 客戶端，連接到指定的時間伺服器進行同步。

⚠️ **注意**: 使用此腳本後，需要額外執行 `configure_sync_interval.ps1` 才能實現真正的高頻率同步。建議使用 `setup_ntp_client_simple.ps1` 代替。

##### 重要語法

```powershell
# 基本執行（必須指定伺服器 IP）
.\setup_time_client.ps1 -ServerIP "192.168.1.100"

# 自訂同步間隔（秒）
.\setup_time_client.ps1 -ServerIP "192.168.1.100" -SyncInterval 30

# 指定日誌檔案
.\setup_time_client.ps1 -ServerIP "192.168.1.100" -SyncInterval 60 -LogPath "D:\logs\time_client.log"
```

##### 參數說明
- `ServerIP`（必要）：時間伺服器的 IP 位址
- `SyncInterval`（選用）：同步間隔（秒），預設 60 秒，範圍 1-3600
- `LogPath`（選用）：日誌檔案路徑

##### 關鍵設定命令
```powershell
# 設定時間伺服器
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "NtpServer" -Value "192.168.1.100,0x9"

# 啟用 NTP Client
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" -Name "Enabled" -Value 1

# 設定同步間隔
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" -Name "SpecialPollInterval" -Value 60

# 測試連通性
Test-Connection -ComputerName "192.168.1.100" -Count 2

# 強制同步
w32tm /resync /force
```

---

### 2.3 修正同步間隔設定 (configure_sync_interval.ps1)

#### 功能說明
修正 W32Time 的輪詢間隔設定，確保實現真正的高頻率同步（解決預設 1024 秒問題）。

#### 重要語法

```powershell
# Server 端修正
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64

# Client 端修正
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.1.100" -SyncInterval 64

# 自訂間隔（128 秒）
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.1.100" -SyncInterval 128
```

#### 參數說明
- `Role`（必要）：Server 或 Client
- `ServerIP`（Client 必要）：時間伺服器 IP
- `SyncInterval`（選用）：同步間隔（秒），預設 64 秒，範圍 64-3600

#### 關鍵設定命令
```powershell
# 計算輪詢間隔冪次（W32Time 使用 2^n）
$pollPower = [Math]::Floor([Math]::Log(64, 2))  # 64秒 = 2^6

# 設定 MinPollInterval 和 MaxPollInterval
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "MinPollInterval" -Value 6
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "MaxPollInterval" -Value 6
```

#### 輪詢間隔對照表
| 冪次 (n) | 間隔 (2^n 秒) | 說明 |
|---------|-------------|------|
| 6 | 64 秒 | 最小值，高精度同步 |
| 7 | 128 秒 | 約 2 分鐘 |
| 8 | 256 秒 | 約 4 分鐘 |
| 9 | 512 秒 | 約 8.5 分鐘 |
| 10 | 1024 秒 | 約 17 分鐘（Windows 預設） |

---

### 2.4 驗證時間同步狀態 (verify_time_sync.ps1)

#### 功能說明
檢查 Windows Time Service 的運作狀態，產生詳細的診斷報告。

#### 重要語法

```powershell
# 基本驗證
.\verify_time_sync.ps1

# 顯示詳細資訊
.\verify_time_sync.ps1 -ShowDetails

# 持續監控模式（每 5 秒更新）
.\verify_time_sync.ps1 -ContinuousMode

# 持續監控（每 10 秒更新）
.\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 10

# 指定日誌檔案
.\verify_time_sync.ps1 -LogPath "D:\logs\verify.log"
```

#### 參數說明
- `ShowDetails`：顯示詳細診斷資訊
- `ContinuousMode`：持續監控模式
- `RefreshInterval`：更新間隔（秒），預設 5 秒
- `LogPath`：日誌檔案路徑

#### 關鍵診斷命令
```powershell
# 查看服務狀態
Get-Service W32Time

# 查看時間同步狀態
w32tm /query /status

# 查看詳細狀態
w32tm /query /status /verbose

# 查看設定
w32tm /query /configuration

# 查看對等點
w32tm /query /peers

# 查看時間來源
w32tm /query /source

# 測試與伺服器的時間差
w32tm /stripchart /computer:192.168.1.100 /samples:5
```

---

### 2.5 重置時間服務 (reset_time_service.ps1)

#### 功能說明
將 Windows Time Service 還原為預設設定，移除所有自訂配置。

#### 重要語法

```powershell
# 重置為基本設定（無外部時間伺服器）
.\reset_time_service.ps1

# 重置並使用 Windows 預設時間伺服器
.\reset_time_service.ps1 -RestoreToDefault

# 指定日誌檔案
.\reset_time_service.ps1 -RestoreToDefault -LogPath "D:\logs\reset.log"
```

#### 參數說明
- `RestoreToDefault`：還原為 Windows 預設時間伺服器（time.windows.com）
- `LogPath`：日誌檔案路徑

#### 關鍵重置命令
```powershell
# 停止服務
Stop-Service W32Time -Force

# 取消註冊服務
w32tm /unregister

# 重新註冊服務（還原預設設定）
w32tm /register

# 啟動服務
Start-Service W32Time

# 更新設定
w32tm /config /update

# 移除防火牆規則
Remove-NetFirewallRule -DisplayName "NTP Server (UDP-In)"
```

---

## 🧪 測試時間同步功能

### 手動更改系統時間（測試用）

在測試時間同步功能時，需要先手動更改系統時間，然後觀察是否能正確同步回來。

#### 查看當前時間
```powershell
# 顯示當前系統時間
Get-Date

# 顯示詳細時間資訊
Get-Date -Format "yyyy-MM-dd HH:mm:ss"
```

#### 更改系統時間
```powershell
# 方法 1: 設定完整日期和時間
Set-Date -Date "2025-01-18 10:30:00"

# 方法 2: 只設定日期（保持當前時間）
Set-Date -Date "2025-01-18"

# 方法 3: 只設定時間（保持當前日期）
$newTime = Get-Date -Hour 10 -Minute 30 -Second 0
Set-Date -Date $newTime

# 方法 4: 將時間往前調整（例如：往前 5 分鐘）
Set-Date -Date (Get-Date).AddMinutes(-5)

# 方法 5: 將時間往後調整（例如：往後 10 分鐘）
Set-Date -Date (Get-Date).AddMinutes(10)
```

#### 完整測試流程範例

**測試 Client 端時間同步：**

```powershell
# 1. 記錄當前時間
Get-Date
# 輸出範例：2025年1月18日 星期六 下午 6:00:00

# 2. 將時間往前調 5 分鐘
Set-Date -Date (Get-Date).AddMinutes(-5)

# 3. 確認時間已更改
Get-Date
# 輸出範例：2025年1月18日 星期六 下午 5:55:00

# 4. 強制同步
w32tm /resync /force

# 5. 等待幾秒後查看時間
Start-Sleep -Seconds 5
Get-Date

# 6. 查看同步狀態
w32tm /query /status
```

#### 常用測試場景

**場景 1：測試小幅度時間偏移（1-5 分鐘）**
```powershell
# 往前調 3 分鐘
Set-Date -Date (Get-Date).AddMinutes(-3)
w32tm /resync /force
Start-Sleep -Seconds 3
Get-Date
```

**場景 2：測試中等幅度時間偏移（10-30 分鐘）**
```powershell
# 往前調 15 分鐘
Set-Date -Date (Get-Date).AddMinutes(-15)
w32tm /resync /force
Start-Sleep -Seconds 5
Get-Date
```

**場景 3：測試大幅度時間偏移（1-2 小時）**
```powershell
# 往前調 1 小時
Set-Date -Date (Get-Date).AddHours(-1)
w32tm /resync /force
Start-Sleep -Seconds 5
Get-Date
```

**場景 4：測試跨日期同步**
```powershell
# 往前調 1 天
Set-Date -Date (Get-Date).AddDays(-1)
w32tm /resync /force
Start-Sleep -Seconds 5
Get-Date
```

#### 測試注意事項

⚠️ **重要提醒：**
1. **僅在測試環境使用**：不要在生產環境隨意更改系統時間
2. **需要管理員權限**：Set-Date 命令需要管理員權限
3. **影響系統運作**：更改時間可能影響排程任務、日誌記錄等
4. **建議測試範圍**：時間偏移建議在 ±1 小時內測試
5. **超過 15 小時**：W32Time 預設不會同步超過 15 小時的偏移（需調整 MaxPosPhaseCorrection 和 MaxNegPhaseCorrection）

#### 查看時間同步效果

```powershell
# 使用 verify 腳本持續監控
.\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 5

# 或直接查看同步狀態
w32tm /query /status

# 查看時間偏移
w32tm /stripchart /computer:192.168.168.199 /samples:5
```

#### 還原為網路時間

如果測試後時間不準確，可以手動同步：

```powershell
# 方法 1: 強制與設定的伺服器同步
w32tm /resync /force

# 方法 2: 使用 Windows 預設時間伺服器
.\reset_time_service.ps1 -RestoreToDefault
w32tm /resync /force

# 方法 3: 線上查詢正確時間後手動設定
# 先到 https://time.is/ 查看準確時間，然後：
Set-Date -Date "2025-01-18 18:30:45"
```

---

## 🔍 常用 W32Time 命令速查

### 服務管理
```powershell
# 啟動服務
Start-Service W32Time

# 停止服務
Stop-Service W32Time

# 重新啟動服務
Restart-Service W32Time

# 設定自動啟動
Set-Service W32Time -StartupType Automatic

# 檢查服務狀態
Get-Service W32Time | Select-Object Name, Status, StartType
```

### 時間同步操作
```powershell
# 強制同步
w32tm /resync /force

# 重新設定並更新
w32tm /config /update

# 查看同步統計
w32tm /query /status /verbose | Select-String "Offset|Delay|Dispersion"
```

### 設定檢視
```powershell
# 查看時間伺服器設定
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" | Select-Object NtpServer, Type

# 查看輪詢間隔設定
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" | Select-Object MinPollInterval, MaxPollInterval

# 查看 NTP Client 設定
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient"
```

### 網路測試
```powershell
# 測試連通性
Test-Connection -ComputerName "192.168.1.100" -Count 4

# 測試 NTP 埠（需要 PowerShell 5.0+）
Test-NetConnection -ComputerName "192.168.1.100" -Port 123

# 查看本機 IP
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" }
```

---

## 📝 使用流程範例

### 完整時間同步設定流程

#### Server 端（192.168.168.199）
```powershell
# 1. 以管理員身分執行 PowerShell
# 2. 設定為時間伺服器
.\setup_time_server.ps1

# 3. 修正輪詢間隔
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64

# 4. 驗證設定
.\verify_time_sync.ps1 -ShowDetails
```

#### Client 端方案一：簡化版（推薦）⭐

```powershell
# 1. 以管理員身分執行 PowerShell
# 2. 執行簡化版腳本（一步完成所有設定）
.\setup_ntp_client_simple.ps1 -ServerIP "192.168.168.199"

# 或者執行後再輸入 IP（互動式）
.\setup_ntp_client_simple.ps1

# 3. 驗證同步狀態
.\verify_time_sync.ps1

# 4. 持續監控（可選）
.\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 10
```

#### Client 端方案二：完整版（需要兩步驟）

```powershell
# 1. 以管理員身分執行 PowerShell
# 2. 設定為時間客戶端
.\setup_time_client.ps1 -ServerIP "192.168.168.199"

# 3. 修正輪詢間隔（必須執行此步驟才能實現真正的高頻率同步）
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.168.199" -SyncInterval 64

# 4. 驗證同步狀態
.\verify_time_sync.ps1

# 5. 持續監控（可選）
.\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 10
```

---

## ⚠️ 注意事項

### 共通注意事項
1. **所有腳本都需要以系統管理員權限執行**
2. 建議在執行前先閱讀腳本內容，了解會執行的操作
3. 日誌檔案會記錄所有操作，建議定期檢查

### 時間同步注意事項
1. Server 和 Client 必須在同一網段或能互相 Ping 通
2. Server 端需要開放 UDP 123 埠（腳本會自動處理）
3. 同步間隔最小為 64 秒（W32Time 限制）
4. 根散佈（Root Dispersion）正常值應 < 3 秒
5. 如需重置設定，使用 `reset_time_service.ps1`

### 帳號管理注意事項
1. 刪除帳號操作無法復原
2. 無法刪除當前登入的使用者
3. 不建議刪除系統內建帳號
4. 建議定期檢查帳號狀態和權限

---

## 🐛 故障排除

### 時間同步問題

#### 問題：根散佈過高（> 10 秒）
```powershell
# Server 端強制同步
w32tm /resync /force

# 修正輪詢間隔
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64    # Server
.\configure_sync_interval.ps1 -Role Client -ServerIP "IP" -SyncInterval 64  # Client
```

#### 問題：無法連接到伺服器
```powershell
# 測試網路連通性
Test-Connection -ComputerName "192.168.1.100"

# 檢查防火牆規則
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*NTP*" }
```

#### 問題：同步失敗
```powershell
# 強制重新同步
w32tm /resync /force

# 檢查詳細狀態
w32tm /query /status /verbose
```

### 帳號管理問題

#### 問題：無法執行腳本
```powershell
# 檢查執行原則
Get-ExecutionPolicy

# 允許執行腳本（需管理員）
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

#### 問題：權限不足
```powershell
# 檢查是否為管理員
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 如果返回 False，需要以管理員身分重新開啟 PowerShell
```

---

## 📚 相關資源

### 官方文件
- [Microsoft - Windows Time Service](https://docs.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-top)
- [W32Time 設定參考](https://docs.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)
- [PowerShell 使用者管理](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/)

### 時間同步詳細文件
- `time_sync/README.md` - 時間同步工具總覽
- `time_sync/QUICKSTART.md` - 快速開始指南
- `time_sync/TROUBLESHOOTING.md` - 故障排除指南
- `time_sync/windows_time_sync_guide.md` - 完整操作手冊

---

## 📌 版本資訊

- **建立日期**：2025-01-18
- **最後更新**：2025-01-18
- **維護者**：Claude Code

---

## 💡 使用提示

1. **第一次使用**：建議從 QUICKSTART.md 開始
2. **遇到問題**：參考 TROUBLESHOOTING.md
3. **進階設定**：查閱完整的操作手冊
4. **自訂需求**：可以修改腳本參數或直接使用本文件中的命令

**祝使用順利！** 🎉
