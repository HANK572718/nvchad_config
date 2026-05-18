-- conform.nvim 設定：依檔案類型指定使用的格式化工具
local options = {
  formatters_by_ft = {
    lua                = { "stylua" },
    javascript         = { "prettier" },
    javascriptreact    = { "prettier" },
    typescript         = { "prettier" },
    typescriptreact    = { "prettier" },
    html               = { "prettier" },
    css                = { "prettier" },
    scss               = { "prettier" },
    json               = { "prettier" },
    jsonc              = { "prettier" },
    markdown           = { "prettier" },
  },

  -- 存檔時自動格式化（取消註解以啟用）
  -- format_on_save = {
  --   timeout_ms = 2000,
  --   lsp_fallback = true,
  -- },
}

return options
