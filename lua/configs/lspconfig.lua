require("nvchad.configs.lspconfig").defaults()

-- Function to find Python interpreter in project root
local function get_python_path(workspace)
  -- Try to find .venv in workspace root (cross-platform)
  local venv_path = vim.fn.has("win32") == 1
      and workspace .. '/.venv/Scripts/python.exe'
      or workspace .. '/.venv/bin/python'
  if vim.fn.filereadable(venv_path) == 1 then
    return venv_path
  end

  -- Fallback to system Python
  if vim.fn.has("win32") == 1 then
    return vim.fn.exepath('python')
  end
  local py3 = vim.fn.exepath('python3')
  return py3 ~= '' and py3 or vim.fn.exepath('python')
end

-- Configure pyright with dynamic Python path detection
-- Using require("lspconfig") API (compatible with nvim 0.10+)
require("lspconfig").pyright.setup {
  root_dir = require("lspconfig.util").root_pattern(
    'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git'
  ),
  settings = {
    python = {
      analysis = {
        autoSearchPaths = true,
        diagnosticMode = "openFilesOnly",
        useLibraryCodeForTypes = true,
        typeCheckingMode = "basic",  -- Options: "off", "basic", "strict"
      },
    },
  },
  on_new_config = function(config, root_dir)
    local python_path = get_python_path(root_dir)
    config.settings.python.pythonPath = python_path
    vim.notify("Pyright using: " .. python_path, vim.log.levels.INFO)
  end,
}

-- read :h vim.lsp.config for changing options of lsp servers 
