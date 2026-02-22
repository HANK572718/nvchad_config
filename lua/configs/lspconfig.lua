-- 載入 NvChad 預設的 LSP 設定
require("nvchad.configs.lspconfig").defaults()

-- 偵測專案所使用的 Python 路徑（虛擬環境優先，找不到才用系統 Python）
local function get_python_path(workspace)
  -- 優先找專案根目錄下的 .venv（跨平台路徑）
  local venv_path = vim.fn.has("win32") == 1
      and workspace .. '/.venv/Scripts/python.exe'
      or workspace .. '/.venv/bin/python'
  if vim.fn.filereadable(venv_path) == 1 then
    return venv_path
  end

  -- 找不到 .venv 時，回退到系統 Python
  if vim.fn.has("win32") == 1 then
    return vim.fn.exepath('python')
  end
  local py3 = vim.fn.exepath('python3')
  return py3 ~= '' and py3 or vim.fn.exepath('python')
end

-- 設定 Pyright LSP（Python 語言伺服器）
-- 使用 nvim 0.11+ 的原生 vim.lsp.config API
vim.lsp.config.pyright = {
  -- 判斷專案根目錄的依據（找到任一檔案即視為根目錄）
  root_markers = {
    'pyproject.toml', 'setup.py', 'setup.cfg',
    'requirements.txt', 'Pipfile', '.git',
  },
  settings = {
    python = {
      analysis = {
        autoSearchPaths = true,          -- 自動搜尋模組路徑
        diagnosticMode = "openFilesOnly", -- 只診斷已開啟的檔案（節省資源）
        useLibraryCodeForTypes = true,   -- 使用套件原始碼推斷型別
        typeCheckingMode = "basic",      -- 基本型別檢查（不過於嚴格）
      },
    },
  },
  -- 每次新增設定時動態注入 Python 路徑，並顯示通知
  on_new_config = function(config, root_dir)
    local python_path = get_python_path(root_dir)
    config.settings.python.pythonPath = python_path
    vim.notify("Pyright using: " .. python_path, vim.log.levels.INFO)
  end,
}

-- 啟用 Pyright
vim.lsp.enable("pyright")

-- 更多 LSP 選項請參考：:h vim.lsp.config
