return {
  -- 程式碼格式化工具（Formatter）
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- 取消註解可開啟存檔自動格式化
    opts = require "configs.conform",
  },

  -- Telescope 模糊搜尋（含自訂忽略清單與圖片預覽）
  {
    "nvim-telescope/telescope.nvim",
    opts = function()
      return require "configs.telescope"
    end,
    config = function(_, opts)
      require("telescope").setup(opts)
    end,
  },

  -- LSP 設定（語言伺服器協定，提供補全/跳轉/診斷等功能）
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },
  -- Mason：統一管理 LSP server、formatter、linter 的安裝工具
  {
    "williamboman/mason.nvim",
    lazy = false,
    opts = require "configs.mason",  -- 確保安裝：pyright, black, isort, debugpy
  },
  -- Mason 與 lspconfig 的橋接層（自動設定已安裝的 LSP server）
  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup {
        ensure_installed = { "pyright" },  -- 僅列 LSP server（formatter 由 Mason 直接管）
        automatic_installation = false,
        automatic_enable = true,
      }
    end,
  },
  -- Markdown 即時預覽（在瀏覽器中顯示渲染結果）
  {
    "iamcco/markdown-preview.nvim",
    build = "cd app && yarn install",
    ft = {"markdown"},
    cmd = {"MarkdownPreview", "MarkdownPreviewStop"}
  },


  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },

  -- Image preview with custom Telescope + chafa (Windows-compatible)
  -- No additional plugins needed - uses built-in Telescope API

  -- Log file syntax highlighting
  {
    "fei6409/log-highlight.nvim",
    ft = "log", -- Only load for .log files
    config = function()
      require("log-highlight").setup {
        -- Highlight patterns configuration
        pattern = {
          -- Error levels (case insensitive)
          error = "ERROR",
          warning = "WARN",
          info = "INFO",
          debug = "DEBUG",
          trace = "TRACE",
          fatal = "FATAL",
        },
        -- Extension to auto-detect as log files
        extension = "log",
      }
    end,
  },

  -- =============================================================
  -- DAP: Python 調試
  -- =============================================================
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    dependencies = {
      { "mfussenegger/nvim-dap-python", ft = "python" },
      "nvim-neotest/nvim-nio",
      {
        "rcarriga/nvim-dap-ui",
        dependencies = { "nvim-neotest/nvim-nio" },
        config = function()
          require "configs.dap"
        end,
      },
    },
  },

  -- =============================================================
  -- image.nvim: 圖片渲染（僅 Mac/Linux）
  -- =============================================================
  {
    "3rd/image.nvim",
    cond = function() return vim.fn.has("win32") == 0 end,
    lazy = true,
    event = "BufEnter",
    opts = function()
      return {
        backend = (function()
          if vim.fn.executable("ueberzug") == 1 then return "ueberzug" end
          return "kitty"
        end)(),
        integrations = { telescope = { enabled = true } },
        max_width = 100,
        max_height = 40,
      }
    end,
    config = function(_, opts)
      require("image").setup(opts)
    end,
  },

  -- Auto session management
  {
    "rmagatti/auto-session",
    lazy = false, -- Load at startup to restore session
    config = function()
      require("auto-session").setup {
        -- Session save location
        auto_session_root_dir = vim.fn.stdpath("data") .. "/sessions/",

        -- Auto save session on exit
        auto_save_enabled = true,

        -- Auto restore session on startup
        auto_restore_enabled = true,

        -- Suppress session restore prompt
        auto_session_suppress_dirs = {
          "~/",
          "~/Downloads",
          "~/Desktop",
          "/",
        },

        -- Show session restore message
        auto_session_use_git_branch = false,

        -- Log level (error, warn, info, debug)
        log_level = "error",
      }
    end,
  },
}
