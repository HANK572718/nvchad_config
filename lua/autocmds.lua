require "nvchad.autocmds"

-- 讓 log rotate 檔案（如 app.log.1, app.log.2）也被識別為 log filetype
-- 用 autocmd 直接設定，比 vim.filetype.add 更可靠，避免 lazy load chicken-egg 問題
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.log.*", "*.log-*" },
  callback = function()
    vim.bo.filetype = "log"
  end,
})
