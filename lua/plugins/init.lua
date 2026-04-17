return {
  -- nvim-tree：覆寫 H 同時 toggle dotfiles + gitignore 兩個 filter
  {
    "nvim-tree/nvim-tree.lua",
    opts = function()
      local default_opts = require("nvchad.configs.nvimtree")
      local api = require("nvim-tree.api")

      local original_on_attach = default_opts.on_attach

      default_opts.on_attach = function(bufnr)
        -- 載入 NvChad 預設所有按鍵
        if original_on_attach then
          original_on_attach(bufnr)
        else
          api.config.mappings.default_on_attach(bufnr)
        end

        -- 覆寫 H：切換 gitignore filter（.venv / logs 都是 gitignored，非 dotfiles）
        -- NvChad 預設 dotfiles=false 已顯示，不需額外 toggle_hidden_filter
        vim.keymap.set("n", "H", function()
          api.tree.toggle_gitignore_filter()
        end, { buffer = bufnr, noremap = true, desc = "Toggle gitignore filter" })
      end

      return default_opts
    end,
  },

  -- 程式碼格式化工具（Formatter）
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- 取消註解可開啟存檔自動格式化
    opts = require "configs.conform",
  },

  -- Telescope 模糊搜尋（含自訂忽略清單與圖片預覽）
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-telescope/telescope-live-grep-args.nvim",
    },
    opts = function()
      return require "configs.telescope"
    end,
    config = function(_, opts)
      local telescope = require "telescope"
      telescope.setup(opts)
      telescope.load_extension "live_grep_args"
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
        automatic_enable = false,  -- 由 configs/lspconfig.lua 統一用 vim.lsp.enable() 管理
      }
    end,
  },
  -- Markdown 即時預覽（在瀏覽器中顯示渲染結果）
  -- SSH 使用方式：執行 :MarkdownPreview，從 cmdline 複製 URL，在 SSH client 瀏覽器開啟
  {
    "iamcco/markdown-preview.nvim",
    build = "cd app && yarn install",
    ft = { "markdown" },
    cmd = { "MarkdownPreview", "MarkdownPreviewStop" },
    init = function()
      vim.g.mkdp_open_to_the_world = 1  -- bind 0.0.0.0，讓 SSH client 可從外部 IP 存取
      vim.g.mkdp_echo_preview_url  = 1  -- 在 cmdline 顯示完整 URL（含 port）
      vim.g.mkdp_browser           = "" -- 不嘗試在 Windows 本機開瀏覽器
      vim.g.mkdp_port              = "8090" -- 固定 port，方便記憶或設 SSH tunnel
    end,
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

  -- =============================================================
  -- vim-dadbod: 資料庫瀏覽器（支援 SQLite）
  -- 指令: :DBUI 開啟側邊欄, :DB sqlite:path/to/file.db
  -- =============================================================
  {
    "tpope/vim-dadbod",
    lazy = true,
    cmd = { "DB", "DBUI", "DBUIToggle", "DBUIAddConnection" },
  },
  {
    "kristijanhusak/vim-dadbod-ui",
    lazy = true,
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    dependencies = { "tpope/vim-dadbod" },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_win_position = "left"
      vim.g.db_ui_winwidth = 35
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/dadbod_ui"
    end,
  },
  {
    "kristijanhusak/vim-dadbod-completion",
    lazy = true,
    ft = { "sql", "mysql", "plsql" },
    dependencies = { "tpope/vim-dadbod" },
    config = function()
      -- 整合 nvim-cmp 補全
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          require("cmp").setup.buffer {
            sources = { { name = "vim-dadbod-completion" } },
          }
        end,
      })
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
