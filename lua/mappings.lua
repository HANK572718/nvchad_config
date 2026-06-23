-- 載入 NvChad 預設按鍵映射
require "nvchad.mappings"

local map = vim.keymap.set

-- 在 Normal 模式下，按 ; 直接進入命令列（省去按 Shift+:）
map("n", ";", ":", { desc = "CMD enter command mode" })
-- 在 Insert 模式下，按 jk 快速回到 Normal 模式（替代 <ESC>）
map("i", "jk", "<ESC>")

-- =============================================================
-- 統一「往回刪一個詞」的按鍵（跨平台）
-- 問題：Windows 習慣 Ctrl+Backspace 刪一個詞，Linux 桌面慣用 Alt+Backspace。
--       而且不同終端機對這兩個 chord 送出的位元組不一致：
--         - 多數終端機把 Ctrl+Backspace 送成 <C-h>（0x08），少數送 <C-BS>
--         - Alt+Backspace 通常送 <M-BS>（ESC + DEL）
--       導致「同一個動作，不同平台 / 終端機要按不同鍵、甚至沒反應」。
-- 對策：在 nvim 層把所有變體都對到同一個動作 = <C-w>（insert mode 刪前一詞）。
--       這樣不論本機是 Windows 還是 Linux、不論用哪個終端機，Ctrl+Backspace
--       與 Alt+Backspace 都能「往回刪一個詞」，行為統一成 Linux 習慣。
--       command-line mode 也一併處理（cmap），搜尋 / : 指令列同樣適用。
-- =============================================================
for _, key in ipairs({ "<C-BS>", "<C-h>", "<M-BS>" }) do
  map("i", key, "<C-w>", { desc = "Insert: 往回刪一個詞（跨平台統一）" })
  map("c", key, "<C-w>", { desc = "Cmdline: 往回刪一個詞（跨平台統一）" })
end

-- =============================================================
-- 覆蓋 NvChad 預設的 terminal <C-x>（原綁定為「跳出 terminal 模式」）
-- 改為「透傳 Ctrl+X 給終端內程式」，讓 Claude Code 等程式能收到 <C-x>
-- 跳出 terminal 模式請改用內建的 <C-\><C-n>
-- =============================================================
map("t", "<C-x>", "<C-v><C-x>", { desc = "Send Ctrl-X to terminal program (e.g. Claude Code)" })

-- Alt+i：tab-local 浮動終端，覆蓋 NvChad 預設的全域 "floatTerm"
-- 原理：id 加入 tabpage handle，讓每個 tab 在 g.nvchad_terms 有獨立 entry
map({ "n", "t" }, "<A-i>", function()
  require("nvchad.term").toggle {
    pos = "float",
    id  = "floatTerm_" .. vim.api.nvim_get_current_tabpage(),
  }
end, { desc = "terminal toggle float (tab-local)" })

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

-- =============================================================
-- 專案／Tab-local 根目錄
-- <leader>fP : Telescope projects（從歷史專案挑，套用 :tcd 到當前 tab）
-- <leader>cd : 手動輸入路徑，對當前 tab 執行 :tcd
-- <leader>tn : 開新 tab + 輸入路徑 :tcd（每個 tab 一個專案根）
-- :tcd <path> 也可直接用，nvim-tree / terminal 會自動跟隨
-- =============================================================
map("n", "<leader>fP", "<cmd>Telescope projects<cr>", { desc = "Telescope 專案列表（tab-local cd）" })

-- 設定 / 清除當前 tabpage 的自訂標籤（顯示在右上角 tab 列）
-- 空白輸入 = 清除自訂標籤，恢復顯示 cwd basename
map("n", "<leader>tR", function()
  local ok, cur = pcall(vim.api.nvim_tabpage_get_var, 0, "tab_label")
  vim.ui.input({ prompt = "Tab label (空=恢復 cwd): ", default = ok and cur or "" }, function(input)
    if input == nil then return end
    if input == "" then
      pcall(vim.api.nvim_tabpage_del_var, 0, "tab_label")
    else
      vim.api.nvim_tabpage_set_var(0, "tab_label", input)
    end
    vim.cmd "redrawtabline"
  end)
end, { desc = "Tab：設定自訂標籤（空=清除）" })

map("n", "<leader>cd", function()
  vim.ui.input({ prompt = "tcd → ", default = vim.fn.getcwd(-1, 0), completion = "dir" }, function(input)
    if input and input ~= "" then
      vim.cmd("tcd " .. vim.fn.fnameescape(vim.fn.expand(input)))
      vim.notify("Tab cwd → " .. vim.fn.getcwd(-1, 0))
    end
  end)
end, { desc = "Tab-local :tcd（輸入路徑）" })

map("n", "<leader>tn", function()
  vim.ui.input({ prompt = "新 tab tcd → ", completion = "dir" }, function(input)
    if input and input ~= "" then
      vim.cmd "tabnew"
      vim.cmd("tcd " .. vim.fn.fnameescape(vim.fn.expand(input)))
      vim.notify("New tab @ " .. vim.fn.getcwd(-1, 0))
    end
  end)
end, { desc = "新 tab + tcd 到指定專案" })

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

