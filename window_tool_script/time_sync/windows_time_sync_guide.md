# Windows 時間同步解決方案

## 概述

此解決方案提供一套完整的 PowerShell 腳本，讓兩台（或多台）Windows 電腦透過乙太網路進行高精度時間同步。使用 Windows 內建的 Windows Time Service (W32Time)，透過 NTP 協議實現時間同步。

### 主要特性

- ✅ **彈性角色分配**：提供 Server/Client 兩套腳本，可自由選擇哪台電腦作為時間伺服器
- ✅ **高頻率同步**：支援最快 64 秒同步一次（W32Time 最小值），可自訂同步間隔
- ✅ **自動化設定**：一鍵執行腳本完成所有配置，包括防火牆規則
- ✅ **詳細日誌**：所有操作都會記錄到日誌檔案，方便追蹤問題
- ✅ **狀態驗證**：提供完整的驗證工具，即時監控同步狀態
- ✅ **簡單重置**：可快速還原為 Windows 預設設定
- ✅ **故障排除**：完整的問題診斷與修正工具

### 檔案說明

| 檔案名稱 | 用途 | 執行對象 |
|---------|------|---------|
| `setup_time_server.ps1` | 將電腦設定為時間伺服器 | Server 端 |
| `setup_time_client.ps1` | 將電腦設定為時間客戶端 | Client 端 |
| `configure_sync_interval.ps1` | **修正輪詢間隔設定（重要！）** | 兩端皆可 |
| `verify_time_sync.ps1` | 驗證時間同步狀態 | 兩端皆可 |
| `reset_time_service.ps1` | 重置為預設設定 | 兩端皆可 |
| `QUICKSTART.md` | 快速開始指南 | 文件 |
| `TROUBLESHOOTING.md` | 故障排除指南 | 文件 |

---

## 快速開始

### 前置需求

1. **硬體需求**
   - 兩台 Windows 電腦（Windows 10/11 或 Windows Server）
   - 乙太網路連接（實體網路線或虛擬網路）

2. **權限需求**
   - 系統管理員權限（所有腳本都需要）

3. **網路需求**
   - 兩台電腦必須能互相 Ping 通
   - Server 端需要開放 UDP 123 埠（腳本會自動處理）

### 基本設定流程

#### 步驟 1：決定角色分配

選擇其中一台電腦作為**時間伺服器（Server）**，另一台作為**時間客戶端（Client）**。

> **建議**：選擇較穩定、較少關機的電腦作為 Server

#### 步驟 2：在 Server 端執行設定

1. 以**系統管理員身分**開啟 PowerShell
2. 切換到 `time_sync` 資料夾
3. 執行：

```powershell
.\setup_time_server.ps1
```

4. 記下顯示的 **Server IP 位址**（例如：192.168.1.100）

#### 步驟 3：在 Client 端執行設定

1. 以**系統管理員身分**開啟 PowerShell
2. 切換到 `time_sync` 資料夾
3. 執行（將 IP 改為您的 Server IP）：

```powershell
.\setup_time_client.ps1 -ServerIP "192.168.1.100"
```

#### 步驟 4：修正輪詢間隔（重要！）

> **為什麼需要這步驟？**
> 原始的 setup 腳本缺少 `MinPollInterval` 和 `MaxPollInterval` 設定，導致實際輪詢間隔是 1024 秒（17 分鐘）而非預期的 64 秒。

**在 Server 端執行：**

```powershell
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64
```

**在 Client 端執行：**

```powershell
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.1.100" -SyncInterval 64
```

#### 步驟 5：驗證同步狀態

在 Client 端執行：

```powershell
.\verify_time_sync.ps1
```

檢查以下項目：
- ✅ 輪詢間隔：6 (64s)
- ✅ 根散佈：< 3 秒
- ✅ 已成功同步

如果輪詢間隔仍是 10 (1024s) 或根散佈很高，請參閱 `TROUBLESHOOTING.md`。

---

## 詳細操作指南

### Server 端設定

#### 基本設定

```powershell
# 使用預設設定
.\setup_time_server.ps1
```

#### 自訂日誌路徑

```powershell
# 指定日誌檔案位置
.\setup_time_server.ps1 -LogPath "D:\logs\time_server.log"
```

#### Server 端會執行的操作

1. ✅ 停止現有的 W32Time 服務
2. ✅ 設定為 NTP Server 模式
3. ✅ 啟用 NTP Server 功能
4. ✅ 設定允許客戶端查詢
5. ✅ 設定高精度同步參數
6. ✅ 設定外部時間來源（time.windows.com, time.google.com）
7. ✅ 開啟防火牆規則（UDP 123）
8. ✅ 啟動服務並強制同步

