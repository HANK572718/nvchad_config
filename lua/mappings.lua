require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Telescope LSP symbols (類似 VSCode Ctrl+Shift+O)
map("n", "<leader>o", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "LSP 顯示文件符號列表" })
map("n", "<leader>O", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", { desc = "LSP 顯示工作區符號列表" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
