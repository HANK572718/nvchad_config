require("nvchad.configs.lspconfig").defaults()

-- 配置 pyright 的 Python 環境
vim.lsp.config.pyright = {
  settings = {
    python = {
      pythonPath = vim.fn.exepath("python"),  -- 自動偵測當前環境的 Python
      analysis = {
        autoSearchPaths = true,
        diagnosticMode = "openFilesOnly",
        useLibraryCodeForTypes = true,
        typeCheckingMode = "basic",  -- 可選: "off", "basic", "strict"
      },
    },
  },
}

local servers = { "pyright" }  -- 只啟用已安裝的 pyright
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers 