#### 查看 Server IP

執行腳本後會顯示所有網路介面的 IP 位址，建議使用**乙太網路介面**的 IP。

如需再次查看 IP：

```powershell
# 查看所有 IP
ipconfig

# 或僅查看 IPv4
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" }
```

---

### Client 端設定

#### 基本設定（必要參數）

```powershell
# 連接到指定的時間伺服器
.\setup_time_client.ps1 -ServerIP "192.168.1.100"
```

#### 自訂同步間隔

```powershell
# 設定每 30 秒同步一次
.\setup_time_client.ps1 -ServerIP "192.168.1.100" -SyncInterval 30

# 設定每 5 分鐘（300 秒）同步一次
.\setup_time_client.ps1 -ServerIP "192.168.1.100" -SyncInterval 300
```

#### 自訂日誌路徑

```powershell
.\setup_time_client.ps1 -ServerIP "192.168.1.100" -LogPath "D:\logs\time_client.log"
```

#### Client 端會執行的操作

1. ✅ 測試與 Server 的連通性（Ping）
2. ✅ 停止現有的 W32Time 服務
3. ✅ 設定為 NTP Client 模式
4. ✅ 設定時間伺服器位址
5. ✅ 停用 NTP Server 功能
6. ✅ 設定同步間隔（預設 60 秒）
7. ✅ 設定時間校正參數
8. ✅ 啟動服務並強制同步

#### 連通性測試

腳本會自動測試與 Server 的連通性：
- **Ping 成功**：繼續執行設定
- **Ping 失敗**：顯示警告，詢問是否繼續

手動測試連通性：

```powershell
# 測試 Ping
Test-Connection -ComputerName "192.168.1.100" -Count 4

# 測試 NTP 埠（需要安裝 Test-NetConnection）
Test-NetConnection -ComputerName "192.168.1.100" -Port 123
```

---

### 驗證同步狀態

#### 基本驗證

```powershell
.\verify_time_sync.ps1
```

顯示內容：
- ✅ W32Time 服務狀態
- ✅ 時間來源設定
- ✅ 與伺服器的連通性
- ✅ 最後同步時間
- ✅ 時間階層（Stratum）

#### 顯示詳細資訊

```powershell
.\verify_time_sync.ps1 -ShowDetails
```

額外顯示：
- 完整的 `w32tm /query /status` 輸出
- 完整的 `w32tm /query /configuration` 輸出
- 所有已知的時間對等點（peers）

#### 持續監控模式

```powershell
# 每 5 秒更新一次（預設）
.\verify_time_sync.ps1 -ContinuousMode

# 每 10 秒更新一次
.\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 10
```

按 `Ctrl+C` 停止監控。

---

### 重置設定

#### 重置為基本預設設定

```powershell
.\reset_time_service.ps1
```

此操作會：
- ✅ 取消註冊並重新註冊 W32Time 服務
- ✅ 清除所有自訂設定
- ✅ 移除防火牆規則
- ⚠️ **不會**設定任何時間伺服器

#### 重置並使用 Windows 預設時間伺服器

```powershell
.\reset_time_service.ps1 -RestoreToDefault
```

此操作會：
- ✅ 重置所有設定
- ✅ 設定為使用 `time.windows.com`
- ✅ 設定同步間隔為 3600 秒（1 小時）

---

## 網路設定指南

### IP 位址設定

#### 自動 (DHCP)

如果兩台電腦都連接到同一個路由器，通常會自動取得 IP 位址。

**優點**：設定簡單
**缺點**：IP 可能會變動（需要重新設定 Client）

**建議**：在路由器設定 DHCP 保留（IP 綁定），讓 Server 的 IP 固定

#### 手動（固定 IP）

如果兩台電腦直接用網路線連接，需要手動設定 IP。

##### 設定步驟

**Server 端：**
1. 開啟「控制台」→「網路和共用中心」→「變更介面卡設定」
2. 右鍵點選乙太網路介面 → 內容
3. 選擇「網際網路通訊協定第 4 版 (TCP/IPv4)」→ 內容
4. 選擇「使用下列的 IP 位址」：
   - IP 位址：`192.168.100.1`
   - 子網路遮罩：`255.255.255.0`
   - 預設閘道：留空

**Client 端：**
1. 同上步驟 1-3
2. 設定：
   - IP 位址：`192.168.100.2`
   - 子網路遮罩：`255.255.255.0`
   - 預設閘道：留空

##### PowerShell 設定方式

