# Windows 時間同步工具

自動化 PowerShell 腳本，讓兩台（或多台）Windows 電腦透過區域網路進行高精度時間同步。

## 快速開始

### 1. Server 端（選擇一台電腦作為時間伺服器）

以**系統管理員身分**開啟 PowerShell，執行：

```powershell
.\setup_time_server.ps1
```

記下顯示的 **IP 位址**（例如：192.168.1.100）

### 2. Client 端（其他電腦）

以**系統管理員身分**開啟 PowerShell，執行：

```powershell
.\setup_time_client.ps1 -ServerIP "192.168.1.100"
```

（將 IP 改為您的 Server IP）

### 3. 驗證

```powershell
.\verify_time_sync.ps1
```

看到「✓ 已成功同步」即表示設定成功！

---

## 檔案說明

| 檔案 | 用途 |
|------|------|
| `setup_time_server.ps1` | 設定為時間伺服器（Server 端執行） |
| `setup_time_client.ps1` | 設定為時間客戶端（Client 端執行） |
| `configure_sync_interval.ps1` | **修正輪詢間隔設定（重要！）** |
| `verify_time_sync.ps1` | 驗證時間同步狀態 |
| `reset_time_service.ps1` | 重置為預設設定 |
| `windows_time_sync_guide.md` | 完整操作指南 |
| `TROUBLESHOOTING.md` | **故障排除指南（遇到問題必讀）** |
| `QUICKSTART.md` | 快速開始指南 |

---

## 主要特性

- ✅ 高頻率同步（最快 64 秒，W32Time 限制）
- ✅ 自動設定防火牆規則
- ✅ 詳細日誌記錄
- ✅ 網路連通性測試
- ✅ 一鍵重置功能
- ✅ 完整的故障排除工具

---

## 常用命令

### 🔧 修正輪詢間隔（重要！）

如果發現輪詢間隔是 1024 秒而非 64 秒，請執行：

```powershell
# Server 端
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64

# Client 端
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.1.100" -SyncInterval 64
```

### 持續監控狀態

```powershell
.\verify_time_sync.ps1 -ContinuousMode
```

### 顯示詳細資訊

```powershell
.\verify_time_sync.ps1 -ShowDetails
```

### 重置為 Windows 預設

```powershell
.\reset_time_service.ps1 -RestoreToDefault
```

---

## 注意事項

1. **必須以系統管理員權限執行**
2. 兩台電腦必須能互相 Ping 通
3. Server 端需要開放 UDP 123 埠（腳本會自動處理）
4. 如需詳細說明，請參閱 `windows_time_sync_guide.md`

---

## 故障排除

### ⚠️ 根散佈（Root Dispersion）過高

如果看到根散佈 > 10 秒：

```powershell
# 1. Server 端強制同步
w32tm /resync /force

# 2. 修正輪詢間隔
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64   # Server 端
.\configure_sync_interval.ps1 -Role Client -ServerIP "IP" -SyncInterval 64  # Client 端
```

詳細說明請參閱 `TROUBLESHOOTING.md`

### 無法連接到伺服器

```powershell
# 測試網路連通性
Test-Connection -ComputerName "192.168.1.100"

# 檢查防火牆規則
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*NTP*" }
```

### 同步失敗

```powershell
# 強制重新同步
w32tm /resync /force

# 檢查詳細狀態
w32tm /query /status /verbose
```

### 無法執行腳本

```powershell
# 允許執行腳本（需管理員權限）
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## 完整文件

| 文件 | 內容 |
|------|------|
| **`QUICKSTART.md`** | 新手快速開始指南 |
| **`TROUBLESHOOTING.md`** | 常見問題與解決方案（根散佈過高等） |
| **`windows_time_sync_guide.md`** | 完整操作指南、進階設定、命令參考 |

---

## 版本

- **版本**：1.1.0
- **日期**：2025-11-11
- **作者**：Claude Code
- **更新**：新增 configure_sync_interval.ps1，修正輪詢間隔設定問題

---

**祝您使用順利！**
