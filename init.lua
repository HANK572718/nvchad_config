-- NvChad 主題快取路徑（加速主題載入）
vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
-- <leader> 鍵設為空白鍵
vim.g.mapleader = " "

-- 初始化 lazy.nvim（插件管理器）路徑
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

-- 若尚未安裝則自動從 GitHub clone 穩定版
if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

-- 將 lazy.nvim 加入 runtimepath 最前端
vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- 載入所有插件
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,     -- 立即載入，不延遲
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },  -- 載入 lua/plugins/ 自訂插件
}, lazy_config)

-- 從快取直接載入主題（避免重新計算，加速啟動）
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

-- 載入編輯器選項與自動命令
require "options"
require "autocmds"

-- 延遲載入按鍵映射（UI 完全初始化後再綁定，避免衝突）
vim.schedule(function()
  require "mappings"
end)
