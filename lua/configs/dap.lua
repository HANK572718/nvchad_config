-- DAP (Debug Adapter Protocol) 配置
-- 包含：nvim-dap, nvim-dap-python, nvim-dap-ui
-- 支援 Windows / Linux 跨平台，自動偵測專案 .venv

local dap = require("dap")
local dapui = require("dapui")
local dap_python = require("dap-python")

-- ----------------------------------------------------------------
-- 0. 跨平台工具函數
-- ----------------------------------------------------------------

-- vim.fn.has("win32") 在 Windows 32/64 位元都回傳 1，比 os_uname 更可靠
local is_windows = vim.fn.has("win32") == 1

-- 根據平台回傳 venv 內的 python 執行檔路徑
-- @param venv_root string  venv 根目錄（不含結尾 /）
-- @return string  python 執行檔完整路徑
local function venv_python(venv_root)
  if is_windows then
    return venv_root .. "/Scripts/python.exe"
  else
    return venv_root .. "/bin/python"
  end
end

-- 在當前專案目錄下找 .venv 或 venv 的 python
-- 設計為函數參照，讓 nvim-dap 在每次 launch 時才呼叫
-- 這樣切換專案目錄後不需要重啟 nvim
-- @return string  python 執行檔路徑，找不到則回傳系統 python
local function find_project_python()
  local cwd = vim.fn.getcwd()
  for _, name in ipairs({ ".venv", "venv" }) do
    local py = venv_python(cwd .. "/" .. name)
    if vim.fn.filereadable(py) == 1 then
      return py
    end
  end
  -- fallback：系統 python
  local sys = vim.fn.exepath("python3")
  if sys == "" then sys = vim.fn.exepath("python") end
  return sys ~= "" and sys or "python"
end

-- 找有安裝 debugpy 的 python，給 dap_python.setup() 使用
-- 這個 python 負責「啟動 debugpy adapter process」，跟跑程式的 python 不同
-- 優先級：專案 .venv > Mason debugpy venv > 系統 python
-- @return string  python 執行檔路徑
local function find_debugpy_python()
  -- 1. 當前專案 .venv / venv（優先，與 pythonPath 來源一致）
  local proj_py = find_project_python()
  if proj_py ~= "python" and proj_py ~= "" then
    return proj_py
  end

  -- 2. Mason 安裝的 debugpy（專案沒有 .venv 時的穩定備案）
  local mason_py = venv_python(
    vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv"
  )
  if vim.fn.filereadable(mason_py) == 1 then
    return mason_py
  end

  -- 3. 系統 python（最後手段，可能沒有 debugpy）
  local sys = vim.fn.exepath("python3")
  if sys == "" then sys = vim.fn.exepath("python") end
  return sys ~= "" and sys or "python"
end

-- ----------------------------------------------------------------
-- 1. dap-ui 面板設置
-- ----------------------------------------------------------------
dapui.setup({
  icons = { expanded = "", collapsed = "", current_frame = "" },
  mappings = {
    expand = { "<CR>", "<2-LeftMouse>" },
    open = "o",
    remove = "d",
    edit = "e",
    repl = "r",
    toggle = "t",
  },
  floating = {
    border = "single",
    mappings = { close = { "q", "<Esc>" } },
  },
})

-- ----------------------------------------------------------------
-- 2. 自動開關 DAP UI
-- ----------------------------------------------------------------
dap.listeners.before.attach.dapui_config          = function() dapui.open() end
dap.listeners.before.launch.dapui_config          = function() dapui.open() end
dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
dap.listeners.before.event_exited.dapui_config     = function() dapui.close() end

-- ----------------------------------------------------------------
-- 3. Python 適配器（debugpy）
-- ----------------------------------------------------------------
-- setup() 接收「有 debugpy 的 python」，用於啟動 adapter process
-- 此時路徑是固定的（nvim 啟動時決定）
dap_python.setup(find_debugpy_python())
dap_python.test_runner = "pytest"

-- ----------------------------------------------------------------
-- 4. 覆寫 pythonPath：每次 launch 動態抓當前專案 .venv
-- ----------------------------------------------------------------
-- dap_python.setup() 完成後，dap.configurations.python 已填入預設 config
-- 將 pythonPath 改為函數參照（不加括號），nvim-dap 在 launch 時才呼叫
-- 效果：cd 到新專案後直接 F5，自動切換到該專案的 .venv python
for _, config in ipairs(dap.configurations.python or {}) do
  config.pythonPath = find_project_python
end

-- ----------------------------------------------------------------
-- 5. 載入專案自訂 launch.json（若存在 .vscode/launch.json）
-- ----------------------------------------------------------------
-- 優先級高於上方預設 config，讓各專案能自訂 cwd / program / args
-- filetypes 對應表：告知哪些 type 屬於 python adapter
require("dap.ext.vscode").load_launchjs(nil, { python = { "python" } })
