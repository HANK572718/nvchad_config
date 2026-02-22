-- DAP (Debug Adapter Protocol) 配置
-- 包含：nvim-dap, nvim-dap-python, nvim-dap-ui
-- 調試啟動/結束時自動開關 UI 面板

local dap = require("dap")
local dapui = require("dapui")
local dap_python = require("dap-python")

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
  layouts = {
    {
      -- 左側欄：變量範圍 + 斷點 + 調用棧 + 監視
      elements = {
        { id = "scopes",      size = 0.30 },
        { id = "breakpoints", size = 0.20 },
        { id = "stacks",      size = 0.30 },
        { id = "watches",     size = 0.20 },
      },
      size = 40,
      position = "left",
    },
    {
      -- 底部欄：REPL + 控制台
      elements = {
        { id = "repl",    size = 0.5 },
        { id = "console", size = 0.5 },
      },
      size = 10,
      position = "bottom",
    },
  },
  floating = {
    border = "single",
    mappings = { close = { "q", "<Esc>" } },
  },
})

-- ----------------------------------------------------------------
-- 2. 自動開關 DAP UI
-- ----------------------------------------------------------------
dap.listeners.before.attach.dapui_config    = function() dapui.open() end
dap.listeners.before.launch.dapui_config    = function() dapui.open() end
dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
dap.listeners.before.event_exited.dapui_config     = function() dapui.close() end

-- ----------------------------------------------------------------
-- 3. Python 適配器（debugpy via Mason）
-- ----------------------------------------------------------------
local mason_packages = vim.fn.stdpath("data") .. "/mason/packages"
local debugpy_python = mason_packages .. "/debugpy/venv/bin/python"

-- 找不到 Mason 的 debugpy 時回退到系統 Python
if vim.fn.filereadable(debugpy_python) == 0 then
  debugpy_python = vim.fn.exepath("python3")
  if debugpy_python == "" then
    debugpy_python = vim.fn.exepath("python")
  end
end

dap_python.setup(debugpy_python)
dap_python.test_runner = "pytest"
