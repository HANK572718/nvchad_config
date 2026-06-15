-- =============================================================
-- 動態 Buffer 顯示名稱（nvim 版「CC 動態改 terminal title」）
--
-- 概念：把名稱存進 buffer-local 變數 vim.b[buf].display_name，
--       重新渲染 tabufline 時優先顯示它，而非真實檔名。
--       state(vim.b) → redrawtabline，等同 CC 反覆寫 OSC 2 escape。
--
-- 觸發來源全部走同一個 API（set_name / clear_name）：
--   - 手動：:BufRename / <leader>br（見 mappings.lua）
--   - 外部/CC：nvim --server <addr> --remote-expr
--               "luaeval('require(\"configs.bufname\").set_name(0, _A)', 'CC: ...')"
--   - 自動：autocmd（見 autocmds.lua，TermOpen 等）
--   - 還原：session/開檔時 restore()（持久化於 stdpath('state')）
--
-- 渲染覆寫：重寫 nvchad.tabufline.utils.style_buf。
--   為何重寫而非 wrap：原 style_buf 把 buf_name / filename /
--   gen_unique_name 以 file-local upvalue 凍結在 module 載入時，
--   wrap 後暫時替換 vim.api.nvim_buf_get_name 不會被原 closure 看到。
--   來源：nvim-data/lazy/ui/lua/nvchad/tabufline/utils.lua (line 44-90)
--   ⚠ NvChad/ui 升級若改動 style_buf，需對照該檔重 diff 本函式。
-- =============================================================

local M = {}
local api = vim.api

-- ── 持久化設定 ───────────────────────────────────────────────
-- key = 檔案絕對路徑；value = 自訂顯示名。無名 buffer（terminal/scratch）
-- 路徑下次對不上，故不持久化。
local STORE_PATH = vim.fn.stdpath("state") .. "/buf_display_names.json"
local store = nil -- 記憶體快取（lazy load）

-- 讀取持久化檔到記憶體（pcall 包 decode 防壞檔）
local function load_store()
  if store ~= nil then
    return store
  end
  store = {}
  if vim.fn.filereadable(STORE_PATH) == 1 then
    local ok, lines = pcall(vim.fn.readfile, STORE_PATH)
    if ok and lines and #lines > 0 then
      local ok2, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
      if ok2 and type(decoded) == "table" then
        store = decoded
      end
    end
  end
  return store
end

-- 取得 buffer 對應的持久化 key（真實檔案絕對路徑；無名 buffer 回傳 nil）
local function persist_key(buf)
  local name = api.nvim_buf_get_name(buf)
  if not name or name == "" then
    return nil
  end
  -- terminal buffer 名稱形如 term://...，不持久化
  if name:match("^%a+://") then
    return nil
  end
  return vim.fn.fnamemodify(name, ":p")
end

-- ── 渲染覆寫：重寫 style_buf ──────────────────────────────────
-- 內聯 utils.lua 的 file-local filename()（跨平台 basename，處理 / 與 \）
local function filename(str)
  return str:match("([^/\\]+)[/\\]*$")
end

-- 對照 utils.lua gen_unique_name：同 basename 時前綴上層目錄名消歧。
-- 僅用於「非自訂名」分支（自訂名是使用者明確選的，不需消歧）。
local function gen_unique_name(name, index)
  local buf_name = api.nvim_buf_get_name
  for i2, nr2 in ipairs(vim.t.bufs) do
    local filepath = filename(buf_name(nr2))
    if index ~= i2 and filepath == name then
      return vim.fn.fnamemodify(buf_name(vim.t.bufs[index]), ":h:t") .. "/" .. name
    end
  end
end

