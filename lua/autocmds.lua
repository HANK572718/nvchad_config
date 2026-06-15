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
--       於是所有 buffer 都堆進 tab 1，其他 tab 只剩各自 window 顯示的那一個。
-- 修法：還原完成後重建各 tab 的 vim.t.bufs，規則：
--       某 buffer 留在某 tab 的清單中，若它「在該 tab 的 window 中顯示」
--       或「原本就在該 tab 清單裡，且沒有在其他 tab 的 window 中顯示」。
--       → tab 1 的堆積（屬於其他 tab、已在別 tab 顯示的 buffer）被移除；
--         但同 tab 內未顯示的 hidden buffer（如第二個 :term、同 tab 第二個檔）會保留。
--       這解決了純用 window 重建會「丟掉同 tab 隱藏 buffer」的問題
--       （例如一個 tab 開兩個同名 :term pwsh 只剩一個）。
-- =============================================================
vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    vim.schedule(function()
      -- 1) 統計每個 buffer 被「哪些 tab 的 window」顯示
      local shown_in = {} -- buf -> { [tab]=true }
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          local b = vim.api.nvim_win_get_buf(win)
          shown_in[b] = shown_in[b] or {}
          shown_in[b][tab] = true
        end
      end

      -- 2) 逐 tab 重建：留下「在本 tab 顯示」或「原本在本 tab 且未被其他 tab 顯示」的 buffer
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local seen, bufs = {}, {}
        local function consider(b)
          if not (vim.api.nvim_buf_is_valid(b) and vim.fn.buflisted(b) == 1) then return end
          if seen[b] then return end
          local shown_here = shown_in[b] and shown_in[b][tab]
          local shown_elsewhere = false
          if shown_in[b] then
            for t in pairs(shown_in[b]) do
              if t ~= tab then shown_elsewhere = true break end
            end
          end
          if shown_here or not shown_elsewhere then
            seen[b] = true
            bufs[#bufs + 1] = b
          end
        end
        for _, b in ipairs(vim.t[tab].bufs or {}) do consider(b) end
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          consider(vim.api.nvim_win_get_buf(win))
        end
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
