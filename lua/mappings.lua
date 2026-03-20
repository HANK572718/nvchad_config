-- 載入 NvChad 預設按鍵映射
require "nvchad.mappings"

local map = vim.keymap.set

-- 在 Normal 模式下，按 ; 直接進入命令列（省去按 Shift+:）
map("n", ";", ":", { desc = "CMD enter command mode" })
-- 在 Insert 模式下，按 jk 快速回到 Normal 模式（替代 <ESC>）
map("i", "jk", "<ESC>")

-- =============================================================
-- Ctrl+U/D 滾動：insert / terminal mode 直接可用
-- insert mode：<C-\><C-o> 執行一次 normal 指令後自動回 insert mode
-- terminal mode：退出 terminal mode 後滾動（停在 N-TERMINAL）
-- 原 insert built-in：<C-U>=刪到行首、<C-D>=取消縮排（已確認不需要）
-- 原 terminal 功能：<C-U>=shell清行、<C-D>=EOF（已確認不需要）
-- =============================================================
map("i", "<C-u>", "<Esc><C-u>", { desc = "Scroll up (exit insert → normal)" })
map("i", "<C-d>", "<Esc><C-d>", { desc = "Scroll down (exit insert → normal)" })
map("t", "<C-u>", "<C-\\><C-n><C-u>", { desc = "Scroll up (terminal)" })
map("t", "<C-d>", "<C-\\><C-n><C-d>", { desc = "Scroll down (terminal)" })

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
  require("telescope").extensions.live_grep_args.live_grep_args({
    additional_args = function(args)
      return vim.list_extend(args, { "--no-ignore", "--max-filesize", "500K" })
    end,
  })
end, { desc = "telescope live grep args (no gitignore) | 範例: foo -- -t py -g '!test_*'" })

-- Telescope LSP 符號搜尋（類似 VSCode Ctrl+Shift+O）
map("n", "<leader>o", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "LSP 顯示文件符號列表" })
map("n", "<leader>O", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", { desc = "LSP 顯示工作區符號列表" })

-- LSP 跳轉到參考（Python 以 references 取代 implementations）
map("n", "gI", "<cmd>Telescope lsp_references<cr>", { desc = "LSP Find References (類似 Implementation)" })
map("n", "gr", "<cmd>Telescope lsp_references<cr>", { desc = "LSP Find References" })

-- LSP Call Hierarchy（呼叫階層）
-- Pyright 已知 bug：callHierarchy 回傳重複結果，自行去重後送 Telescope
local function call_hierarchy_picker(direction)
  local params = vim.lsp.util.make_position_params()
  vim.lsp.buf_request(0, "textDocument/prepareCallHierarchy", params, function(err, result)
    if err or not result or #result == 0 then
      vim.notify("No call hierarchy item at cursor", vim.log.levels.WARN)
      return
    end
    local method = direction == "incoming"
      and "callHierarchy/incomingCalls"
      or  "callHierarchy/outgoingCalls"
    vim.lsp.buf_request(0, method, { item = result[1] }, function(err2, calls)
      if err2 or not calls then return end
      local seen, entries = {}, {}
      for _, call in ipairs(calls) do
        -- incoming: call.from + call.fromRanges；outgoing: call.to + call.fromRanges
        local target = direction == "incoming" and call.from or call.to
        for _, range in ipairs(call.fromRanges) do
          local key = target.uri .. range.start.line .. range.start.character
          if not seen[key] then
            seen[key] = true
            table.insert(entries, {
              filename = vim.uri_to_fname(target.uri),
              lnum     = range.start.line + 1,
              col      = range.start.character + 1,
              text     = target.name,
            })
          end
        end
      end
      if #entries == 0 then
        vim.notify("No calls found", vim.log.levels.INFO)
        return
      end
      local pickers    = require "telescope.pickers"
      local finders    = require "telescope.finders"
      local conf       = require("telescope.config").values
      local make_entry = require "telescope.make_entry"
      local title = direction == "incoming" and "Incoming Calls" or "Outgoing Calls"
      pickers.new({}, {
        prompt_title = title,
        finder   = finders.new_table { results = entries, entry_maker = make_entry.gen_from_quickfix() },
        sorter   = conf.generic_sorter {},
        previewer = conf.qflist_previewer {},
      }):find()
    end)
  end)
end

map("n", "<leader>ci", function() call_hierarchy_picker("incoming") end, { desc = "LSP Incoming Calls（誰呼叫了我）" })
map("n", "<leader>co", function() call_hierarchy_picker("outgoing") end, { desc = "LSP Outgoing Calls（我呼叫了誰）" })

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
-- DB UI 快捷鍵（SQLite / 資料庫瀏覽器）
-- =============================================================
map("n", "<leader>Dt", "<cmd>DBUIToggle<cr>",          { desc = "DB Toggle UI" })
map("n", "<leader>Da", "<cmd>DBUIAddConnection<cr>",   { desc = "DB Add Connection" })
map("n", "<leader>Df", "<cmd>DBUIFindBuffer<cr>",      { desc = "DB Find Buffer" })

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
-- <A-n>：Alt+數字，適用 normal / insert / terminal mode
-- <D-n>：Cmd+數字，僅限 Mac/Windows Neovide GUI
local function goto_tab(i)
  local bufs = vim.t.bufs
  if not (bufs and bufs[i]) then return end

  local mode = vim.api.nvim_get_mode().mode
  if mode == "i" or mode == "ic" or mode == "ix" then
    -- insert mode：先退出再切，避免新 buffer 也進入 insert mode
    vim.cmd "stopinsert"
  end
  -- terminal mode：直接切即可，Neovim 換 buffer 時自動退出 terminal mode
  require("nvchad.tabufline").goto_buf(bufs[i])
end

-- 綁定 Alt+1~9：normal / insert / terminal 三個 mode 均有效
for i = 1, 9 do
  local desc = "Tab " .. i .. "（Alt）"
  map("n", "<A-" .. i .. ">", function() goto_tab(i) end, { desc = desc })
  map("i", "<A-" .. i .. ">", function() goto_tab(i) end, { desc = desc })
  map("t", "<A-" .. i .. ">", function() goto_tab(i) end, { desc = desc })
  if vim.fn.has("gui_running") == 1 or vim.g.neovide then
    map("n", "<D-" .. i .. ">", function() goto_tab(i) end, { desc = "Tab " .. i .. "（Cmd/Win GUI）" })
  end
end
