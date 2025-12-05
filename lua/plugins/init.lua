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
}
