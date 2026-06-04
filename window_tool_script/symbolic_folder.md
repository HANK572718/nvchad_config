# Windows 符號連結 (Symbolic Link) 使用說明

本文件說明如何在 Windows PowerShell 和 CMD 中建立符號連結。

---

## 📋 目錄

- [PowerShell 語法](#powershell-語法)
- [CMD mklink 命令](#cmd-mklink-命令)
- [查看與管理符號連結](#查看與管理符號連結)
- [重要注意事項](#重要注意事項)
- [常見錯誤處理](#常見錯誤處理)
- [實際應用範例](#實際應用範例)

---

## 🔧 PowerShell 語法

### 建立檔案符號連結

```powershell
# Basic syntax
New-Item -ItemType SymbolicLink -Path "link_path" -Target "target_path"

# Example: Create file symbolic link
New-Item -ItemType SymbolicLink -Path "C:\MyLink\config.txt" -Target "D:\Original\config.txt"
```

**範例:**

```powershell
# Link configuration file from project to user directory
New-Item -ItemType SymbolicLink `
    -Path "C:\Users\User\Documents\config.yaml" `
    -Target "D:\docs\AD_ITRI_questcomposite\model_use\config.yaml"
```

### 建立目錄符號連結

```powershell
# Basic syntax
New-Item -ItemType SymbolicLink -Path "link_directory" -Target "target_directory"

# Example: Create directory symbolic link
New-Item -ItemType SymbolicLink -Path "C:\MyLink" -Target "D:\OriginalFolder"
```

**範例:**

```powershell
# Link test_captures folder
New-Item -ItemType SymbolicLink `
    -Path "D:\docs\AD_ITRI_questcomposite\test_captures" `
    -Target "D:\test_data\captures"

# Link model_use folder
New-Item -ItemType SymbolicLink `
    -Path "C:\Projects\model_use" `
    -Target "D:\SharePoint\AD_Model\model_use"
```

### 建立硬連結 (Hard Link)

```powershell
# Hard link for files only (not directories)
New-Item -ItemType HardLink -Path "link_path" -Target "target_file"

# Example
New-Item -ItemType HardLink -Path "C:\backup\file.txt" -Target "D:\data\file.txt"
```

### 建立接合點 (Junction)

```powershell
# Junction for directories (older Windows compatibility)
New-Item -ItemType Junction -Path "link_directory" -Target "target_directory"

# Example
New-Item -ItemType Junction -Path "C:\Users\Public\SharedDocs" -Target "D:\Documents"
```

---

## 💻 CMD mklink 命令

如果在 PowerShell 中需要使用傳統的 `mklink` 命令:

### 基本語法

```cmd
# Run CMD from PowerShell
cmd /c mklink "link" "target"

# Or enter CMD mode
cmd
```

### 建立檔案符號連結

```cmd
mklink "link_file" "target_file"
```

**範例:**

```cmd
mklink "C:\MyLink\config.txt" "D:\Original\config.txt"
```

### 建立目錄符號連結

```cmd
mklink /D "link_directory" "target_directory"
```

**範例:**

```cmd
mklink /D "C:\Projects\test_captures" "D:\test_data\captures"
```

### 建立硬連結

```cmd
mklink /H "link_file" "target_file"
```

### 建立接合點

```cmd
mklink /J "link_directory" "target_directory"
```

### 從 PowerShell 執行 mklink

```powershell
# Method 1: Direct CMD call
cmd /c mklink /D "C:\MyLink" "D:\OriginalFolder"

# Method 2: Using Start-Process
Start-Process cmd -ArgumentList "/c mklink /D `"C:\MyLink`" `"D:\OriginalFolder`"" -Verb RunAs
```

---

## 🔍 查看與管理符號連結

### 查看符號連結

```powershell
# List items with symbolic link attribute
Get-ChildItem | Where-Object { $_.Attributes -match "ReparsePoint" }

# Show detailed information
Get-Item "C:\MyLink" | Select-Object Name, Target, LinkType

# Check if path is a symbolic link
(Get-Item "C:\MyLink").Attributes -match "ReparsePoint"
```

### 使用 CMD 查看

```cmd
# Show symbolic links in directory
dir /AL

# Show detailed directory listing
dir /AL /S
```

### 取得符號連結目標

```powershell
# Get target path
(Get-Item "C:\MyLink").Target

# Example
$link = Get-Item "D:\docs\AD_ITRI_questcomposite\test_captures"
if ($link.Attributes -match "ReparsePoint") {
    Write-Host "Link Target: $($link.Target)"
}
```

---

## 🗑️ 刪除符號連結

### PowerShell 刪除方法

```powershell
# Remove symbolic link (does NOT delete target)
Remove-Item "C:\MyLink"

# For directory links, use -Force to avoid confirmation
Remove-Item "C:\MyLinkDirectory" -Force

# Safe deletion with confirmation
if (Test-Path "C:\MyLink") {
    $confirm = Read-Host "Delete link 'C:\MyLink'? (Y/N)"
    if ($confirm -eq 'Y') {
        Remove-Item "C:\MyLink" -Force
        Write-Host "Link deleted" -ForegroundColor Green
    }
}
```

### CMD 刪除方法

```cmd
# Delete file symbolic link
del "C:\MyLink\config.txt"

# Delete directory symbolic link or junction
rmdir "C:\MyLinkDirectory"
```

⚠️ **重要**: 刪除符號連結**不會**刪除目標檔案或目錄！

---

## ⚙️ 重要注意事項

### 1. 管理員權限

建立符號連結通常需要管理員權限，請以管理員身分執行 PowerShell。

```powershell
# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run as Administrator" -ForegroundColor Red
    exit
}
```

**以管理員身分執行 PowerShell:**
- 右鍵點擊 PowerShell 圖示
- 選擇「以系統管理員身分執行」

### 2. 路徑格式

```powershell
# Absolute path (recommended)
New-Item -ItemType SymbolicLink -Path "C:\Link" -Target "D:\Target"

# Relative path (from current directory)
New-Item -ItemType SymbolicLink -Path ".\link" -Target "..\..\target"

# Use quotes for paths with spaces
New-Item -ItemType SymbolicLink -Path "C:\My Documents\link" -Target "D:\My Files\target"
```

### 3. 符號連結類型差異

| 類型 | 用途 | 跨磁碟 | 權限需求 | 目標刪除影響 |
|------|------|--------|----------|------------|
| **SymbolicLink** | 檔案或目錄 | ✅ 支援 | 管理員 | 連結失效 |
| **HardLink** | 僅檔案 | ❌ 不支援 | 一般使用者 | 檔案仍存在 |
| **Junction** | 僅目錄 | ✅ 支援 | 一般使用者 | 連結失效 |

### 4. 檢查符號連結狀態

```powershell
# Function to check link status
function Test-SymbolicLink {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "Path does not exist: $Path" -ForegroundColor Red
        return
    }

    $item = Get-Item $Path
    if ($item.Attributes -match "ReparsePoint") {
        Write-Host "Type: Symbolic Link" -ForegroundColor Green
        Write-Host "Target: $($item.Target)"

        if (Test-Path $item.Target) {
            Write-Host "Target Status: Valid" -ForegroundColor Green
        } else {
            Write-Host "Target Status: Broken (target not found)" -ForegroundColor Red
        }
    } else {
        Write-Host "Not a symbolic link" -ForegroundColor Yellow
    }
}

# Usage
Test-SymbolicLink "C:\MyLink"
```

---

## 🛠️ 常見錯誤處理

### 錯誤 1: 需要提高的權限

**錯誤訊息:**
```
New-Item : Administrator privileges required to create symbolic link
```

**解決方案:**
1. 以系統管理員身分執行 PowerShell
2. 或啟用開發者模式 (Windows 10 1703+):
   - 設定 → 更新與安全性 → 開發人員選項 → 開發人員模式

### 錯誤 2: 目標路徑不存在

**錯誤訊息:**
```
New-Item : Cannot find path 'D:\Target' because it does not exist
```

**解決方案:**
確認目標檔案或目錄存在後再建立符號連結

```powershell
# Check before creating link
$target = "D:\Target"
if (Test-Path $target) {
    New-Item -ItemType SymbolicLink -Path "C:\Link" -Target $target
} else {
    Write-Host "Target does not exist: $target" -ForegroundColor Red
}
```

### 錯誤 3: 連結已存在

**錯誤訊息:**
```
New-Item : An item with the specified name already exists
```

**解決方案:**

```powershell
# Option 1: Delete existing link first
Remove-Item "C:\MyLink" -Force
New-Item -ItemType SymbolicLink -Path "C:\MyLink" -Target "D:\Target"

# Option 2: Use -Force to overwrite
New-Item -ItemType SymbolicLink -Path "C:\MyLink" -Target "D:\Target" -Force
```

### 錯誤 4: 路徑包含空格

**解決方案:**
使用引號包住路徑

```powershell
# Correct
New-Item -ItemType SymbolicLink -Path "C:\My Documents\link" -Target "D:\My Files\target"

# Wrong (will cause error)
# New-Item -ItemType SymbolicLink -Path C:\My Documents\link -Target D:\My Files\target
```

---

## 📝 實際應用範例

### 本專案中的符號連結使用

#### 範例 1: 連結測試資料目錄

```powershell
# Link test_captures to external storage
New-Item -ItemType SymbolicLink `
    -Path "D:\docs\AD_ITRI_questcomposite\test_captures" `
    -Target "E:\TestData\captures"

# Verify link
Get-Item "D:\docs\AD_ITRI_questcomposite\test_captures" | Select-Object Name, Target
```

#### 範例 2: 連結 model_use 設定目錄

```powershell
# Link model_use from SharePoint sync folder
New-Item -ItemType SymbolicLink `
    -Path "D:\docs\AD_ITRI_questcomposite\model_use" `
    -Target "C:\Users\User\SharePoint\AD_Model\model_use"
```

#### 範例 3: 連結日誌目錄到監控系統

```powershell
# Link logs directory to centralized log server
New-Item -ItemType SymbolicLink `
    -Path "C:\Logs\AD_ITRI" `
    -Target "D:\docs\AD_ITRI_questcomposite\logs"
```

#### 範例 4: 批次建立多個符號連結

```powershell
# Define link mappings
$linkMappings = @(
    @{ Link = "C:\Projects\model_use"; Target = "D:\SharePoint\model_use" }
    @{ Link = "C:\Projects\test_data"; Target = "E:\TestData" }
    @{ Link = "C:\Projects\logs"; Target = "D:\docs\AD_ITRI_questcomposite\logs" }
)

# Create all links
foreach ($mapping in $linkMappings) {
    $linkPath = $mapping.Link
    $targetPath = $mapping.Target

    # Check if target exists
    if (-not (Test-Path $targetPath)) {
        Write-Host "Target not found: $targetPath" -ForegroundColor Red
        continue
    }

    # Remove existing link if any
    if (Test-Path $linkPath) {
        Remove-Item $linkPath -Force
    }

    # Create symbolic link
    try {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -Force | Out-Null
        Write-Host "Created link: $linkPath -> $targetPath" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create link: $linkPath" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}
```

### 管理腳本範例

```powershell
# Complete link management script
function Manage-SymbolicLinks {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Action,  # "create", "list", "verify", "remove"

        [string]$LinkPath,
        [string]$TargetPath
    )

    switch ($Action.ToLower()) {
        "create" {
            if (-not $LinkPath -or -not $TargetPath) {
                Write-Host "LinkPath and TargetPath required for create action" -ForegroundColor Red
                return
            }

            if (Test-Path $TargetPath) {
                New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force
                Write-Host "Created: $LinkPath -> $TargetPath" -ForegroundColor Green
            } else {
                Write-Host "Target does not exist: $TargetPath" -ForegroundColor Red
            }
        }

        "list" {
            Get-ChildItem -Recurse | Where-Object { $_.Attributes -match "ReparsePoint" } |
                Select-Object FullName, Target | Format-Table -AutoSize
        }

        "verify" {
            $links = Get-ChildItem -Recurse | Where-Object { $_.Attributes -match "ReparsePoint" }
            foreach ($link in $links) {
                $status = if (Test-Path $link.Target) { "Valid" } else { "Broken" }
                Write-Host "$($link.FullName) -> $($link.Target) [$status]"
            }
        }

        "remove" {
            if (-not $LinkPath) {
                Write-Host "LinkPath required for remove action" -ForegroundColor Red
                return
            }

            if (Test-Path $LinkPath) {
                Remove-Item $LinkPath -Force
                Write-Host "Removed: $LinkPath" -ForegroundColor Green
            } else {
                Write-Host "Link not found: $LinkPath" -ForegroundColor Yellow
            }
        }

        default {
            Write-Host "Invalid action. Use: create, list, verify, or remove" -ForegroundColor Red
        }
    }
}

# Usage examples
# Manage-SymbolicLinks -Action "create" -LinkPath "C:\MyLink" -TargetPath "D:\Target"
# Manage-SymbolicLinks -Action "list"
# Manage-SymbolicLinks -Action "verify"
# Manage-SymbolicLinks -Action "remove" -LinkPath "C:\MyLink"
```

---

## 📚 快速參考

### PowerShell 命令速查

```powershell
# Create symbolic link
New-Item -ItemType SymbolicLink -Path "link" -Target "target"

# Create junction
New-Item -ItemType Junction -Path "link" -Target "target"

# Create hard link
New-Item -ItemType HardLink -Path "link" -Target "target"

# List symbolic links
Get-ChildItem | Where-Object { $_.Attributes -match "ReparsePoint" }

# Get target
(Get-Item "link").Target

# Remove link
Remove-Item "link" -Force
```

### CMD 命令速查

```cmd
# Create file symbolic link
mklink "link" "target"

# Create directory symbolic link
mklink /D "link" "target"

# Create hard link
mklink /H "link" "target"

# Create junction
mklink /J "link" "target"

# List symbolic links
dir /AL
```

---

## 📖 相關資源

### 官方文件
- [Microsoft - New-Item Cmdlet](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item)
- [Symbolic Links (Windows)](https://docs.microsoft.com/en-us/windows/win32/fileio/symbolic-links)
- [mklink Command Reference](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/mklink)

### 相關工具
- Link Shell Extension: 圖形化符號連結管理工具
- PowerShell: 內建符號連結支援
- Developer Mode: Windows 10+ 無需管理員權限

---

## 📌 版本資訊

- **建立日期**: 2025-01-19
- **最後更新**: 2025-01-19
- **適用系統**: Windows 7+, Windows Server 2008 R2+

---

**祝使用順利！** 🔗
