# 時間同步問題排除指南

## 問題 1：根散佈（Root Dispersion）過高

### 症狀

執行 `w32tm /query /status` 顯示：
```
根散佈: 16.8873203s    # 非常高（正常應 < 1s）
```

### 原因分析

1. **Server 端長時間未同步**
   - 上次同步時間過久（超過 1-2 小時）
   - Server 本身的根散佈就很高

2. **輪詢間隔設定未生效**
   - 顯示的輪詢間隔是 1024 秒，而不是設定的 60 秒
   - W32Time 使用 `MinPollInterval` 和 `MaxPollInterval` 控制實際間隔
   - 原腳本缺少這些關鍵設定

3. **根散佈累積**
   - Client 會繼承 Server 的根散佈
   - 再加上網路延遲和本地時鐘漂移
   - 導致根散佈持續累積

### 立即解決方案

#### 步驟 1：強制 Server 端重新同步

在 **Server 端**（192.168.168.199）執行：

```powershell
# 強制與外部時間源同步
w32tm /resync /force

# 等待 5 秒
Start-Sleep -Seconds 5

# 檢查狀態
w32tm /query /status
```

應該會看到：
- 「上次成功同步時間」更新為剛才的時間
- 根散佈降低到 1-2 秒左右

#### 步驟 2：修正輪詢間隔設定

在 **Server 端**執行：

```powershell
cd D:\docs\AD_ITRI_questcomposite\time_sync
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64
```

在 **Client 端**（您的電腦）執行：

```powershell
cd D:\project\intel_ARC_support\ITRI_questcomposite\time_sync
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.168.199" -SyncInterval 64
```

> **注意**：同步間隔最小為 64 秒（2^6），這是 W32Time 的限制

#### 步驟 3：驗證修正結果

等待 2-3 分鐘後，在 Client 端執行：

```powershell
.\verify_time_sync.ps1 -ShowDetails
```

預期結果：
- 輪詢間隔：64 秒（或更小）
- 根散佈：< 2 秒（理想情況 < 1 秒）

---

## 問題 2：輪詢間隔不正確

### 症狀

```
輪詢間隔: 10 (1024s)    # 實際是 17 分鐘，而不是 60 秒
```

### 根本原因

W32Time 的輪詢間隔由以下參數控制：

| 參數 | 位置 | 說明 |
|-----|------|------|
| `MinPollInterval` | Config | 最小輪詢間隔（2^n 秒） |
| `MaxPollInterval` | Config | 最大輪詢間隔（2^n 秒） |
| `SpecialPollInterval` | NtpClient | 特殊輪詢間隔（秒） |

原腳本只設定了 `SpecialPollInterval`，但沒有設定 `MinPollInterval` 和 `MaxPollInterval`。

### 解決方案

使用 `configure_sync_interval.ps1` 修正（見上方步驟 2）。

或手動設定：

```powershell
# 停止服務
Stop-Service W32Time -Force

# 設定為 64 秒 (2^6 = 64)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "MinPollInterval" -Value 6

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "MaxPollInterval" -Value 6

# 啟動服務
Start-Service W32Time

# 更新設定
w32tm /config /update

# 強制同步
w32tm /resync /force
```

### 輪詢間隔對照表

| 冪次 (n) | 間隔 (2^n 秒) | 說明 |
|---------|-------------|------|
| 6 | 64 秒 | 最小值，適合高精度同步 |
| 7 | 128 秒 | 約 2 分鐘 |
| 8 | 256 秒 | 約 4 分鐘 |
| 9 | 512 秒 | 約 8.5 分鐘 |
| 10 | 1024 秒 | 約 17 分鐘（Windows 預設） |
| 12 | 4096 秒 | 約 1.1 小時 |
| 15 | 32768 秒 | 約 9 小時 |

---

## 問題 3：Server 端長時間未同步

### 症狀

```
上次成功同步處理時間: 2025/11/11 下午 12:09:56
# 現在是 14:37，已經 2.5 小時沒同步
```

### 原因

1. Server 端的輪詢間隔太長（1024 秒 = 17 分鐘）
2. 外部時間源（time.google.com）可能不穩定或網路問題
3. 長時間未同步導致根散佈持續增加

### 解決方案

#### 1. 立即強制同步

```powershell
w32tm /resync /force
```

#### 2. 檢查外部時間源連通性

```powershell
# 測試 time.google.com
Test-Connection time.google.com -Count 4

# 測試 NTP 連接
w32tm /stripchart /computer:time.google.com /samples:5
```

#### 3. 如果無法連接外部時間源

考慮更換時間源：

```powershell
# 停止服務
Stop-Service W32Time

# 更換為台灣 NTP 伺服器
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "NtpServer" -Value "tock.stdtime.gov.tw,0x9 watch.stdtime.gov.tw,0x9"

# 啟動服務
Start-Service W32Time
w32tm /config /update
w32tm /resync /force
```

**推薦的 NTP 伺服器**：

| 伺服器 | 位置 | 說明 |
|-------|------|------|
| tock.stdtime.gov.tw | 台灣 | 國家時間與頻率標準實驗室 |
| time.google.com | Google | Google 公用 NTP |
| time.windows.com | Microsoft | Windows 預設 |
| time.cloudflare.com | Cloudflare | Cloudflare NTP |