-- =============================================================
-- :BufRename — 自訂當前 buffer 在頂部 tabufline 的顯示名（不改真實檔名）
-- 有參數：直接設定；無參數：跳出輸入框（預填目前名稱，空輸入=清除）
-- 核心邏輯與持久化見 lua/configs/bufname.lua
-- =============================================================
vim.api.nvim_create_user_command("BufRename", function(opts)
  local bufname = require "configs.bufname"
  if opts.args ~= "" then
    bufname.set_name(0, opts.args)
  else
    vim.ui.input({ prompt = "Buffer 顯示名 (空=清除): ", default = bufname.get_name(0) or "" }, function(input)
      if input == nil then return end
      if input == "" then
        bufname.clear_name(0)
      else
        bufname.set_name(0, input)
      end
    end)
  end
end, { nargs = "?", desc = "Buffer：設定 tabufline 自訂顯示名（空=清除）" })

-- <leader>br：跳出輸入框設定當前 buffer 顯示名（仿 <leader>tR tab-label 流程）
map("n", "<leader>br", "<cmd>BufRename<cr>", { desc = "Buffer: set custom display name" })

-- 圖片瀏覽器：用 Telescope + chafa 預覽圖片（<leader>fp）
map("n", "<leader>fp", function()
  require("configs.image_preview").find_images()
end, { desc = "瀏覽圖片（Image Browser）" })

-- Web 多媒體瀏覽器：filebrowser + 瀏覽器（縮圖牆/圖片/影片/PDF）
-- <leader>fs：服務當前 tab cwd       <leader>fS：輸入路徑
-- 再按一次會停舊的、換新資料夾；離開 nvim 自動收掉。:WebMediaStop 手動停止
map("n", "<leader>fs", function()
  require("configs.web_media").serve_cwd()
end, { desc = "Web 瀏覽多媒體（當前資料夾）" })

map("n", "<leader>fS", function()
  require("configs.web_media").serve_prompt()
end, { desc = "Web 瀏覽多媒體（指定資料夾）" })

vim.api.nvim_create_user_command("WebMediaStop", function()
  require("configs.web_media").stop()
end, { desc = "停止 web media server" })

-- =============================================================
-- SSH 設定精靈（TUI）：:SshSetup 或 <leader>Sk
-- 金鑰產生 / ~/.ssh/config 別名 / 部署公鑰到對方 / 測試免密碼連線。
-- 不用記任何參數，全程選單 + 問答。見 lua/configs/ssh_tui.lua 與
-- docs/SSH_CONFIG_GUIDE.md。
-- =============================================================
require("configs.ssh_tui").setup()

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

-- 移動 buffer 順序（tabufline 上的位置）
-- <A-S-h>/<A-S-l>：Alt+Shift+h/l 左右移動目前 buffer（<A-h> 已被 NvChad 水平 terminal 佔用）
map("n", "<A-S-h>", function() require("nvchad.tabufline").move_buf(-1) end, { desc = "Buffer 左移" })
map("n", "<A-S-l>", function() require("nvchad.tabufline").move_buf(1) end,  { desc = "Buffer 右移" })

-- =============================================================
-- :bd / :bd! / <A-w> 改走自製 close_current_buffer，避免兩個問題：
--   (1) 原生 :bd 會「拋棄」顯示該 buffer 的 window；若那是 tab 唯一的 window，
--       整個 tab 就被關掉。
--   (2) <A-w> 需要按兩次：NvChad close_buffer() 的 bang 參數其實不存在
--       （簽名只有 close_buffer(bufnr)），所以 :Bd! 之前根本沒 force——遇到
--       未存檔 / terminal buffer 會走 `confirm bd` 卡在提示，第一次按等於沒關，
--       要再按一次才生效。同時關掉最後一個 buffer 時它會 enew 一個 No Name，
--       那個 No Name 因為「正顯示在 window」躲過清理，看起來也像沒關乾淨。
--
-- 對策：自己處理。先把當前 window 切到 vim.t.bufs 的鄰居（多個 buffer 時，
--       絕不 enew →不再冒出多餘 No Name）；只有真的關到最後一個 buffer 才
--       enew（此時 window 一定要顯示點東西，No Name 無法避免，屬正常）。
--       接著用 nvim_buf_delete 帶 force=bang 刪掉目標 buffer：force 時直接丟棄
--       未存檔變更、不彈 confirm，所以一次到位。最後 wipe_empty_noname 收掉
--       任何沒在顯示的空 No Name 殘留。
-- =============================================================

-- 清掉「空的 No Name」buffer：無檔名、未修改、空內容、且沒有顯示在任何 window。
-- 「沒在顯示」這個條件刻意保留——正在看的空 buffer（含關到最後一個時必要的
-- enew）不該被砍掉，否則 window 會沒東西可顯示。
local function wipe_empty_noname()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf)
      and vim.fn.buflisted(buf) == 1
      and vim.api.nvim_buf_get_name(buf) == ""
      and vim.bo[buf].buftype == ""                        -- 排除 terminal / quickfix 等特殊 buffer
      and not vim.bo[buf].modified
      and vim.fn.bufwinid(buf) == -1                       -- 沒有顯示在任何 window
      and vim.api.nvim_buf_line_count(buf) == 1
      and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""  -- 內容為空
    then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- 關閉指定（預設當前）buffer，保留 window/tab。force=true 時等同 :bd!（丟棄未存檔）。
