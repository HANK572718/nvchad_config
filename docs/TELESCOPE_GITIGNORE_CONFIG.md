# Telescope 自動讀取 .gitignore 資料夾規則 - 實作文件

## 📋 需求說明

### 問題 1：`<leader>o` 無法顯示 LSP 符號列表
- **現狀**：手動執行 `:Telescope lsp_document_symbols` 可以運作
- **問題**：按 `<leader>o` 無法觸發
- **狀態**：✅ 已解決（用戶自行解決）

### 問題 2：`<leader>ff` 搜尋範圍過大
- **需求 1**：搜尋檔案時自動排除大型資料夾（如 `build/`, `.venv/`, `node_modules/`）
- **需求 2**：根據每個專案的 `.gitignore` 中的**資料夾規則**動態過濾
- **需求 3**：只忽略資料夾，不忽略單獨的檔案規則
- **狀態**：✅ 已實作完成

---

## 🔍 問題分析

### 用戶需求細節

假設 `.gitignore` 內容如下：
```gitignore
# 資料夾規則
build/
dist/
.venv/
data/

# 檔案規則
*.log
*.pyc
secret.txt
```

**期望行為**：
- ❌ **資料夾規則**：`build/`, `dist/`, `.venv/`, `data/` → 不要出現在 Telescope 搜尋結果
- ✅ **檔案規則**：`*.log`, `*.pyc`, `secret.txt` → 仍然可以搜尋到

### 技術挑戰

1. **標準工具的限制**
   - `ripgrep (rg)` 和 `fd` 會完全遵循 `.gitignore`（包括資料夾和檔案）
   - 無法區分資料夾規則和檔案規則

2. **Windows 環境**
   - 用戶系統上未安裝 `rg` 或 `fd`
   - 需要使用 Neovim 原生 API

3. **動態性需求**
   - 每個專案的 `.gitignore` 不同
   - 需要在開啟 Neovim 時動態讀取並解析

---

## 🎯 解決方案

### 方案概述

實作一個 Lua 函數來：
1. 自動找到當前 Git 專案的根目錄
2. 讀取 `.gitignore` 檔案
3. 解析出**以 `/` 結尾的資料夾規則**
4. 將 gitignore 模式轉換為 Lua 正則表達式模式
5. 與基礎資料夾清單合併
6. 動態應用到 Telescope 的 `file_ignore_patterns`

### 架構設計

```
┌─────────────────────────────────────┐
│  Telescope find_files (<leader>ff) │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   get_file_ignore_patterns()        │
└──────────────┬──────────────────────┘
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
┌──────────────┐  ┌────────────────────┐
│ 基礎資料夾清單│  │ .gitignore 資料夾   │
│ (永遠忽略)   │  │ (動態讀取)         │
└──────────────┘  └────────────────────┘
       │                │
       └───────┬────────┘
               ▼
      合併並應用過濾規則
```

---

## 💻 實作細節

### 檔案位置

- **主配置檔案**：`lua\configs\telescope.lua`
- **插件載入**：`lua\plugins\init.lua` (第 8-12 行)

### 核心函數

#### 1. `parse_gitignore_folders()` (第 3-51 行)

**功能**：解析 .gitignore 並提取資料夾規則

**流程**：
```lua
1. 找到 Git 根目錄
   ↓
2. 檢查 .gitignore 是否存在
   ↓
3. 逐行讀取 .gitignore
   ↓
4. 過濾註解和空行
   ↓
5. 檢查是否以 / 結尾（資料夾）
   ↓
6. 轉換 gitignore 模式為 Lua 模式
   ↓
7. 返回資料夾模式清單
```

**模式轉換邏輯**：
```lua
-- gitignore 模式 → Lua 模式
"**/build/"  → "build/"       -- 移除前綴萬用字元
"dist/"      → "dist/"        -- 保持原樣
"data-*/"    → "data%-.*/"    -- 轉義特殊字元，* → .*
```

**處理的 gitignore 模式**：
- ✅ `build/` - 簡單資料夾
- ✅ `**/temp/` - 任意深度的資料夾
- ✅ `src/build/` - 特定路徑的資料夾
- ✅ `dist-*/` - 帶萬用字元的資料夾

#### 2. `get_base_patterns()` (第 54-71 行)

**功能**：定義永遠要忽略的基礎資料夾清單

**包含的資料夾**：
```lua
{
  ".git/",              -- Git 內部資料
  "node_modules/",      -- Node.js 依賴
  "__pycache__/",       -- Python 快取
  ".pytest_cache/",     -- Pytest 快取
  ".mypy_cache/",       -- Mypy 快取
  ".tox/",              -- Tox 測試環境
  "%.egg%-info/",       -- Python 套件資訊
  ".vscode/",           -- VSCode 設定
  ".idea/",             -- JetBrains IDE 設定
}
```

