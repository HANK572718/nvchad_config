-- NvChad UI 設定檔，結構需與 nvconfig.lua 相同
-- 參考：https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "chadracula",  -- 目前使用的主題（暗色風格）

	-- 覆蓋特定語法高亮（範例：讓註解顯示為斜體）
	-- hl_override = {
	-- 	Comment = { italic = true },
	-- 	["@comment"] = { italic = true },
	-- },
}

-- 啟動時顯示 NvChad 儀表板（Dashboard）
-- M.nvdash = { load_on_startup = true }

-- 自訂 tabufline（頂部 buffer 列）行為
-- M.ui = {
--       tabufline = {
--          lazyload = false  -- 設為 false 可立即載入 tabufline
--      }
-- }

-- 懸浮終端機視窗大小設定（預設 0.5 x 0.4 太小）
M.term = {
  float = {
    relative = "editor",
    row = 0.1,
    col = 0.1,
    width = 0.8,
    height = 0.7,
    border = "single",
  },
}

return M
