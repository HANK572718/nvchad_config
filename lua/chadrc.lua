-- NvChad UI 設定檔，結構需與 nvconfig.lua 相同
-- 參考：https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "chadracula",  -- 目前使用的主題（暗色風格）

	-- 覆蓋特定語法高亮（範例：讓註解顯示為斜體）
	-- hl_override = {
	-- 	Comment = { italic = true },
	-- 	["@comment"] = { italic = true },
	-- },
}

-- 啟動時顯示 NvChad 儀表板（Dashboard）
-- M.nvdash = { load_on_startup = true }

-- 自訂 tabufline（頂部 buffer 列）行為
-- M.ui = {
--       tabufline = {
--          lazyload = false  -- 設為 false 可立即載入 tabufline
--      }
-- }

-- ── Tabufline：動態縮減 tab 寬度，讓所有 buffer 都能顯示 ──────────
M.ui = {
  tabufline = {
    modules = {
      buffers = function()
        local api = vim.api
        local utils = require "nvchad.tabufline.utils"

        -- 清除無效 buffer
        vim.t.bufs = vim.tbl_filter(api.nvim_buf_is_valid, vim.t.bufs)
        local bufs = vim.t.bufs

        if #bufs == 0 then
          return utils.txt("%=", "Fill")
        end

        -- 計算 NvimTree 佔用寬度
        local tree_w = 0
        for _, win in pairs(api.nvim_tabpage_list_wins(0)) do
          if vim.bo[api.nvim_win_get_buf(win)].ft == "NvimTree" then
            tree_w = api.nvim_win_get_width(win) + 1  -- +1 for separator
            break
          end
        end

        -- 計算 vim tabpages 佔用寬度（>1 個 tabpage 才顯示）
        local tabpages_w = 0
        if vim.fn.tabpagenr "$" > 1 then
          tabpages_w = vim.fn.tabpagenr "$" * 4 + 14
        end

        -- btns 模組：toggle_theme(4) + close_all(4) = 8 欄
        local btns_w = 8

        local space = vim.o.columns - tree_w - tabpages_w - btns_w

        -- 動態寬度：每個 tab 最小 10、最大 21（NvChad 預設值）
        local MIN_W, MAX_W = 10, 21
        local w = math.min(MAX_W, math.max(MIN_W, math.floor(space / #bufs)))

        local result = {}
        for i, nr in ipairs(bufs) do
          table.insert(result, utils.style_buf(nr, i, w))
        end

        return table.concat(result) .. utils.txt("%=", "Fill")
      end,
    },
  },

  statusline = {
    modules = {

      -- ── Mode：永不隱藏，顯示全名（最高優先） ──────────────────────
      mode = function()
        local utils = require "nvchad.stl.utils"
        if not utils.is_activewin() then return "" end

        local full_modes = {
          ["n"]    = { "NORMAL",     "Normal"    },
          ["no"]   = { "NORMAL",     "Normal"    },
          ["nov"]  = { "NORMAL",     "Normal"    },
          ["noV"]  = { "NORMAL",     "Normal"    },
          ["\22o"] = { "NORMAL",     "Normal"    },
          ["niI"]  = { "NORMAL",     "Normal"    },
          ["niR"]  = { "NORMAL",     "Normal"    },
          ["niV"]  = { "NORMAL",     "Normal"    },
          ["nt"]   = { "N-TERMINAL", "NTerminal" },
          ["ntT"]  = { "N-TERMINAL", "NTerminal" },
          ["v"]    = { "VISUAL",     "Visual"    },
          ["vs"]   = { "VISUAL",     "Visual"    },
          ["V"]    = { "V-LINE",     "Visual"    },
          ["Vs"]   = { "V-LINE",     "Visual"    },
          ["\22"]  = { "V-BLOCK",    "Visual"    },
          ["i"]    = { "INSERT",     "Insert"    },
          ["ic"]   = { "INSERT",     "Insert"    },
          ["ix"]   = { "INSERT",     "Insert"    },
          ["t"]    = { "TERMINAL",   "Terminal"  },
          ["R"]    = { "REPLACE",    "Replace"   },
          ["Rc"]   = { "REPLACE",    "Replace"   },
          ["Rx"]   = { "REPLACE",    "Replace"   },
          ["Rv"]   = { "V-REPLACE",  "Replace"   },
          ["Rvc"]  = { "V-REPLACE",  "Replace"   },
          ["Rvx"]  = { "V-REPLACE",  "Replace"   },
          ["s"]    = { "SELECT",     "Select"    },
          ["S"]    = { "S-LINE",     "Select"    },
          ["\19"]  = { "S-BLOCK",    "Select"    },
          ["c"]    = { "COMMAND",    "Command"   },
          ["cv"]   = { "COMMAND",    "Command"   },
          ["ce"]   = { "COMMAND",    "Command"   },
          ["cr"]   = { "COMMAND",    "Command"   },
          ["r"]    = { "PROMPT",     "Confirm"   },
          ["rm"]   = { "MORE",       "Confirm"   },
          ["r?"]   = { "CONFIRM",    "Confirm"   },
          ["x"]    = { "CONFIRM",    "Confirm"   },
          ["!"]    = { "SHELL",      "Terminal"  },
        }

        local cfg = require("nvconfig").ui.statusline
        local sep_style = cfg.separator_style
        local seps = (type(sep_style) == "table" and sep_style) or utils.separators[sep_style]
        local sep_r = seps["right"]

        local m = vim.api.nvim_get_mode().mode
        local info = full_modes[m] or { "NORMAL", "Normal" }
        -- %< 告訴 Vim：若 statusline 太長，從這裡之後開始截，mode 永遠保留
        return "%#St_" .. info[2] .. "Mode#  " .. info[1]
          .. "%#St_" .. info[2] .. "ModeSep#" .. sep_r
          .. "%#ST_EmptySpace#" .. sep_r .. "%<"
      end,

      -- ── File：超過 18 字元截斷，保留副檔名 ───────────────────────
      file = function()
        local utils = require "nvchad.stl.utils"
        local cfg = require("nvconfig").ui.statusline
        local sep_style = cfg.separator_style
        local seps = (type(sep_style) == "table" and sep_style) or utils.separators[sep_style]
        local sep_r = seps["right"]

        local x = utils.file()
        local icon, name = x[1], x[2]
        local max_len = 18

        if #name > max_len then
          local ext = name:match "%.([^%.]+)$"
          if ext and (#ext + 5) <= max_len then
            name = name:sub(1, max_len - #ext - 2) .. "…." .. ext
          else
            name = name:sub(1, max_len - 1) .. "…"
          end
        end

        local tail = (sep_style == "default" and " " or "")
        return "%#St_file# " .. icon .. " " .. name .. tail .. "%#St_file_sep#" .. sep_r
      end,

      -- ── Git：col < 95 時隱藏（低優先） ────────────────────────────
      git = function()
        if vim.o.columns < 95 then return "" end
        return "%#St_gitIcons#" .. require("nvchad.stl.utils").git()
      end,

      -- ── Diagnostics：col < 115 時隱藏（最低優先） ─────────────────
      diagnostics = function()
        if vim.o.columns < 115 then return "" end
        return require("nvchad.stl.utils").diagnostics()
      end,

      -- ── CWD：col < 80 時隱藏（中優先） ───────────────────────────
      cwd = function()
        if vim.o.columns < 80 then return "" end
        local utils = require "nvchad.stl.utils"
        local cfg = require("nvconfig").ui.statusline
        local sep_style = cfg.separator_style
        local seps = (type(sep_style) == "table" and sep_style) or utils.separators[sep_style]
        local sep_l = seps["left"]
        local name = vim.uv.cwd()
        name = "%#St_cwd_text#" .. " " .. (name:match "([^/\\]+)[/\\]*$" or name) .. " "
        return "%#St_cwd_sep#" .. sep_l .. "%#St_cwd_icon#" .. "󰉋 " .. name
      end,

    }
  }
}

-- 懸浮終端機視窗大小設定（預設 0.5 x 0.4 太小）
M.term = {
  float = {
    relative = "editor",
    row = 0.1,
    col = 0.1,
    width = 0.8,
    height = 0.7,
    border = "single",
  },
}

return M