-- 重寫版 style_buf：邏輯與 utils.lua:44-90 一致，僅名稱來源改為
-- 優先讀 vim.b[nr].display_name。其餘（devicon / padding / 截斷 /
-- highlight / GoToBuf|KillBuf 點擊與關閉鈕）原封保留。
local function make_style_buf()
  local utils = require("nvchad.tabufline.utils")
  local get_opt = api.nvim_get_option_value
  local strep = string.rep
  local cur_buf = api.nvim_get_current_buf
  local buf_name = api.nvim_buf_get_name
  local get_hl = api.nvim_get_hl
  local txt = utils.txt
  local btn = utils.btn

  -- 對照 utils.lua 的 file-local new_hl（devicon 配色用）
  local function new_hl(group1, group2)
    local fg = get_hl(0, { name = group1 }).fg
    local bg = get_hl(0, { name = "Tb" .. group2 }).bg
    api.nvim_set_hl(0, group1 .. group2, { fg = fg, bg = bg })
    return "%#" .. group1 .. group2 .. "#"
  end

  return function(nr, i, w)
    -- add fileicon + name
    local icon = "󰈚 "
    local is_curbuf = cur_buf() == nr
    local tbHlName = "BufO" .. (is_curbuf and "n" or "ff")
    local icon_hl = new_hl("DevIconDefault", tbHlName)

    -- ★ 唯一實質差異：優先讀自訂顯示名 ★
    local custom = vim.b[nr] and vim.b[nr].display_name
    local name
    if custom and custom ~= "" then
      name = custom
    else
      local base = filename(buf_name(nr))
      name = base and (gen_unique_name(base, i) or base) or " No Name "
    end

    if name ~= " No Name " then
      local devicon, devicon_hl = require("nvim-web-devicons").get_icon(name)

      if devicon then
        icon = " " .. devicon .. " "
        icon_hl = new_hl(devicon_hl, tbHlName)
      end
    end

    -- padding around bufname; 15= maxnamelen + 2 icon & space + 2 close icon
    local pad = math.floor((w - #name - 5) / 2)
    pad = pad <= 0 and 1 or pad

    local maxname_len = w - 5
    name = string.sub(name, 1, maxname_len - 2) .. (#name > maxname_len and ".." or "")
    name = txt(name, tbHlName)

    name = strep(" ", pad - 1) .. (icon_hl .. icon .. name) .. strep(" ", pad - 1)

    local close_btn = btn(" 󰅖 ", nil, "KillBuf", nr)
    name = btn(name, nil, "GoToBuf", nr)

    -- modified bufs icon or close icon
    local mod = get_opt("mod", { buf = nr })
    local cur_mod = get_opt("mod", { buf = 0 })

    -- color close btn for focused / hidden  buffers
    if is_curbuf then
      close_btn = cur_mod and txt("  ", "BufOnModified") or txt(close_btn, "BufOnClose")
    else
      close_btn = mod and txt("  ", "BufOffModified") or txt(close_btn, "BufOffClose")
    end

    name = txt(name .. close_btn, "BufO" .. (is_curbuf and "n" or "ff"))

    return name
  end
end

-- ── 安裝（once-guard）─────────────────────────────────────────
local installed = false

--- 把重寫版 style_buf 指派回 nvchad.tabufline.utils。
--- 重複呼叫為 no-op，避免重複包裝。需在 NvChad ui 載入後呼叫（VeryLazy）。
function M.setup()
  if installed then
    return
  end
  local ok, utils = pcall(require, "nvchad.tabufline.utils")
  if not ok then
    return
  end
  utils.style_buf = make_style_buf()
  installed = true
end

-- ── 重新渲染（包 schedule 防 fast event 的 E5560）────────────────
local function redraw()
  vim.schedule(function()
    pcall(vim.cmd, "redrawtabline")
  end)
end

-- ── 公開 API ─────────────────────────────────────────────────

--- 設定 buffer 的自訂顯示名。
--- @param buf integer|nil 0 或省略=當前 buffer
--- @param name string 顯示名（空字串等同 clear）
function M.set_name(buf, name)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  if name == nil or name == "" then
    return M.clear_name(buf)
  end
  vim.b[buf].display_name = name
  -- 寫入持久化（僅真實檔案 buffer）
  local key = persist_key(buf)
  if key then
    load_store()[key] = name
  end
  redraw()
end

--- 清除 buffer 的自訂顯示名，恢復顯示真實檔名。
--- @param buf integer|nil 0 或省略=當前 buffer
function M.clear_name(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  vim.b[buf].display_name = nil
  local key = persist_key(buf)
  if key then
    load_store()[key] = nil
  end
  redraw()
end

--- 取得 buffer 目前的自訂顯示名（無則 nil）。
--- @param buf integer|nil 0 或省略=當前 buffer
function M.get_name(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if not api.nvim_buf_is_valid(buf) then
    return nil
  end
  return vim.b[buf].display_name
end

-- ── 持久化 save / restore ─────────────────────────────────────

--- 依 buffer 的絕對路徑查持久化表，有就套回（開檔/還原 session 時呼叫）。
--- @param buf integer
function M.restore(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  local key = persist_key(buf)
  if not key then
    return
  end
  local saved = load_store()[key]
  if saved and saved ~= "" then
    vim.b[buf].display_name = saved
    redraw()
  end
end

--- 把記憶體中的自訂名表寫回磁碟（VimLeavePre / BufWritePost 呼叫）。
function M.save()
  local data = load_store()
  -- 清掉已不存在的檔案 key，避免無限增長
  for key in pairs(data) do
    if vim.fn.filereadable(key) == 0 then
      data[key] = nil
    end
  end
  local ok, encoded = pcall(vim.json.encode, data)
  if ok then
    pcall(vim.fn.writefile, { encoded }, STORE_PATH)
  end
end

return M
