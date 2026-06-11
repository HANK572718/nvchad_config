-- =============================================================
-- Web Media Browser
-- 用 `filebrowser` 把資料夾丟到瀏覽器瀏覽多媒體（圖片 / 影片 / PDF /
-- 音訊），格狀縮圖牆 + 內建 viewer + 搜尋，由瀏覽器原生處理顯示與
-- 播放，不依賴終端機 graphics protocol，SSH 遠端也適用。
--
-- 對照 image_preview.lua（Telescope + chafa，終端內顯示圖片）：
--   image_preview = 終端內快速翻圖
--   web_media     = 瀏覽器看完整多媒體（含影片/互動）
--
-- filebrowser binary：優先 PATH，退回 ~/.local/bin/filebrowser。
-- 設定資料庫固定於 ~/.config/filebrowser/filebrowser.db，首次使用會
-- 自動建立（auth=noauth 免登入 + 一個 admin user）；root / port 每次
-- 啟動由旗標指定。綁 0.0.0.0（區網可連），noauth 無認證，不信任的
-- 網路請用完即停（:WebMediaStop，離開 nvim 也會自動收掉）。
-- =============================================================

local M = {}

-- filebrowser 設定資料庫（固定位置；首次自動建立）
local DB = vim.fn.expand("~/.config/filebrowser/filebrowser.db")

-- 單一 server 狀態（同時只跑一個，換資料夾會先停舊的）
local state = { job = nil, port = nil, root = nil }

--- 確保 filebrowser 設定資料庫存在；不存在則建立。
--- 設成 auth=noauth（免登入），並加一個 admin user（noauth 需要有 user
--- 可自動登入）。此 server 僅供本機/區網瀏覽，密碼不具實際安全意義。
--- @param fb string filebrowser 執行檔路徑。
--- @return boolean db 是否就緒。
local function ensure_db(fb)
  if vim.fn.filereadable(DB) == 1 then return true end
  vim.fn.mkdir(vim.fn.fnamemodify(DB, ":h"), "p")
  vim.fn.system({ fb, "config", "init", "-d", DB })
  vim.fn.system({ fb, "config", "set", "--auth.method=noauth", "-d", DB })
  vim.fn.system({ fb, "users", "add", "admin", "local-only-noauth", "--perm.admin", "-d", DB })
  return vim.fn.filereadable(DB) == 1
end

local function is_running()
  return state.job ~= nil and vim.fn.jobwait({ state.job }, 0)[1] == -1
end

--- 從 start 起找第一個真正空的 port。
--- 注意：libuv 的 bind() 預設帶 SO_REUSEADDR，單獨 bind 不會報衝突，
--- 必須再 listen() 才能偵測到 port 已被其他 server 佔用。
--- @param start integer 起始 port。
--- @return integer 第一個空的 port（找不到則回傳 start）。
local function find_free_port(start)
  for p = start, start + 50 do
    local tcp = vim.uv.new_tcp()
    local ok = pcall(function()
      assert(tcp:bind("0.0.0.0", p))
      assert(tcp:listen(1, function() end))
    end)
    pcall(function() tcp:close() end)
    if ok then return p end
  end
  return start
end

--- 停止目前的 web media server。
function M.stop()
  if is_running() then
    vim.fn.jobstop(state.job)
    vim.notify("Web media server 已停止 (port " .. tostring(state.port) .. ")", vim.log.levels.INFO)
  end
  state.job, state.port, state.root = nil, nil, nil
end

--- 對指定資料夾啟動 filebrowser 並開瀏覽器。
--- @param dir string 資料夾路徑（會展開 ~ 與環境變數）。
--- @param opts table|nil 可選：{ port = <int>, open = true }；port 預設自動找空的。
function M.serve(dir, opts)
  opts = opts or {}
  dir = vim.fn.fnamemodify(vim.fn.expand(dir), ":p")
  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("不是資料夾: " .. dir, vim.log.levels.ERROR)
    return
  end

  -- 已有 server 在跑就先停掉，改服務新資料夾
  if is_running() then M.stop() end

  -- 解析 filebrowser 執行檔：優先 PATH，退回 ~/.local/bin/filebrowser
  local fb = vim.fn.exepath("filebrowser")
  if fb == "" then fb = vim.fn.expand("~/.local/bin/filebrowser") end
  if vim.fn.executable(fb) == 0 then
    vim.notify("找不到 filebrowser（PATH 與 ~/.local/bin 都沒有）", vim.log.levels.ERROR)
    return
  end

  -- 首次使用自動建立 db（noauth + admin user）
  if not ensure_db(fb) then
    vim.notify("無法初始化 filebrowser 資料庫: " .. DB, vim.log.levels.ERROR)
    return
  end

  -- -r 指定服務的資料夾、-p 自動找空 port（避免撞 port）、-a 綁 0.0.0.0
  local port = opts.port or find_free_port(8000)
  local job = vim.fn.jobstart(
    { fb, "-d", DB, "-r", dir, "-a", "0.0.0.0", "-p", tostring(port) },
    {
      on_exit = function(_, code)
        -- 143 = 被 jobstop (SIGTERM) 正常結束，不報錯
        if code ~= 0 and code ~= 143 then
          vim.schedule(function()
            vim.notify(
              "filebrowser 退出 (code " .. code .. ")，port " .. port .. " 可能被佔用",
              vim.log.levels.WARN
            )
          end)
        end
      end,
    }
  )

  if job <= 0 then
    vim.notify("無法啟動 filebrowser", vim.log.levels.ERROR)
    return
  end

  state.job, state.port, state.root = job, port, dir
  local url = "http://127.0.0.1:" .. port

  -- 綁 0.0.0.0：附上區網 IP，方便別台機器/手機連入
  local lan = ""
  local ok, ips = pcall(vim.fn.systemlist, { "hostname", "-I" })
  if ok and ips[1] then
    for _, ip in ipairs(vim.split(ips[1], "%s+", { trimempty = true })) do
      if ip:match("^%d+%.%d+%.%d+%.%d+$") then
        lan = lan .. "\n→ http://" .. ip .. ":" .. port .. "  (區網)"
      end
    end
  end
  vim.notify("Serving " .. dir .. "\n→ " .. url .. lan, vim.log.levels.INFO)

  -- 給 server 一點啟動時間再開瀏覽器
  vim.defer_fn(function()
    if opts.open ~= false then vim.ui.open(url) end
  end, 300)
end

--- 服務「當前 tab 的 cwd」（配合 :tcd 的 tab-local 專案根工作流）。
function M.serve_cwd()
  M.serve(vim.fn.getcwd(-1, 0))
end

--- 提示輸入路徑後服務該資料夾。
function M.serve_prompt()
  vim.ui.input(
    { prompt = "Web 瀏覽資料夾 → ", default = vim.fn.getcwd(-1, 0), completion = "dir" },
    function(input)
      if input and input ~= "" then M.serve(input) end
    end
  )
end

-- 離開 nvim 前自動收掉 server，避免遺留 filebrowser 進程
vim.api.nvim_create_autocmd("VimLeavePre", {
  desc = "停止 web media server",
  callback = function() M.stop() end,
})

return M