local function close_current_buffer(force)
  local target = vim.api.nvim_get_current_buf()
  local bufs = vim.t.bufs or {}

  -- 找目標在 tabufline 清單中的位置
  local idx
  for i, b in ipairs(bufs) do
    if b == target then idx = i break end
  end

  -- 先把當前 window 帶離 target：多個 buffer →切到鄰居（不 enew）；
  -- 只剩這一個（或不在清單內）→ enew 一個空 buffer 撐住 window。
  if idx and #bufs > 1 then
    local neighbor = bufs[idx == #bufs and idx - 1 or idx + 1]
    pcall(vim.cmd, "buffer " .. neighbor)
  else
    pcall(vim.cmd, "enew")
  end

  -- 真正刪掉 target。force 時 nvim_buf_delete 不彈 confirm、直接丟棄變更。
  if vim.api.nvim_buf_is_valid(target) then
    pcall(vim.api.nvim_buf_delete, target, { force = force == true, unload = false })
  end

  wipe_empty_noname()
  pcall(vim.cmd, "redrawtabline")
end

vim.api.nvim_create_user_command("Bd", function(opts)
  close_current_buffer(opts.bang)
end, { bang = true, desc = "Buffer 關閉（保留 window/tab；! = 強制不儲存，順手清空 No Name）" })

-- 只在「整行剛好是 bd / bd!」時改寫，:bdelete foo / :bd 3 等仍走原生
vim.cmd [[
  cnoreabbrev <expr> bd  (getcmdtype() ==# ':' && getcmdline() ==# 'bd')  ? 'Bd'  : 'bd'
  cnoreabbrev <expr> bd! (getcmdtype() ==# ':' && getcmdline() ==# 'bd!') ? 'Bd!' : 'bd!'
]]

-- <A-w>：等同 :bd! —— 強制關閉目前 buffer、不儲存（未存檔的變更直接丟棄）。
-- 一次到位，不再需要按兩次。normal / insert / terminal 三個 mode 均有效。
do
  local force_close = function() close_current_buffer(true) end
  map("n", "<A-w>", force_close, { desc = "Buffer 強制關閉（不儲存，等同 :bd!）" })
  map("i", "<A-w>", function() vim.cmd("stopinsert"); force_close() end, { desc = "Buffer 強制關閉（不儲存，等同 :bd!）" })
  map("t", "<A-w>", function() vim.cmd("stopinsert"); force_close() end, { desc = "Buffer 強制關閉（不儲存，等同 :bd!）" })
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

-- =============================================================
-- Conform：手動格式化
-- =============================================================
map({ "n", "v" }, "<leader>fm", function()
  require("conform").format { async = true, lsp_fallback = true }
end, { desc = "Format file (conform)" })

-- =============================================================
-- Trouble：Diagnostics 面板
-- =============================================================
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",          { desc = "Trouble: workspace diagnostics" })
map("n", "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Trouble: buffer diagnostics" })
map("n", "<leader>xq", "<cmd>Trouble qflist toggle<cr>",               { desc = "Trouble: quickfix list" })
map("n", "<leader>xl", "<cmd>Trouble loclist toggle<cr>",              { desc = "Trouble: location list" })

-- =============================================================
-- TypeScript Tools：TS 特定操作（僅在 JS/TS 檔案生效）
-- =============================================================
map("n", "<leader>to", "<cmd>TSToolsOrganizeImports<cr>",    { desc = "TS: organize imports" })
map("n", "<leader>ta", "<cmd>TSToolsAddMissingImports<cr>",  { desc = "TS: add missing imports" })
map("n", "<leader>tu", "<cmd>TSToolsRemoveUnusedImports<cr>", { desc = "TS: remove unused imports" })
map("n", "<leader>tf", "<cmd>TSToolsFixAll<cr>",             { desc = "TS: fix all" })
map("n", "<leader>tr", "<cmd>TSToolsRenameFile<cr>",         { desc = "TS: rename file (update imports)" })

-- =============================================================
-- Package Info：package.json 套件資訊（在 package.json 內使用）
-- =============================================================
map("n", "<leader>ns", function() require("package-info").show() end,           { desc = "npm: show package versions" })
map("n", "<leader>nh", function() require("package-info").hide() end,           { desc = "npm: hide package versions" })
map("n", "<leader>nu", function() require("package-info").update() end,         { desc = "npm: update package" })
map("n", "<leader>nd", function() require("package-info").delete() end,         { desc = "npm: delete package" })
map("n", "<leader>ni", function() require("package-info").install() end,        { desc = "npm: install new package" })
map("n", "<leader>nv", function() require("package-info").change_version() end, { desc = "npm: change package version" })
