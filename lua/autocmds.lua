require "nvchad.autocmds"


-- 讓 log rotate 檔案（如 app.log.1, app.log.2）也被識別為 log filetype
-- 用 autocmd 直接設定，比 vim.filetype.add 更可靠，避免 lazy load chicken-egg 問題
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.log.*", "*.log-*" },
  callback = function()
    vim.bo.filetype = "log"
  end,
})

-- auto-session 還原 session 後，強制統一 foldexpr 為 v:lua.vim.treesitter.foldexpr()
-- 避免舊 session 殘留其他 foldexpr 值（如 nvim_treesitter#foldexpr()）導致 zM 無效
vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.wo[win].foldmethod == "expr" then
          vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        end
      end
    end)
  end,
})

-- =============================================================
-- 修正：還原多 tab 專案時 buffer 全擠到第一個 tab 的問題
-- 成因：mksession 會先 badd 所有 buffer（此時還在 tab 1），再 tabnew 建其他 tab。
--       NvChad tabufline 的 BufAdd autocmd 把每個新 buffer 塞進「當前 tab」的 vim.t.bufs，
--       於是隱藏的 buffer（沒被任何 window 顯示者）都堆進 tab 1，跑到別的 tab 去。
-- 關鍵：mksession 用 `balt`（window 的 alternate buffer，即 `#`）記錄每個 tab 的
--       隱藏成員。所以「某 tab 真正擁有的 buffer」= 該 tab 各 window 顯示的 buffer
--       ＋ 各 window 的 alternate buffer。純掃 window 顯示會漏掉 alternate（隱藏成員），
--       導致隱藏 buffer 被誤判、留在 tab 1 或被丟掉。
-- 修法：還原後依「window 顯示 + window alternate」算出每個 tab 的擁有集合 owned[tab]，
--       再重建 vim.t.bufs：保留本 tab 既有清單中「屬於本 tab」或「不屬於任何其他 tab」者，
--       並補上本 tab 擁有的全部。
--       → 跨 tab 堆積被移到正確的 tab；同 tab 內隱藏 buffer（第二個 :term / 第二個檔）保留。
-- =============================================================
vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    vim.schedule(function()
      local tabs = vim.api.nvim_list_tabpages()

      -- 1) 每個 tab 真正擁有的 buffer：window 顯示者 ＋ 各 window 的 alternate(#)
      local owned = {} -- tab -> { [buf]=true }
      for _, tab in ipairs(tabs) do
        local s = {}
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          s[vim.api.nvim_win_get_buf(win)] = true
          local ok, alt = pcall(vim.api.nvim_win_call, win, function()
            return vim.fn.bufnr("#")
          end)
          if ok and alt and alt > 0 then s[alt] = true end
        end
        owned[tab] = s
      end

      -- 2) 逐 tab 重建
      for _, tab in ipairs(tabs) do
        local seen, bufs = {}, {}
        local function owned_elsewhere(b)
          for _, t in ipairs(tabs) do
            if t ~= tab and owned[t][b] then return true end
          end
          return false
        end
        local function add(b)
          if vim.api.nvim_buf_is_valid(b) and vim.fn.buflisted(b) == 1 and not seen[b] then
            seen[b] = true
            bufs[#bufs + 1] = b
          end
        end
        -- 既有清單：屬於本 tab，或不屬於任何其他 tab（避免把別 tab 的成員留下來堆積）
        for _, b in ipairs(vim.t[tab].bufs or {}) do
          if owned[tab][b] or not owned_elsewhere(b) then add(b) end
        end
        -- 補上本 tab 擁有的全部（含 alternate 的隱藏成員）
        for b in pairs(owned[tab]) do add(b) end
        vim.t[tab].bufs = bufs
      end

      pcall(vim.cmd, "redrawtabline")
    end)
  end,
})

-- =============================================================
-- 動態 Buffer 顯示名稱（configs/bufname.lua）：安裝 + 還原 + 存檔 + 自動標記
-- 概念見 lua/configs/bufname.lua 檔頭。手動指令見 lua/mappings.lua 的 :BufRename。
-- =============================================================

-- 一次性安裝重寫版 style_buf。用 VeryLazy 確保 NvChad ui / tabufline.utils 已載入，
-- 避開 init.lua 的 vim.schedule(mappings) 排序競態。
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    require("configs.bufname").setup()
  end,
})

-- 開檔時還原該檔曾設定的自訂名（持久化於 stdpath('state')）
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(args)
    require("configs.bufname").restore(args.buf)
  end,
})

-- 離開 / 存檔時把自訂名表寫回磁碟（與 auto-session 並存，各存各的）
vim.api.nvim_create_autocmd({ "VimLeavePre", "BufWritePost" }, {
  callback = function()
    require("configs.bufname").save()
  end,
})

-- 自動標記：terminal 跑 Claude Code 時，把該 terminal buffer 顯示名設為 "CC"。
-- 這是「autocmd 自動跟隨狀態」的範本，可自行擴充（LspProgress / BufModifiedSet 等）。
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function(args)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then
        return
      end
      local name = vim.api.nvim_buf_get_name(args.buf):lower()
      if name:match("claude") or name:match("[/\\]cc%f[%A]") then
        require("configs.bufname").set_name(args.buf, "CC")
      end
    end)
  end,
})
