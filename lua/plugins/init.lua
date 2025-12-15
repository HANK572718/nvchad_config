return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- Telescope configuration with file ignore patterns
  {
    "nvim-telescope/telescope.nvim",
    opts = function()
      return require "configs.telescope"
    end,
    config = function(_, opts)
      -- Force apply our configuration
      local telescope = require("telescope")
      telescope.setup(opts)

      -- Verify configuration is applied
      vim.schedule(function()
        local config = require("telescope.config").values
        if config.max_results ~= 1000 then
          vim.notify("WARNING: Telescope max_results not applied! Value: " .. tostring(config.max_results), vim.log.levels.WARN)
        else
          vim.notify("✓ Telescope configured: max_results = 1000", vim.log.levels.INFO)
        end
      end)
    end,
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },
  -- add two mason plugin
  {
    "williamboman/mason.nvim",
    opts = require "configs.mason",
  },
  {
    "williamboman/mason-lspconfig.nvim",
    config = function()
      require("mason-lspconfig").setup {
        ensure_installed = {"pyright", "black", "isort" },
	automatic_installation = true,
      }
    end
  },
  -- add markdown preview
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