```powershell
# Server 端
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.100.1" -PrefixLength 24

# Client 端
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress "192.168.100.2" -PrefixLength 24
```

> **注意**：`Ethernet` 是介面名稱，可能是「乙太網路」、「Ethernet」、「Ethernet 2」等，請使用 `Get-NetAdapter` 確認。

### 防火牆設定

#### 自動設定（推薦）

執行 `setup_time_server.ps1` 時會自動建立防火牆規則。

#### 手動設定

如果自動設定失敗，可手動開啟：

##### 使用 PowerShell

```powershell
New-NetFirewallRule -DisplayName "NTP Server (UDP-In)" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 123 `
    -Action Allow `
    -Profile Any
```

##### 使用 Windows 防火牆圖形介面

1. 開啟「控制台」→「系統及安全性」→「Windows Defender 防火牆」
2. 點選「進階設定」
3. 點選「輸入規則」→「新增規則」
4. 選擇「連接埠」→ 下一步
5. 選擇「UDP」，特定本機連接埠：`123` → 下一步
6. 選擇「允許連線」→ 下一步
7. 全選（網域、私人、公用）→ 下一步
8. 名稱：`NTP Server` → 完成

#### 檢查防火牆規則

```powershell
# 查看 NTP 相關規則
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*NTP*" }

# 查看 UDP 123 規則
Get-NetFirewallPortFilter | Where-Object { $_.LocalPort -eq 123 }
```

---

## 故障排除

### 問題 1：「無法 Ping 到伺服器」

**可能原因**：
1. 網路線未連接
2. IP 位址設定錯誤
3. 防火牆阻擋 ICMP（Ping）

**解決方式**：

```powershell
# 1. 檢查網路介面狀態
Get-NetAdapter

# 2. 檢查 IP 設定
ipconfig /all

# 3. 測試連通性
Test-Connection -ComputerName "192.168.1.100" -Count 4

# 4. 暫時停用防火牆測試（測試完記得啟用）
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
# 測試完後啟用
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
```

---

### 問題 2：「服務狀態異常」或「無法啟動服務」

**解決方式**：

```powershell
# 1. 檢查服務狀態
Get-Service W32Time

# 2. 停止並重新啟動
Stop-Service W32Time -Force
Start-Service W32Time

# 3. 如果還是失敗，重新註冊服務
w32tm /unregister
w32tm /register
Start-Service W32Time

# 4. 檢查服務依賴
Get-Service W32Time | Select-Object -ExpandProperty DependentServices
Get-Service W32Time | Select-Object -ExpandProperty RequiredServices
```

---

### 問題 3：「同步失敗」或「未指定時間來源」

**可能原因**：
1. Server 端未正確設定
2. 網路連線問題
3. 防火牆阻擋 UDP 123

**解決方式**：

```powershell
# 1. 檢查時間來源設定
w32tm /query /source

# 2. 檢查對等點狀態
w32tm /query /peers

# 3. 手動強制同步
w32tm /resync /force

# 4. 重新設定並更新
w32tm /config /update
w32tm /resync /force

# 5. 檢查詳細狀態
w32tm /query /status /verbose
```

---

### 問題 4：「時間偏移過大」

如果兩台電腦的時間差距超過 15 小時，W32Time 可能拒絕同步。

**解決方式**：

```powershell
# 1. 先手動調整時間到接近的時間
# 開啟「設定」→「時間與語言」→ 手動調整

# 2. 或使用命令
# 設定日期（格式：MM-DD-YYYY）
Set-Date -Date "01-15-2025"

# 設定時間（格式：HH:MM:SS）
Set-Date -Date "14:30:00"

# 3. 調整後再次同步
w32tm /resync /force
```

---

### 問題 5：「需要系統管理員權限」

**確認 PowerShell 是否以系統管理員執行**：

```powershell
# 檢查是否為管理員
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

# 如果回傳 False，請關閉 PowerShell，並「以系統管理員身分執行」
```

**快速以管理員身分開啟 PowerShell**：
1. 按 `Win + X`
2. 選擇「Windows PowerShell (系統管理員)」或「終端機 (系統管理員)」

---

### 問題 6：「執行原則限制無法執行腳本」

錯誤訊息：`無法載入檔案 xxx.ps1，因為這個系統上已停用指令碼執行`

**解決方式**：

```powershell
# 檢查目前執行原則
Get-ExecutionPolicy

# 暫時允許執行（僅本次工作階段）
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 或永久允許（需管理員權限）
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## 進階設定

### 調整同步精度

#### 修改同步間隔

**Client 端**（推薦在執行腳本時設定）：

```powershell
# 每 30 秒同步一次
.\setup_time_client.ps1 -ServerIP "192.168.1.100" -SyncInterval 30
```

**手動修改**：

```powershell
# 修改 Client 端的同步間隔為 30 秒
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
    -Name "SpecialPollInterval" -Value 30

