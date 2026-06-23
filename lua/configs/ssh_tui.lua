-- =============================================================
-- SSH TUI：小白也能用的 SSH 金鑰 / 連線設定精靈（純 nvim，跨平台）
--
-- WHY（為什麼）：SSH 金鑰登入要記的東西太多——ssh-keygen 的演算法旗標、私鑰
--   放哪、~/.ssh/config 的語法、怎麼把公鑰送到對方、權限怎麼設……新手很容易
--   卡住或設錯（尤其 Windows 的 authorized_keys ACL）。這個模組把「能無腦做」
--   的步驟全部做掉，使用者只要回答「主機 IP / 帳號 / 別名」幾個問題，其餘
--   交給精靈。
--
-- HOW（怎麼做）：全部走 nvim 內建 UI（vim.ui.select / vim.ui.input）做選單與
--   問答，底層呼叫系統的 ssh-keygen / ssh / ssh-copy-id（Windows 沒有
--   ssh-copy-id 時改用一段 ssh 遠端指令把公鑰 append 進對方 authorized_keys）。
--   不需要使用者預先知道任何參數。
--
-- WHAT（提供什麼）：:SshSetup（或 <leader>Sk）開選單：
--   1. 產生新金鑰（ed25519，問 label / 檔名，預設安全值）
--   2. 設定一台新主機（寫 ~/.ssh/config 別名 + 把公鑰部署到對方 → 之後
--      `ssh <別名>` 免密碼）
--   3. 複製某把公鑰到剪貼簿（給對方自己貼進白名單 / GitHub / GitLab）
--   4. 列出現有金鑰與已設定主機
--   5. 測試連線（ssh -o BatchMode 驗證免密碼是否成功）
--
-- 跨平台：~/.ssh 路徑、檔案讀寫、執行外部指令都走 nvim API（vim.fn.expand /
--   vim.fn.has('win32') / vim.system），Windows 與 Linux 共用同一份程式碼。
--   觀念與進階設定見 docs/SSH_CONFIG_GUIDE.md 與既有 docs/ssh-key-login-guide.md。
-- =============================================================

local M = {}

local SSH_DIR = vim.fn.expand("~/.ssh")
local CONFIG_PATH = SSH_DIR .. "/config"
local is_win = vim.fn.has("win32") == 1

-- ── 小工具 ────────────────────────────────────────────────────────────

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "SSH Setup" })
end

--- 確保 ~/.ssh 存在且權限正確（Linux 700；Windows 由 ACL 控管，這裡只建目錄）。
local function ensure_ssh_dir()
  if vim.fn.isdirectory(SSH_DIR) == 0 then
    vim.fn.mkdir(SSH_DIR, "p", tonumber("700", 8))
  end
end

