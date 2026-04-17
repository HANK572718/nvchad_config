require "nvchad.options"

-- add yours here!

-- Shell 設定：Windows 用 PowerShell 7，Linux/Mac 用系統預設 shell
if vim.fn.has("win32") == 1 then
  vim.opt.shell = "pwsh"
  vim.opt.shellcmdflag = "-NoLogo -NonInteractive -Command"
  vim.opt.shellquote = ""
  vim.opt.shellxquote = ""
end

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

-- Treesitter-based folding（依程式結構折疊 function / class / block）
-- 使用 Neovim 內建 vim.treesitter.foldexpr()，fold 計算正確
-- 開檔時預設不折疊，按 zM 全收、zR 全展、za toggle 當前區塊
vim.opt.foldmethod = "expr"
vim.opt.foldexpr   = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldenable = false
vim.opt.foldlevel  = 99
