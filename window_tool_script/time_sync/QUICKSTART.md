# Windows 時間同步快速開始指南

## 🚀 3 步驟完成設定

### 前置需求
- ✅ 兩台 Windows 電腦
- ✅ 已用乙太網路連接
- ✅ 系統管理員權限

---

## 步驟 1：設定 Server 端

在選定的時間伺服器上，以**系統管理員身分**開啟 PowerShell：

```powershell
cd D:\docs\AD_ITRI_questcomposite\time_sync

# 執行設定
.\setup_time_server.ps1

# 修正輪詢間隔（重要！）
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64
```

**記下顯示的 IP 位址**，例如：`192.168.168.199`

---

## 步驟 2：設定 Client 端

在另一台電腦上，以**系統管理員身分**開啟 PowerShell：

```powershell
cd D:\project\intel_ARC_support\ITRI_questcomposite\time_sync

# 執行設定（將 IP 改為您的 Server IP）
.\setup_time_client.ps1 -ServerIP "192.168.168.199"

# 修正輪詢間隔（重要！）
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.168.199" -SyncInterval 64
```

---

## 步驟 3：驗證

在 Client 端執行：

```powershell
.\verify_time_sync.ps1
```

### ✅ 成功的標誌

```
✓ 服務狀態: Running
✓ 時間來源: 192.168.168.199
✓ 已成功同步
  輪詢間隔: 6 (64s)            ← 正確
  根散佈: 1-3s                  ← 正常
```

### ❌ 需要修正

如果看到：
```
輪詢間隔: 10 (1024s)          ← 錯誤
根散佈: > 10s                  ← 過高
```

請執行步驟 1 和 2 中的 `configure_sync_interval.ps1`

---

## 常見問題快速解答

### Q: 為什麼需要執行 configure_sync_interval.ps1？

**A:** Windows Time Service 的輪詢間隔由 `MinPollInterval` 和 `MaxPollInterval` 控制。原始的 `setup_time_*.ps1` 腳本缺少這些設定，導致實際輪詢間隔是 1024 秒（17 分鐘）而非 64 秒。

### Q: 為什麼是 64 秒而不是 60 秒？

**A:** W32Time 的輪詢間隔必須是 2 的冪次（2^n 秒），64 秒 (2^6) 是最小值。

### Q: 根散佈是什麼？多少才正常？

**A:** 根散佈（Root Dispersion）代表時間的不確定性：
- **< 1 秒**：優秀
- **1-3 秒**：正常（區域網路）
- **> 10 秒**：需要修正

### Q: Server 端長時間沒有同步怎麼辦？

**A:** 在 Server 端執行強制同步：

```powershell
w32tm /resync /force
```

然後再執行 `configure_sync_interval.ps1`。

### Q: 無法 Ping 到伺服器

**A:** 檢查：
1. 網路線是否連接
2. IP 位址是否正確
3. 防火牆是否阻擋

```powershell
# 測試連通性
Test-Connection 192.168.168.199

# 查看本機 IP
ipconfig
```

---

## 完整命令流程（複製貼上版）

### Server 端

```powershell
# 進入目錄
cd D:\docs\AD_ITRI_questcomposite\time_sync

# 設定 Server
.\setup_time_server.ps1

# 修正輪詢間隔
.\configure_sync_interval.ps1 -Role Server -SyncInterval 64

# 驗證
w32tm /query /status
```

### Client 端（替換 IP）

```powershell
# 進入目錄
cd D:\project\intel_ARC_support\ITRI_questcomposite\time_sync

# 設定 Client（改為您的 Server IP）
.\setup_time_client.ps1 -ServerIP "192.168.168.199"

# 修正輪詢間隔（改為您的 Server IP）
.\configure_sync_interval.ps1 -Role Client -ServerIP "192.168.168.199" -SyncInterval 64

# 驗證
.\verify_time_sync.ps1
```

---

## 持續監控

想要即時查看同步狀態：

```powershell
.\verify_time_sync.ps1 -ContinuousMode -RefreshInterval 10
```

按 `Ctrl+C` 停止。

---

## 進階操作

### 調整同步間隔

```powershell
# 128 秒同步一次 (2^7)
.\configure_sync_interval.ps1 -Role Client -ServerIP "IP" -SyncInterval 128

# 256 秒同步一次 (2^8)
.\configure_sync_interval.ps1 -Role Client -ServerIP "IP" -SyncInterval 256
```

**可用值**：64, 128, 256, 512, 1024, 2048...（2 的冪次）

### 重置為預設

```powershell
# 重置並使用 Windows 預設時間伺服器
.\reset_time_service.ps1 -RestoreToDefault
```

---

## 需要幫助？

- 🔧 **常見問題**：參閱 `TROUBLESHOOTING.md`
- 📖 **完整手冊**：參閱 `windows_time_sync_guide.md`
- 📝 **基本說明**：參閱 `README.md`

---

## 檢查清單

設定完成後，確認以下項目：

**Server 端**
- [ ] 服務狀態：Running
- [ ] 輪詢間隔：6 (64s)
- [ ] 根散佈：< 2s
- [ ] 最近同步：幾分鐘內
- [ ] 防火牆：UDP 123 已開放

**Client 端**
- [ ] 服務狀態：Running
- [ ] 輪詢間隔：6 (64s)
- [ ] 根散佈：< 3s
- [ ] 最近同步：幾分鐘內
- [ ] 時間來源：Server IP

---

**版本：1.1.0 | 最後更新：2025-11-11**