---

## 問題 4：根散佈居高不下

如果執行修正腳本後，根散佈仍然很高（> 2 秒），請依序檢查：

### 1. 確認 Server 端狀態正常

在 Server 端執行：

```powershell
w32tm /query /status
```

確認：
- ✅ 上次同步時間在最近幾分鐘內
- ✅ 根散佈 < 1 秒
- ✅ 組織層 = 2 或 3
- ✅ 來源是外部 NTP 伺服器

### 2. 確認網路延遲正常

在 Client 端測試：

```powershell
# 測試延遲
Test-Connection 192.168.168.199 -Count 10

# 查看統計
w32tm /stripchart /computer:192.168.168.199 /samples:10
```

預期：
- 延遲 < 10ms（區域網路）
- 時間偏移穩定（不劇烈波動）

### 3. 檢查時鐘品質

在兩端執行：

```powershell
w32tm /query /configuration | Select-String "ClockRate|Frequency"
```

### 4. 重新設定（最後手段）

如果以上都沒問題，執行完整重置：

**Server 端：**
```powershell
.\reset_time_service.ps1
.\setup_time_server.ps1
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64
```

**Client 端：**
```powershell
.\reset_time_service.ps1
.\setup_time_client.ps1 -ServerIP "192.168.168.199"
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.168.199" -SyncInterval 64
```

---

## 診斷命令速查

### 查看當前狀態

```powershell
# 基本狀態
w32tm /query /status

# 詳細狀態
w32tm /query /status /verbose

# 設定資訊
w32tm /query /configuration

# 對等點資訊
w32tm /query /peers
```

### 查看登錄檔設定

```powershell
# 查看輪詢間隔
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" |
    Select-Object MinPollInterval, MaxPollInterval

# 查看時間伺服器
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" |
    Select-Object NtpServer, Type

# 查看 NTP Client 設定
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient"
```

### 手動操作

```powershell
# 強制同步
w32tm /resync /force

# 重新註冊服務
w32tm /unregister
w32tm /register

# 更新設定
w32tm /config /update

# 測試與伺服器連線
w32tm /stripchart /computer:192.168.168.199 /samples:5
```

---

## 正常狀態參考值

### Server 端

```
躍進式指示器: 0(沒有警告)
組織層: 2
精確度: -23 (119.209ns 每個滴答)
根延遲: 0.01-0.05s          ← 正常
根散佈: 0.5-2s               ← 正常
上次成功同步處理時間: 最近幾分鐘內  ← 重要
輪詢間隔: 6 (64s)            ← 修正後
```

### Client 端

```
躍進式指示器: 0(沒有警告)
組織層: 3
精確度: -23 (119.209ns 每個滴答)
根延遲: 0.02-0.06s          ← 正常（略高於 Server）
根散佈: 1-3s                 ← 正常（略高於 Server）
參照識別碼: Server IP
上次成功同步處理時間: 最近幾分鐘內  ← 重要
輪詢間隔: 6 (64s)            ← 修正後
```

---

## 常見誤解

### ❌ 誤解 1：同步間隔可以設為 1 秒

**事實**：W32Time 的最小輪詢間隔是 2^6 = 64 秒，無法更小。

### ❌ 誤解 2：根散佈 0 才是正常

**事實**：根散佈代表時間不確定性，永遠不會是 0。區域網路同步通常在 1-3 秒是正常的。

### ❌ 誤解 3：立即就會看到改善

**事實**：修正設定後，需要等待幾次同步週期（5-10 分鐘）才會看到根散佈明顯降低。

### ❌ 誤解 4：Client 應該直接連外部 NTP

**事實**：在區域網路環境中，Client 連接本地 Server 可以：
- 減少外部網路依賴
- 降低延遲
- 提高同步精度
- 減輕外部 NTP 伺服器負載

---

## 進階：為什麼根散佈會累積？

### 時間同步的層級結構

```
Stratum 0: 原子鐘、GPS 時鐘（硬體）
    ↓
Stratum 1: 直接連接 Stratum 0 的伺服器
    ↓
Stratum 2: time.google.com（您的 Server 的來源）
    ↓ Root Dispersion ≈ 8s
Stratum 3: 您的 Server (192.168.168.199)
    ↓ Root Dispersion 累積
Stratum 4: 您的 Client
    Root Dispersion = Server 的散佈 + 網路延遲 + 時間漂移
```

### 根散佈計算公式（簡化）

```
Client 根散佈 = Server 根散佈 +
                (當前時間 - 上次同步時間) × 時鐘漂移率 +
                網路往返延遲 / 2
```

**這就是為什麼**：
1. Server 長時間不同步 → Server 根散佈增加
2. Client 繼承 Server 的散佈
3. Client 自己也有時鐘漂移
4. 最終 Client 根散佈 = 16 秒

---

## 聯絡資訊

如果問題持續，請提供以下資訊：

**Server 端：**
```powershell
w32tm /query /status > server_status.txt
w32tm /query /configuration > server_config.txt
w32tm /query /peers > server_peers.txt
```

**Client 端：**
```powershell
w32tm /query /status > client_status.txt
w32tm /query /configuration > client_config.txt
w32tm /stripchart /computer:192.168.168.199 /samples:10 > client_test.txt
```

---

**文件結束**