--- 列出 ~/.ssh 下的私鑰（有對應 .pub 才算一把可用金鑰）。
--- @return string[] 私鑰完整路徑清單。
local function list_keys()
  local keys = {}
  local pubs = vim.fn.glob(SSH_DIR .. "/*.pub", false, true)
  for _, pub in ipairs(pubs) do
    local priv = pub:gsub("%.pub$", "")
    if vim.fn.filereadable(priv) == 1 then
      keys[#keys + 1] = priv
    end
  end
  return keys
end

--- 同步執行外部指令，回傳 (ok, stdout, stderr)。
--- @param cmd string[] 指令與參數陣列。
--- @return boolean, string, string
local function run(cmd)
  local res = vim.system(cmd, { text = true }):wait()
  return res.code == 0, res.stdout or "", res.stderr or ""
end

-- ── 動作 1：產生新金鑰 ────────────────────────────────────────────────

function M.gen_key(callback)
  ensure_ssh_dir()
  vim.ui.input({ prompt = "金鑰用途標籤（例：home-nas-2026，可留空）: " }, function(label)
    if label == nil then return end -- 取消
    vim.ui.input({
      prompt = "私鑰檔名（放在 ~/.ssh/，預設 id_ed25519）: ",
      default = "id_ed25519",
    }, function(fname)
      if fname == nil or fname == "" then return end
      local path = SSH_DIR .. "/" .. fname
      if vim.fn.filereadable(path) == 1 then
        notify("金鑰已存在：" .. path .. "（不覆蓋）", vim.log.levels.WARN)
        if callback then callback(path) end
        return
      end
      -- -N "" = 不設 passphrase，最無痛；想要更安全可事後 ssh-keygen -p 補上。
      local cmd = { "ssh-keygen", "-t", "ed25519", "-f", path, "-N", "" }
      if label and label ~= "" then
        vim.list_extend(cmd, { "-C", label })
      end
      local ok, _, err = run(cmd)
      if ok then
        notify("已產生金鑰：" .. path .. "\n公鑰：" .. path .. ".pub")
        if callback then callback(path) end
      else
        notify("產生失敗：" .. err, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- ── 動作 2：設定一台新主機（config 別名 + 部署公鑰）────────────────────

--- 把一段 Host block 追加進 ~/.ssh/config（若別名已存在則略過寫入）。
local function append_host_block(alias, host, user, port, identity)
  ensure_ssh_dir()
  local existing = ""
  if vim.fn.filereadable(CONFIG_PATH) == 1 then
    existing = table.concat(vim.fn.readfile(CONFIG_PATH), "\n")
  end
  if existing:match("\n?Host%s+" .. vim.pesc(alias) .. "%s") or existing:match("^Host%s+" .. vim.pesc(alias) .. "%s") then
    notify("config 已有別名 '" .. alias .. "'，略過寫入（保留你現有設定）", vim.log.levels.WARN)
    return
  end
  local block = {
    "",
    "Host " .. alias,
    "    HostName " .. host,
    "    User " .. user,
    "    Port " .. port,
    "    IdentityFile " .. identity,
    "    IdentitiesOnly yes",
    "    AddKeysToAgent yes",
  }
  local all = vim.fn.filereadable(CONFIG_PATH) == 1 and vim.fn.readfile(CONFIG_PATH) or {}
  vim.list_extend(all, block)
  vim.fn.writefile(all, CONFIG_PATH)
  notify("已寫入 ~/.ssh/config 別名：" .. alias)
end

--- 把公鑰部署到遠端的 authorized_keys，讓之後免密碼登入。
--- Linux 有 ssh-copy-id 就用它；否則（含 Windows）用一段 ssh 遠端指令 append。
--- 這一步「會」要求輸入一次遠端密碼（這是最後一次需要密碼）。
local function deploy_pubkey(alias, pub_path)
  local pub = table.concat(vim.fn.readfile(pub_path), "\n")
  -- 優先 ssh-copy-id（Linux / macOS / 有裝的環境）
  if vim.fn.executable("ssh-copy-id") == 1 then
    notify("用 ssh-copy-id 部署公鑰到 " .. alias .. "，待會請輸入一次遠端密碼…\n"
      .. "請在新終端執行：ssh-copy-id -i " .. pub_path .. " " .. alias)
    return
  end
  -- Fallback：適用 Windows client 或沒有 ssh-copy-id 的情況。
  -- 用一段在「遠端」執行的 shell，把公鑰 append 進對方的 ~/.ssh/authorized_keys。
  -- （遠端是 Linux 時成立；遠端是 Windows server 的 authorized_keys ACL 較特殊，
  --   見 docs/ssh-key-login-guide.md 的 Windows server 章節。）
  local remote_cmd = string.format(
    "umask 077; mkdir -p ~/.ssh && echo '%s' >> ~/.ssh/authorized_keys",
    pub:gsub("'", "'\\''")
  )
  notify("沒有 ssh-copy-id，請在新終端手動執行以下指令部署公鑰（會問一次密碼）：\n"
    .. "ssh " .. alias .. " \"" .. remote_cmd .. "\"")
end

function M.add_host()
  local keys = list_keys()
  local function with_key(identity)
    vim.ui.input({ prompt = "主機別名（之後用 `ssh 別名` 連，例：nas）: " }, function(alias)
      if not alias or alias == "" then return end
      vim.ui.input({ prompt = "主機 IP 或網域: " }, function(host)
        if not host or host == "" then return end
        vim.ui.input({ prompt = "登入帳號: " }, function(user)
          if not user or user == "" then return end
          vim.ui.input({ prompt = "Port（預設 22）: ", default = "22" }, function(port)
            if not port or port == "" then port = "22" end
            append_host_block(alias, host, user, port, identity)
            deploy_pubkey(alias, identity .. ".pub")
          end)
        end)
      end)
    end)
  end

  if #keys == 0 then
    notify("尚無金鑰，先幫你產生一把…")
    M.gen_key(function(path) with_key(path) end)
  else
    local choices = vim.deepcopy(keys)
    choices[#choices + 1] = "＋ 產生一把新金鑰"
    vim.ui.select(choices, { prompt = "這台主機用哪把金鑰？" }, function(choice)
      if not choice then return end
      if choice == "＋ 產生一把新金鑰" then
        M.gen_key(function(path) with_key(path) end)
      else
        with_key(choice)
      end
    end)
  end
end

-- ── 動作 3：複製公鑰到剪貼簿 ──────────────────────────────────────────

function M.copy_pubkey()
  local keys = list_keys()
  if #keys == 0 then
    notify("尚無金鑰，請先用選單第 1 項產生", vim.log.levels.WARN)
    return
  end
  vim.ui.select(keys, { prompt = "複製哪把公鑰到系統剪貼簿？" }, function(choice)
    if not choice then return end
    local pub = table.concat(vim.fn.readfile(choice .. ".pub"), "\n")
    vim.fn.setreg("+", pub)
    notify("公鑰已複製到系統剪貼簿，可直接貼到對方 authorized_keys / GitHub / GitLab")
  end)
end

-- ── 動作 4：列出金鑰與已設定主機 ─────────────────────────────────────

function M.list()
  local lines = { "── 金鑰（~/.ssh）──" }
  local keys = list_keys()
  if #keys == 0 then
    lines[#lines + 1] = "  （無）"
  else
    for _, k in ipairs(keys) do
      lines[#lines + 1] = "  " .. vim.fn.fnamemodify(k, ":t")
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "── 已設定主機（~/.ssh/config）──"
  if vim.fn.filereadable(CONFIG_PATH) == 1 then
    for _, l in ipairs(vim.fn.readfile(CONFIG_PATH)) do
      local alias = l:match("^Host%s+(.+)")
      if alias then lines[#lines + 1] = "  " .. alias end
    end
  else
    lines[#lines + 1] = "  （尚無 config）"
  end
  notify(table.concat(lines, "\n"))
end

-- ── 動作 5：測試連線 ──────────────────────────────────────────────────

function M.test_connection()
  if vim.fn.filereadable(CONFIG_PATH) == 0 then
    notify("尚無 ~/.ssh/config，請先設定主機（選單第 2 項）", vim.log.levels.WARN)
    return
  end
  local aliases = {}
  for _, l in ipairs(vim.fn.readfile(CONFIG_PATH)) do
    local a = l:match("^Host%s+(.+)")
    if a and a ~= "*" then aliases[#aliases + 1] = a end
  end
  if #aliases == 0 then
    notify("config 內沒有可測的主機別名", vim.log.levels.WARN)
    return
  end
  vim.ui.select(aliases, { prompt = "測試連到哪一台？" }, function(alias)
    if not alias then return end
    notify("測試 " .. alias .. " …（免密碼登入應在數秒內回應）")
    -- BatchMode=yes：不允許互動輸入密碼，藉此判定「是否真的免密碼成功」。
    local ok, _, err = run({ "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", alias, "echo OK" })
    if ok then
      notify("✅ " .. alias .. " 免密碼連線成功！之後直接 `ssh " .. alias .. "`")
    else
      notify("❌ " .. alias .. " 連線未成功：\n" .. err
        .. "\n通常是公鑰還沒部署到對方（回選單第 2 項重做部署那步）", vim.log.levels.WARN)
    end
  end)
end

-- ── 主選單 ────────────────────────────────────────────────────────────

function M.menu()
  local items = {
    { label = "1. 產生新金鑰（ed25519）", fn = M.gen_key },
    { label = "2. 設定一台新主機（別名 + 部署公鑰 → 免密碼登入）", fn = M.add_host },
    { label = "3. 複製某把公鑰到剪貼簿（給對方加白名單）", fn = M.copy_pubkey },
    { label = "4. 列出現有金鑰與主機", fn = M.list },
    { label = "5. 測試連線（驗證免密碼）", fn = M.test_connection },
  }
  vim.ui.select(items, {
    prompt = "SSH 設定精靈（不用記任何參數）",
    format_item = function(it) return it.label end,
  }, function(choice)
    if choice then choice.fn() end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("SshSetup", function() M.menu() end,
    { desc = "SSH 設定精靈（金鑰 / config / 部署公鑰 / 測試）" })
  vim.keymap.set("n", "<leader>Sk", function() M.menu() end,
    { desc = "SSH 設定精靈（TUI）" })
end

return M
