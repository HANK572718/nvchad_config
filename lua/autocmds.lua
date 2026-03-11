require "nvchad.autocmds"


-- 讓 log rotate 檔案（如 app.log.1, app.log.2）也被識別為 log filetype
-- 用 autocmd 直接設定，比 vim.filetype.add 更可靠，避免 lazy load chicken-egg 問題
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.log.*", "*.log-*" },
  callback = function()
    vim.bo.filetype = "log"
  end,
})

-- auto-session 還原 session 後，強制統一 foldexpr 為 v:lua.vim.treesitter.foldexpr()
-- 避免舊 session 殘留其他 foldexpr 值（如 nvim_treesitter#foldexpr()）導致 zM 無效
vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.wo[win].foldmethod == "expr" then
          vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        end
      end
    end)
  end,
})