# 更新設定
w32tm /config /update
Restart-Service W32Time
```

#### 查看目前設定

```powershell
# 查看完整設定
w32tm /query /configuration

# 僅查看同步間隔
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
    -Name "SpecialPollInterval"
```

---

### 多台 Client 連接同一個 Server

Server 端**不需要**額外設定，可以同時服務多台 Client。

只需在每台 Client 上執行：

```powershell
.\setup_time_client.ps1 -ServerIP "192.168.1.100"
```

---

### 設定開機自動同步

W32Time 服務預設為「自動啟動」，因此電腦重開機後會自動同步。

如需確認：

```powershell
# 檢查啟動類型
Get-Service W32Time | Select-Object Name, Status, StartType

# 設定為自動啟動
Set-Service W32Time -StartupType Automatic
```

---

### 使用排程工作定期強制同步

雖然 W32Time 會自動同步，但您也可以建立排程工作定期強制同步。

```powershell
# 建立每小時強制同步的排程工作
$Action = New-ScheduledTaskAction -Execute "w32tm" -Argument "/resync /force"
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "Force Time Sync" -Action $Action -Trigger $Trigger -Principal $Principal
```

**移除排程工作**：

```powershell
Unregister-ScheduledTask -TaskName "Force Time Sync" -Confirm:$false
```

---

## 命令參考

### W32Time 常用命令

```powershell
# 查看服務狀態
w32tm /query /status

# 查看詳細狀態
w32tm /query /status /verbose

# 查看設定
w32tm /query /configuration

# 查看時間來源
w32tm /query /source

# 查看對等點
w32tm /query /peers

# 強制同步
w32tm /resync /force

# 更新設定
w32tm /config /update

# 重新註冊服務
w32tm /unregister
w32tm /register

# 測試與特定伺服器的連線
w32tm /stripchart /computer:192.168.1.100 /samples:5

# 查看同步統計
w32tm /query /status /verbose | Select-String "Offset|Delay|Dispersion"
```

---

### PowerShell 服務管理

```powershell
# 查看服務狀態
Get-Service W32Time

# 啟動服務
Start-Service W32Time

# 停止服務
Stop-Service W32Time

# 重新啟動服務
Restart-Service W32Time

# 設定啟動類型
Set-Service W32Time -StartupType Automatic

# 查看服務詳細資訊
Get-Service W32Time | Format-List *
```

---

### 登錄檔設定位置

所有 W32Time 設定都儲存在登錄檔中：

```
HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\
├── Config\               # 一般設定
├── Parameters\           # 主要參數（NtpServer, Type 等）
└── TimeProviders\
    ├── NtpClient\        # Client 設定
    └── NtpServer\        # Server 設定
```

**查看登錄檔**：

```powershell
# 查看主要參數
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"

# 查看 NTP Server 設定
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer"

# 查看 NTP Client 設定
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient"
```

---

## 常見問題 (FAQ)

### Q1: 為什麼需要系統管理員權限？

A: W32Time 是系統服務，修改服務設定、登錄檔、防火牆規則都需要管理員權限。

---

### Q2: 可以同時連接多個時間伺服器嗎？

A: 可以。在 Client 端設定時，可以指定多個伺服器（以空格分隔）：

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "NtpServer" -Value "192.168.1.100,0x9 192.168.1.101,0x9"
```

W32Time 會自動選擇最佳的伺服器。

---

### Q3: Server 端也需要連接外部時間伺服器嗎？

A: 建議要。`setup_time_server.ps1` 會自動設定 Server 連接 `time.windows.com` 和 `time.google.com`，確保 Server 本身的時間也是準確的。

如果 Server 沒有網際網路連線，可以手動移除：

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "NtpServer" -Value ""
```

---

### Q4: 如何確認時間已經同步？

A: 使用 `verify_time_sync.ps1` 或手動檢查：

```powershell
# 查看最後同步時間
w32tm /query /status | Select-String "Last Successful Sync Time|上次成功同步時間"

