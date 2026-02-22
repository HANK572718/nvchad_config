-- conform.nvim 設定：依檔案類型指定使用的格式化工具
local options = {
  formatters_by_ft = {
    lua = { "stylua" },      -- Lua 使用 stylua 格式化
    -- css = { "prettier" },
    -- html = { "prettier" },
  },

  -- 存檔時自動格式化（取消註解以啟用）
  -- format_on_save = {
  --   timeout_ms = 500,      -- 格式化超時時間（毫秒）
  --   lsp_fallback = true,   -- conform 找不到 formatter 時退回 LSP 格式化
  -- },
}

return options
