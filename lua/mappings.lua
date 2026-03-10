-- 載入 NvChad 預設按鍵映射
require "nvchad.mappings"

local map = vim.keymap.set

-- 在 Normal 模式下，按 ; 直接進入命令列（省去按 Shift+:）
map("n", ";", ":", { desc = "CMD enter command mode" })
-- 在 Insert 模式下，按 jk 快速回到 Normal 模式（替代 <ESC>）
map("i", "jk", "<ESC>")

-- =============================================================
-- Telescope 完整模式（忽略 gitignore，含 max-filesize / max-depth）
-- 對應預設：<leader>ff -> <leader>fF，<leader>fw -> <leader>fW
-- =============================================================
map("n", "<leader>fF", function()
  require("telescope.builtin").find_files({
    no_ignore = true,
    hidden = true,
    depth = 5,
  })
end, { desc = "telescope find files (no gitignore)" })

map("n", "<leader>fW", function()
  require("telescope.builtin").live_grep({
    additional_args = { "--no-ignore", "--max-filesize", "500K" },
  })
end, { desc = "telescope live grep (no gitignore)" })

-- Telescope LSP 符號搜尋（類似 VSCode Ctrl+Shift+O）
map("n", "<leader>o", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "LSP 顯示文件符號列表" })
map("n", "<leader>O", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", { desc = "LSP 顯示工作區符號列表" })

-- LSP 跳轉到參考（Python 以 references 取代 implementations）
map("n", "gI", "<cmd>Telescope lsp_references<cr>", { desc = "LSP Find References (類似 Implementation)" })
map("n", "gr", "<cmd>Telescope lsp_references<cr>", { desc = "LSP Find References" })

-- LSP Call Hierarchy（呼叫階層）
map("n", "<leader>ci", "<cmd>Telescope lsp_incoming_calls<cr>", { desc = "LSP Incoming Calls（誰呼叫了我）" })
map("n", "<leader>co", "<cmd>Telescope lsp_outgoing_calls<cr>", { desc = "LSP Outgoing Calls（我呼叫了誰）" })

-- Telescope 除錯用自訂命令（:TelescopeXxx 開頭）
vim.api.nvim_create_user_command("TelescopeShowIgnorePatterns", function()
  require("configs.telescope_debug").show_ignore_patterns()
end, { desc = "顯示 Telescope 忽略的模式" })

vim.api.nvim_create_user_command("TelescopeCountFiles", function()
  require("configs.telescope_debug").count_files_in_cwd()
end, { desc = "計算當前目錄的檔案數量" })

vim.api.nvim_create_user_command("TelescopeAnalyzeFolders", function()
  require("configs.telescope_debug").analyze_folders()
end, { desc = "分析當前目錄下的資料夾" })

-- 圖片瀏覽器：用 Telescope + chafa 預覽圖片（<leader>fp）
map("n", "<leader>fp", function()
  require("configs.image_preview").find_images()
end, { desc = "瀏覽圖片（Image Browser）" })

-- =============================================================
-- DAP 快捷鍵（Python 調試）
-- =============================================================
map("n", "<F5>",       function() require("dap").continue() end,          { desc = "DAP Continue/Start" })
map("n", "<F10>",      function() require("dap").step_over() end,         { desc = "DAP Step Over" })
map("n", "<F11>",      function() require("dap").step_into() end,         { desc = "DAP Step Into" })
map("n", "<F12>",      function() require("dap").step_out() end,          { desc = "DAP Step Out" })
map("n", "<leader>dr", function() require("dap").restart() end,           { desc = "DAP Restart" })
map("n", "<leader>db", function() require("dap").toggle_breakpoint() end, { desc = "DAP Toggle Breakpoint" })
map("n", "<leader>dB", function()
  require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
end, { desc = "DAP Conditional Breakpoint" })
map("n", "<leader>du", function() require("dapui").toggle() end,          { desc = "DAP Toggle UI" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- 快速切換 tab（NvChad tabufline）
-- <A-n>：Alt+數字，適用終端機 / SSH 所有平台
-- <D-n>：Cmd+數字，僅限 Mac/Windows Neovide GUI
local function goto_tab(i)
  local bufs = vim.t.bufs
  if bufs and bufs[i] then
    require("nvchad.tabufline").goto_buf(bufs[i])
  end
end

-- 綁定 Alt+1~9 與（GUI 模式下）Cmd/Win+1~9 切換 buffer
for i = 1, 9 do
  map("n", "<A-" .. i .. ">", function() goto_tab(i) end, { desc = "Tab " .. i .. "（Alt）" })
  if vim.fn.has("gui_running") == 1 or vim.g.neovide then
    map("n", "<D-" .. i .. ">", function() goto_tab(i) end, { desc = "Tab " .. i .. "（Cmd/Win GUI）" })
  end
end
