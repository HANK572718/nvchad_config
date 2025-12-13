require("nvchad.configs.lspconfig").defaults()

-- Function to find Python interpreter in project root
local function get_python_path(workspace)
  -- Try to find .venv in workspace root
  local venv_path = workspace .. '/.venv/Scripts/python.exe'
  if vim.fn.filereadable(venv_path) == 1 then
    return venv_path
  end

  -- Fallback to system Python
  return vim.fn.exepath('python')
end

-- Configure pyright with dynamic Python path detection
vim.lsp.config.pyright = {
  root_markers = {
    'pyproject.toml',
    'setup.py',
    'setup.cfg',
    'requirements.txt',
    'Pipfile',
    '.git',
  },
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
    -- Dynamically set Python path based on project root
    local python_path = get_python_path(root_dir)
    config.settings.python.pythonPath = python_path

    -- Optional: Print detected Python path for debugging
    vim.notify("Pyright using: " .. python_path, vim.log.levels.INFO)
  end,
}

-- Configure Jedi Language Server for better implementation support
vim.lsp.config.jedi_language_server = {
  root_markers = {
    'pyproject.toml',
    'setup.py',
    'setup.cfg',
    'requirements.txt',
    'Pipfile',
    '.git',
  },
  on_new_config = function(config, root_dir)
    -- Use the same Python path detection logic as pyright
    local python_path = get_python_path(root_dir)
    config.init_options = {
      workspace = {
        environmentPath = python_path
      }
    }
    -- Optional: Print detected Python path for debugging
    vim.notify("Jedi using: " .. python_path, vim.log.levels.INFO)
  end,
}

local servers = { "pyright", "jedi_language_server" }  -- Enable both LSP servers
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers 
