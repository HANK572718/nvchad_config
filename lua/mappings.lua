require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Telescope LSP symbols (類似 VSCode Ctrl+Shift+O)
map("n", "<leader>o", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "LSP 顯示文件符號列表" })
map("n", "<leader>O", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", { desc = "LSP 顯示工作區符號列表" })

-- Telescope Debug commands
vim.api.nvim_create_user_command("TelescopeShowIgnorePatterns", function()
  require("configs.telescope_debug").show_ignore_patterns()
end, { desc = "顯示 Telescope 忽略的模式" })

vim.api.nvim_create_user_command("TelescopeCountFiles", function()
  require("configs.telescope_debug").count_files_in_cwd()
end, { desc = "計算當前目錄的檔案數量" })

vim.api.nvim_create_user_command("TelescopeAnalyzeFolders", function()
  require("configs.telescope_debug").analyze_folders()
end, { desc = "分析當前目錄下的資料夾" })

-- Image preview with custom Telescope + chafa
map("n", "<leader>fp", function()
  require("configs.image_preview").find_images()
end, { desc = "瀏覽圖片（Image Browser）" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