#### 3. `get_file_ignore_patterns()` (第 74-84 行)

**功能**：合併基礎模式與 .gitignore 模式

```lua
local function get_file_ignore_patterns()
  local base_patterns = get_base_patterns()
  local gitignore_patterns = parse_gitignore_folders()

  -- 合併模式
  for _, pattern in ipairs(gitignore_patterns) do
    table.insert(base_patterns, pattern)
  end

  return base_patterns
end
```

---

## 🔧 配置檔案

### `lua\configs\telescope.lua` (完整)

```lua
-- Parse .gitignore and extract folder patterns (lines ending with /)
-- Only ignores folders, not individual files
local function parse_gitignore_folders()
  local patterns = {}

  -- Find git root directory
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>nul")[1]
  if vim.v.shell_error ~= 0 or not git_root then
    return patterns
  end

  local gitignore_path = git_root .. "\\.gitignore"

  -- Check if .gitignore exists
  if vim.fn.filereadable(gitignore_path) == 0 then
    return patterns
  end

  -- Read .gitignore file
  local lines = vim.fn.readfile(gitignore_path)

  for _, line in ipairs(lines) do
    -- Skip comments and empty lines
    if line:match("^%s*#") or line:match("^%s*$") then
      goto continue
    end

    -- Remove leading/trailing whitespace
    line = line:match("^%s*(.-)%s*$")

    -- Check if it's a folder (ends with /)
    if line:match("/$") then
      -- Convert gitignore pattern to Lua pattern
      -- Remove leading wildcards like **/ or */
      local pattern = line:gsub("^%*%*/", ""):gsub("^%*/", "")

      -- Escape special Lua pattern characters except * and ?
      pattern = pattern:gsub("([%.%-%+%[%]%(%)%$%^%%])", "%%%1")

      -- Convert gitignore wildcards to Lua patterns
      pattern = pattern:gsub("%*", ".*")  -- * -> .*
      pattern = pattern:gsub("%?", ".")   -- ? -> .

      table.insert(patterns, pattern)
    end

    ::continue::
  end

  return patterns
end

-- Get base folder ignore patterns (always applied)
local function get_base_patterns()
  return {
    -- Git internals
    ".git/",

    -- Common large folders that should always be ignored
    "node_modules/",
    "__pycache__/",
    ".pytest_cache/",
    ".mypy_cache/",
    ".tox/",
    "%.egg%-info/",

    -- IDE folders
    ".vscode/",
    ".idea/",
  }
end

-- Merge base patterns with .gitignore folder patterns
local function get_file_ignore_patterns()
  local base_patterns = get_base_patterns()
  local gitignore_patterns = parse_gitignore_folders()

  -- Merge patterns
  for _, pattern in ipairs(gitignore_patterns) do
    table.insert(base_patterns, pattern)
  end

  return base_patterns
end

local options = {
  defaults = {
    file_ignore_patterns = get_file_ignore_patterns(),
  },
}

return options
```

### `lua\plugins\init.lua` (相關部分)

```lua
return {
  -- ... 其他插件 ...

  -- Telescope configuration with file ignore patterns
  {
    "nvim-telescope/telescope.nvim",
    opts = require "configs.telescope",
  },

  -- ... 其他插件 ...
}
```

---

## 📖 使用說明

### 啟用配置

1. **重新啟動 Neovim**：
   ```vim
   :qa
   ```

2. **自動生效**：
   - 每次開啟 Neovim 時自動讀取當前專案的 `.gitignore`
   - 動態應用資料夾過濾規則

### 使用快捷鍵

- **`<leader>ff`** - 搜尋檔案（Telescope find_files）
  - 自動忽略 `.gitignore` 中的資料夾
  - 不忽略 `.gitignore` 中的檔案規則

---

## 🧪 測試方式

### 測試步驟

#### 1. 建立測試資料夾

在你的專案根目錄建立測試資料夾和檔案：
```powershell
mkdir temp
mkdir logs
echo "test" > temp\test.txt
echo "log content" > test.log
```

#### 2. 編輯 .gitignore

新增以下內容到專案的 `.gitignore`：
```gitignore
# 資料夾規則（應該被忽略）
temp/
logs/

# 檔案規則（不應該被忽略）
*.log
```

#### 3. 重新開啟 Neovim

```powershell
nvim
```

#### 4. 測試搜尋

按 `<leader>ff` 並搜尋：

**預期結果**：
- ❌ 看不到 `temp/test.txt`（資料夾被忽略）
- ❌ 看不到 `logs/` 裡的任何檔案（資料夾被忽略）
- ✅ 可以找到 `test.log`（檔案規則不影響搜尋）

### 驗證 .gitignore 解析

