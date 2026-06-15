return {
  -- nvim-tree：覆寫 H 同時 toggle dotfiles + gitignore 兩個 filter
  -- 並讓 tree root 跟隨 tab-local cwd（搭配 :tcd 與 project.nvim）
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

      -- ── Tab-local 根目錄整合 ──────────────────────────────
      -- 已關閉自動跟隨 cwd / 自動切 root：避免誤判專案根目錄而自動移動 tree root。
      -- 仍尊重 buffer 所在 cwd（手動 :tcd 後 tree 會反映），但不再「自動」跟著切換。
      default_opts.sync_root_with_cwd = false
      default_opts.respect_buf_cwd    = true
      default_opts.update_focused_file = vim.tbl_deep_extend(
        "force",
        default_opts.update_focused_file or {},
        { enable = true, update_root = false }  -- 只高亮聚焦檔，不自動移動 tree root
      )

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

  -- Treesitter：語法解析器（顏色高亮、程式碼折疊、結構導航）
  -- 注意：必須釘在 master 分支。上游 2025 年把預設分支改為重寫版 main，
  -- main 分支不支援 ensure_installed / highlight.enable 舊 API（會被靜默忽略，
  -- 導致 parser 不安裝、無語法高亮），且需另裝 tree-sitter CLI。
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    init = function()
      -- 雙重保險：把 bootstrap 偵測到的原生編譯器釘進 compilers 第一順位，
      -- 避免 lazy 載入時序讓 $CC 沒被讀到、或 treesitter 預設清單挑到 Cygwin
      -- gcc 產生不相容 parser 導致閃退。bootstrap 已做好平台偵測與零寫死探測。
      -- 詳見 docs/TREESITTER_CYGWIN_CRASH.md 與 lua/configs/bootstrap.lua。
      local ok, bootstrap = pcall(require, "configs.bootstrap")
      if ok and vim.fn.has("win32") == 1 then
        local cc = (bootstrap.last and bootstrap.last.cc) or vim.env.CC
        if cc and vim.fn.executable(cc) == 1 then
          require("nvim-treesitter.install").compilers = { cc }
        end
      end
    end,
    opts = {
      ensure_installed = {
        -- 編輯 nvim 設定本身
        "vim", "lua", "vimdoc", "luadoc", "query",
        -- 主要工作語言
        "python", "bash",
        -- 常用標記/設定檔
        "markdown", "markdown_inline", "json", "jsonc", "yaml", "toml",
        -- Web 相關
        "html", "css", "javascript", "typescript", "tsx", "jsdoc",
        -- 其他
        "dockerfile", "gitignore", "regex",
      },
      auto_install = true,
      highlight = { enable = true },
      indent    = { enable = true },
    },
  },

  -- =============================================================
  -- JavaScript / TypeScript / React 開發工具
  -- =============================================================

  -- TypeScript LSP（比原生 ts_ls 更快，支援 inlay hints / organize imports）
  {
    "pmizio/typescript-tools.nvim",
    ft = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
    opts = {
      settings = {
        tsserver_file_preferences = {
          includeInlayParameterNameHints          = "literals",
          includeInlayVariableTypeHints           = false,
          includeInlayFunctionLikeReturnTypeHints = true,
        },
        expose_as_code_action = { "fix_all", "add_missing_imports", "remove_unused" },
      },
    },
  },

  -- JSX / HTML tag 自動關閉與同步重命名
  {
    "windwp/nvim-ts-autotag",
    ft = {
      "html", "javascript", "javascriptreact",
      "typescript", "typescriptreact",
    },
    opts = {},
  },

  -- JSX 內 gc 注釋使用正確格式（{/* */} 而非 //）
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    event = "VeryLazy",
    opts = { enable_autocmd = false },
  },

  -- package.json 顯示套件版本資訊（<leader>ns 查版本，<leader>nu 更新）
  {
    "vuki656/package-info.nvim",
    ft = "json",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
      require("package-info").setup { package_manager = "npm" }
    end,
  },

  -- 統一 diagnostics / references / quickfix 面板
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = { focus = true },
  },

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

  -- =============================================================
  -- project.nvim: 自動偵測專案根目錄（搭配 nvim-tree sync_root_with_cwd）
  -- 用 :tcd（tab-local）而非 :cd，每個 tab 可獨立掛在不同專案
  -- 開檔/切 buffer 會自動往上找 .git / pyproject.toml 等標記，找到就 tcd
  -- :Telescope projects 可挑歷史專案；選中後對「當前 tab」執行 tcd
  -- =============================================================
  {
    "ahmedkhalf/project.nvim",
    lazy = false,
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("project_nvim").setup {
        -- 只用 pattern 偵測（移除 "lsp"：LSP root_dir 對散檔常誤判，是自動誤切的主因）
        detection_methods = { "pattern" },
        patterns = {
          ".git",
          "pyproject.toml",
          "requirements.txt",
          "package.json",
          "Cargo.toml",
          "Makefile",
          "go.mod",
        },
        scope_chdir   = "tab",   -- 選專案時用 :tcd 而非 :cd（picker 仍 tab-local 切換）
        silent_chdir  = true,    -- 切換不顯示訊息
        -- 關閉「開檔自動偵測 + 切換」：不再自動 tcd，避免誤判專案根目錄。
        -- 手動切換仍可用：<leader>fP（Telescope projects）/ <leader>cd / <leader>tn / :tcd。
        manual_mode   = true,
        show_hidden   = false,
      }
      -- 註冊 Telescope 擴充（pcall 避免 telescope 還沒載入時報錯）
      pcall(require("telescope").load_extension, "projects")
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
