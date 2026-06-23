-- =============================================================
-- Clipboard：跨平台 / 跨 SSH 的「複製到系統剪貼簿」
--
-- 為什麼需要這個模組（WHY）：
--   開發工作流是 tmux + nvim，常常人在本機、nvim 跑在遠端主機（Windows 或
--   Linux）。傳統 `"+y` 依賴遠端有 clipboard provider（win32yank / xclip /
--   pbcopy）；但 SSH 進去的遠端通常沒有圖形剪貼簿，複製的東西根本到不了你
--   面前那台機器的系統剪貼簿。
--
-- 怎麼解（HOW）：OSC52。這是一段終端機跳脫序列（escape sequence）——nvim 把
--   要複製的字串 base64 後，用 OSC52 序列「丟給終端機」，由你本機的終端機
--   （Windows Terminal / iTerm / Blink / Mintty…）攔截並寫進「本機」系統剪貼簿。
--   資料沿著 ssh 既有的 TTY 通道回流，不需要遠端有任何剪貼簿程式，也不需要
--   反向通道或額外 port。Neovim ≥ 0.10 內建 OSC52 provider，直接用。
--
-- 做了什麼（WHAT）：
--   1. 偵測「是否在遠端 / SSH session」。是 → 把 nvim 的 + / * register 接到
--      OSC52，於是 `"+y`、`"+yy`、`<leader>Y` 都會把字推到「本機」剪貼簿。
--      本機（非 SSH）→ 不覆蓋，沿用 nvim 既有的原生剪貼簿（win32yank /
--      pbcopy / wl-copy 等），效能與貼回都最好。
--   2. 提供「不用記」的好按鍵：
--        <leader>Y  整個檔案 → 系統剪貼簿（等同你說的 ctrl-a, ctrl-c）
--        <leader>y  （normal/visual）選取或當前行 → 系統剪貼簿
--      仍保留原生 `"+y`／`"+yy` 給熟手。
--
-- tmux 注意事項（一次性）：OSC52 要能穿過 tmux，tmux.conf 需開：
--        set -g set-clipboard on
--   舊版 tmux（< 3.3）若仍不通，加：set -g allow-passthrough on
--   詳見 docs/CLIPBOARD_OSC52_GUIDE.md。
-- =============================================================

local M = {}

--- 是否處於遠端 / SSH session。
--- SSH_TTY / SSH_CONNECTION 是 sshd 注入的環境變數，最可靠。
--- 沒有圖形剪貼簿工具時也視為「需要 OSC52」。
--- @return boolean
local function is_remote()
  if vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT then
    return true
  end
  return false
end

--- 本機是否有可用的原生剪貼簿工具（有就優先用原生，貼回比較順）。
--- @return boolean
local function has_native_clipboard_tool()
  local tools = { "win32yank.exe", "pbcopy", "wl-copy", "xclip", "xsel", "clip.exe" }
  for _, t in ipairs(tools) do
    if vim.fn.executable(t) == 1 then return true end
  end
  return false
end

function M.setup()
  local use_osc52 = is_remote() or not has_native_clipboard_tool()

  if use_osc52 then
    -- 把系統剪貼簿（+ 與 *）接到 OSC52。
    -- copy 走 OSC52（推到本機剪貼簿）；paste 用 register 內容當 fallback——
    -- OSC52 的「讀回」很多終端機基於安全預設關閉，所以貼上沿用 nvim 自身的
    -- register（在 nvim 內 yank→paste 一律可用；跨程式貼上請用終端機自身的
    -- 貼上鍵 Ctrl+Shift+V / Cmd+V）。
    local osc52 = require("vim.ui.clipboard.osc52")
    vim.g.clipboard = {
      name = "OSC52",
      copy = {
        ["+"] = osc52.copy("+"),
        ["*"] = osc52.copy("*"),
      },
      paste = {
        ["+"] = function() return vim.split(vim.fn.getreg('"'), "\n") end,
        ["*"] = function() return vim.split(vim.fn.getreg('"'), "\n") end,
      },
    }
  end
  -- 本機且有原生工具：不設定 vim.g.clipboard，沿用 nvim 偵測到的原生 provider。

  -- ── 好記的按鍵（不用背 register 語法）────────────────────────
  -- <leader>Y：整個檔案 → 系統剪貼簿（你要的 ctrl-a, ctrl-c 等價）
  vim.keymap.set("n", "<leader>Y", function()
    vim.cmd('normal! gg"+yG')
    vim.notify("整個檔案已複製到系統剪貼簿", vim.log.levels.INFO)
  end, { desc = "Yank 整個檔案 → 系統剪貼簿" })

  -- <leader>y：visual 選取 / normal 當前行 → 系統剪貼簿
  vim.keymap.set("v", "<leader>y", '"+y', { desc = "Yank 選取 → 系統剪貼簿" })
  vim.keymap.set("n", "<leader>y", '"+yy', { desc = "Yank 當前行 → 系統剪貼簿" })

  return use_osc52
end

return M
