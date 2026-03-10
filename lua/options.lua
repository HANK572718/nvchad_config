require "nvchad.options"

-- add yours here!

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

-- Treesitter-based folding（依程式結構折疊 function / class / block）
-- 開檔時預設不折疊，按 zM 全收、zR 全展、za toggle 當前區塊
vim.opt.foldmethod = "expr"
vim.opt.foldexpr   = "nvim_treesitter#foldexpr()"
vim.opt.foldenable = false
vim.opt.foldlevel  = 99
