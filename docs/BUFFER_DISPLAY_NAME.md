# 動態 Buffer 顯示名稱（Dynamic Buffer Display Name）

讓你可以**自由更改某個 buffer 在頂部 tabufline 上顯示的名稱**，而不改動真實檔案路徑。
靈感來自 Claude Code 會隨工作進度動態改自己的 terminal 標題。

> 概念：把名稱存進 buffer-local 變數 `vim.b[buf].display_name`，重新渲染 tabufline
> 時優先顯示它。等同 CC 反覆寫 OSC 2 escape sequence —— 「改狀態 → 重畫」。

底部 statusline 仍顯示**真實檔名**，方便辨認「這其實是哪個檔」。

## 檔案

| 檔案 | 角色 |
|------|------|
| `lua/configs/bufname.lua` | 核心：重寫 `style_buf` + `setup/set_name/clear_name/get_name` + 持久化 `save/restore` |
| `lua/autocmds.lua` | 安裝（VeryLazy）、開檔還原（BufReadPost）、存檔（VimLeavePre/BufWritePost）、TermOpen 自動標記 CC |
| `lua/mappings.lua` | `:BufRename` 指令 + `<leader>br` 快捷鍵 |

## 三種使用方式

### 1. 手動（我自己改）

```vim
:BufRename API-Server      " 直接設定當前 buffer 顯示名
:BufRename                 " 跳出輸入框（預填目前名稱，空輸入=清除恢復檔名）
```

或快捷鍵 `<leader>br`（normal mode）→ 跳出輸入框。

### 2. 外部程式 / Claude Code 寫入（程式自動改）

`set_name` 是公開 Lua 函式，外部只要能對該 nvim 實例送 RPC 即可。
nvim（TUI / headless）預設就有 RPC server，位址在環境變數 `$NVIM`（子程序可見）
或 `:echo v:servername`。

```bash
# 對指定 nvim 實例設定「當前」buffer 顯示名
nvim --server "$NVIM" --remote-expr \
  "luaeval('require(\"configs.bufname\").set_name(0, _A)', 'CC: editing options.lua')"

# 指定某個 buffer 編號（例如 7）
nvim --server "$NVIM" --remote-expr \
  "luaeval('require(\"configs.bufname\").set_name(7, _A)', 'building…')"

# 清除
nvim --server "$NVIM" --remote-expr \
  "luaeval('require(\"configs.bufname\").clear_name(0)')"
```

PowerShell 下注意引號跳脫，或改用 `--remote-send` 呼叫 `:BufRename`：

```powershell
nvim --server $env:NVIM --remote-send ':BufRename CC works<CR>'
```

> Claude Code 在 nvim terminal 裡執行時，`$NVIM` 已被設好，CC 內的指令可直接用上面的呼叫
> 來「回報目前在做什麼」。

### 3. autocmd 自動跟隨狀態

`lua/autocmds.lua` 內建一個範本：`TermOpen` 時若 terminal 名稱含 `claude`/`cc`，
自動把該 buffer 顯示名設為 `CC`。可照同樣模式擴充其他事件，例如：

```lua
-- 檔案被修改時加 ● 前綴（示意）
vim.api.nvim_create_autocmd("BufModifiedSet", {
  callback = function(a)
    if vim.bo[a.buf].modified then
      -- 自行決定要不要疊加；這裡僅示意呼叫公開 API
    end
  end,
})
```

## 持久化

- 自訂名以**檔案絕對路徑**為 key，存於 `stdpath('state')/buf_display_names.json`。
- 開檔（`BufReadPost`）自動還原；離開 / 存檔時寫回磁碟。
- 與 `auto-session` 並存無衝突（各存各的）。
- **無名 buffer（terminal / scratch）不持久化** —— 路徑不穩定，下次對不上。

## 公開 API

```lua
local bufname = require "configs.bufname"
bufname.set_name(buf, name)  -- buf 省略/0 = 當前 buffer；name 空字串 = 清除
bufname.clear_name(buf)
bufname.get_name(buf)        -- 回傳目前自訂名或 nil
```

## 已知限制

- 顯示名仍受 tabufline 寬度截斷（`maxname_len = bufwidth - 5`），buffer 多時長名會被截成 `..`。
- 自訂名會**跳過**目錄消歧（兩個同名自訂 buffer 不會自動加上層目錄前綴）——這是刻意的，名稱由你決定。
- 渲染靠**重寫** NvChad 的 `style_buf`（見 `lua/configs/bufname.lua` 檔頭說明）；
  升級 NvChad/ui 若改動該函式，需對照 `nvchad/tabufline/utils.lua` 重新 diff。