# 如果顯示具體時間（不是 "unspecified"），表示已同步
```

---

### Q5: 同步間隔最小可以設定多少？

A: 理論上可以設定為 1 秒，但**不建議**設定太小：

- **推薦值**：60 秒（預設）
- **最小值**：15 秒（更小可能導致系統負擔過大）

設定太小的同步間隔可能會：
- 增加網路流量
- 增加 CPU 負擔
- 導致時間抖動（jitter）

---

### Q6: 兩台電腦的時間差距很大，無法同步怎麼辦？

A: W32Time 有預設的最大時間偏移限制（MaxPosPhaseCorrection / MaxNegPhaseCorrection），腳本已設定為 3600 秒（1 小時）。

如果超過 1 小時，請手動調整其中一台的時間到接近的時間，然後再執行同步。

---

### Q7: 如何停用時間同步？

A: 執行重置腳本：

```powershell
.\reset_time_service.ps1
```

或手動停用服務：

```powershell
Stop-Service W32Time
Set-Service W32Time -StartupType Disabled
```

---

### Q8: 日誌檔案會一直增長嗎？

A: 是的，日誌檔案會持續寫入。建議定期清理或使用日誌輪替（log rotation）。

**手動清理**：

```powershell
# 刪除日誌檔案
Remove-Item time_sync_*.log

# 或清空內容
Clear-Content time_sync_*.log
```

**自動輪替**（進階）：可以撰寫排程工作定期備份並清空日誌。

---

### Q9: 可以在虛擬機上使用嗎？

A: 可以，但需要注意：

1. **Hyper-V / VMware**：預設可能啟用「時間同步」功能，會與主機同步時間，可能與 W32Time 衝突
   - **解決**：在虛擬機設定中停用「時間同步」
2. **VirtualBox**：同上，停用 Guest Additions 的時間同步功能

---

### Q10: 如何查看兩台電腦的時間差距？

A: 使用 `w32tm /stripchart` 命令：

```powershell
# 在 Client 端執行，查看與 Server 的時間差
w32tm /stripchart /computer:192.168.1.100 /samples:5
```

輸出範例：
```
Tracking 192.168.1.100 [192.168.1.100:123].
Collecting 5 samples.
The current time is 2025-01-15 14:30:00.
14:30:00, +00.0012345s
14:30:02, +00.0012389s
...
```

`+00.0012345s` 表示 Client 比 Server 快 0.0012345 秒。

---

## 附錄

### 腳本參數完整說明

#### setup_time_server.ps1

| 參數 | 類型 | 必要 | 預設值 | 說明 |
|-----|------|------|--------|------|
| LogPath | String | 否 | time_sync_server.log | 日誌檔案路徑 |

#### setup_time_client.ps1

| 參數 | 類型 | 必要 | 預設值 | 說明 |
|-----|------|------|--------|------|
| ServerIP | String | **是** | - | 時間伺服器的 IP 位址 |
| SyncInterval | Int | 否 | 60 | 同步間隔（秒），範圍 1-3600 |
| LogPath | String | 否 | time_sync_client.log | 日誌檔案路徑 |

#### verify_time_sync.ps1

| 參數 | 類型 | 必要 | 預設值 | 說明 |
|-----|------|------|--------|------|
| ShowDetails | Switch | 否 | False | 顯示詳細診斷資訊 |
| LogPath | String | 否 | time_sync_verify.log | 日誌檔案路徑 |
| ContinuousMode | Switch | 否 | False | 持續監控模式 |
| RefreshInterval | Int | 否 | 5 | 持續監控的更新間隔（秒） |

#### reset_time_service.ps1

| 參數 | 類型 | 必要 | 預設值 | 說明 |
|-----|------|------|--------|------|
| RestoreToDefault | Switch | 否 | False | 還原為 Windows 預設時間伺服器 |
| LogPath | String | 否 | time_sync_reset.log | 日誌檔案路徑 |

---

### 相關資源

- [Microsoft 官方文件 - Windows Time Service](https://docs.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-top)
- [W32Time 設定參考](https://docs.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)
- [NTP 協議說明 (RFC 5905)](https://tools.ietf.org/html/rfc5905)

---

### 版本歷史

| 版本 | 日期 | 變更說明 |
|------|------|---------|
| 1.0.0 | 2025-01-15 | 初始版本發布 |
| 1.1.0 | 2025-11-11 | 新增 configure_sync_interval.ps1 修正輪詢間隔問題<br>新增 TROUBLESHOOTING.md 故障排除指南<br>新增 QUICKSTART.md 快速開始指南<br>修正根散佈過高的問題<br>更新所有文件說明 |

---

### 授權與支援

此解決方案由 Claude Code 協助建立，提供給使用者自由使用與修改。

如有問題或建議：
- 參閱 **`TROUBLESHOOTING.md`** 查看常見問題解決方案
- 參閱 **`QUICKSTART.md`** 快速開始指南
- 查看日誌檔案進行診斷

---

**文件結束**