在 Neovim 中執行以下命令來檢查載入的過濾模式：
```vim
:lua print(vim.inspect(require("telescope.config").values.file_ignore_patterns))
```

應該可以看到：
- 基礎資料夾清單（如 `.git/`, `node_modules/`）
- 從 `.gitignore` 解析出的資料夾（如 `temp/`, `logs/`）

---

## ⚙️ 自訂配置

### 修改基礎資料夾清單

若要新增或移除永遠忽略的資料夾，編輯 `lua\configs\telescope.lua` 的 `get_base_patterns()` 函數：

```lua
local function get_base_patterns()
  return {
    ".git/",
    "node_modules/",
    -- 新增你的資料夾
    "vendor/",
    "tmp/",
  }
end
```

### 支援其他 Git 配置檔案

若要支援 `.git/info/exclude` 或全域 `.gitignore`，可以擴展 `parse_gitignore_folders()` 函數：

```lua
local function parse_gitignore_folders()
  local patterns = {}
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>nul")[1]

  if git_root then
    -- 讀取 .gitignore
    local gitignore_patterns = read_ignore_file(git_root .. "\\.gitignore")
    vim.list_extend(patterns, gitignore_patterns)

    -- 讀取 .git/info/exclude
    local exclude_patterns = read_ignore_file(git_root .. "\\.git\\info\\exclude")
    vim.list_extend(patterns, exclude_patterns)
  end

  return patterns
end
```

---

## 🐛 疑難排解

### 問題 1：.gitignore 中的資料夾沒有被忽略

**可能原因**：
- Git 根目錄找不到
- .gitignore 檔案不存在或無法讀取
- 資料夾規則格式不正確（沒有以 `/` 結尾）

**檢查方式**：
```vim
:lua print(vim.fn.systemlist("git rev-parse --show-toplevel 2>nul")[1])
```

**解決方式**：
- 確認當前目錄是 Git 專案
- 確認 .gitignore 存在且格式正確
- 資料夾規則必須以 `/` 結尾（如 `build/`）

### 問題 2：重新啟動後才生效

**說明**：
這是正常行為。Telescope 配置在啟動時載入，所以修改 `.gitignore` 後需要重新啟動 Neovim。

**快速重啟方式**：
```vim
:qa
```

### 問題 3：某些模式無法正確轉換

**已知限制**：
- 複雜的 gitignore 模式（如否定模式 `!important/`）不支援
- 絕對路徑模式（如 `/build/`）會被轉換為相對路徑

**建議**：
對於特殊需求，直接在 `get_base_patterns()` 中手動添加

---

## 📊 功能比較

| 功能 | 手動清單 | 自動讀取 .gitignore |
|------|---------|-------------------|
| 忽略常見大型資料夾 | ✅ | ✅ |
| 專案特定資料夾 | ⚠️ 需手動添加 | ✅ 自動偵測 |
| 跨專案一致性 | ✅ | ⚠️ 依 .gitignore |
| 只忽略資料夾不忽略檔案 | ✅ | ✅ |
| 效能 | 🚀 快 | 🚀 快（啟動時解析） |
| 維護成本 | ⚠️ 需手動維護 | ✅ 自動同步 |

---

## 📚 參考資料

### 相關文件

- [Telescope.nvim 官方文件](https://github.com/nvim-telescope/telescope.nvim)
- [Git .gitignore 規範](https://git-scm.com/docs/gitignore)
- [Lua 模式匹配](https://www.lua.org/manual/5.1/manual.html#5.4.1)

### 檔案位置

- **配置檔案**：`C:\Users\User\AppData\Local\nvim\lua\configs\telescope.lua`
- **插件配置**：`C:\Users\User\AppData\Local\nvim\lua\plugins\init.lua`
- **按鍵映射**：`C:\Users\User\AppData\Local\nvim\lua\mappings.lua`

---

## 📝 更新日誌

### 2025-12-05

**新增**：
- ✅ 實作 `parse_gitignore_folders()` 函數
- ✅ 實作 `get_base_patterns()` 函數
- ✅ 實作 `get_file_ignore_patterns()` 函數
- ✅ 配置 Telescope 使用動態過濾規則
- ✅ 支援 Windows 環境
- ✅ 完整測試驗證

**功能**：
- 自動讀取每個專案的 `.gitignore`
- 只忽略資料夾規則，不忽略檔案規則
- 與基礎資料夾清單合併
- 支援萬用字元模式轉換

---

## 👨‍💻 維護者

此配置由 Claude Code 協助實作，基於用戶需求設計。

**技術棧**：
- Neovim 配置框架：NvChad
- 插件：telescope.nvim
- 語言：Lua
- 環境：Windows

---

## 📄 授權

此配置檔案可自由使用和修改。
