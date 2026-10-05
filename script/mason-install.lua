-- =====================================================
-- mason-install.lua — headless 安裝所有 LSP server / formatter / DAP
--
-- 用法（三個平台的安裝腳本都呼叫這支）：
--     nvim --headless -c 'luafile <repo>/script/mason-install.lua'
--
-- ⚠️ 不要改用 `nvim --headless -l <script>`：實測 `-l` **不會載入 init.lua**
--    （lazy 沒起來、mason-registry 不存在），腳本會直接判定失敗跳出。
--    `-c luafile` 才會走正常設定載入流程。
--
-- 為什麼需要這支，而不是直接 `nvim --headless +MasonInstallAll +qa`：
--
--   1. `:MasonInstallAll` 由 NvChad 的 ui 外掛延遲註冊（lua/nvchad/au.lua:51）。
--      headless 下該外掛常常還沒載入，指令不存在 → E492: Not an editor command。
--      直接呼叫底層的 require("nvchad.mason").install_all() 才穩。
--
--   2. mason 的安裝是**非同步**的。nvim 一結束就會印
--      "Neovim is exiting while packages are still installing. Terminating all
--      installations…" 並把全部安裝砍掉。所以不能用固定 sleep，必須等到每個
--      目標套件都 is_installed() 才離開。predicate 形式的 vim.wait 會抽事件
--      迴圈，安裝任務才推得動。
--
--   3. get_pkgs() 的來源包含 vim.lsp._enabled_configs 與 conform 的 formatter
--      清單，兩者都來自延遲載入的外掛。不先把它們 require 起來，清單會少一大半
--      （實測只剩 2 個）。
--
-- 套件清單的單一事實來源是 lua/chadrc.lua 的 M.mason.pkgs
-- （對應 nvconfig.mason.pkgs），再加上這裡 require 起來的 lspconfig / conform
-- 自動推導出的項目。注意 mason.nvim **沒有** ensure_installed 選項，掛在它
-- opts 上的清單會被靜默丟掉 —— 那正是本檔存在的原因。
-- =====================================================

local TIMEOUT_MS = 600000 -- 10 分鐘

vim.wait(10000, function() return package.loaded["mason-registry"] ~= nil end)

local mr_ok, mr = pcall(require, "mason-registry")
local nm_ok, nm = pcall(require, "nvchad.mason")
if not mr_ok or not nm_ok then
  io.stderr:write("mason-registry / nvchad.mason 載入失敗，略過\n")
  vim.cmd("cq 1")
  return
end

-- 讓 get_pkgs() 看得到 vim.lsp.enable() 的 server 與 conform 的 formatter
pcall(require, "lspconfig")
pcall(require, "conform")
pcall(require, "configs.lspconfig")

-- 註：get_pkgs() 會 mutate nvconfig.mason.pkgs（把推導出的項目 append 進去），
-- 重複呼叫會累積，所以只叫一次並沿用結果。
local targets = nm.get_pkgs()
table.sort(targets)
print(("目標 %d 個: %s"):format(#targets, table.concat(targets, ", ")))

nm.install_all()

local done = vim.wait(TIMEOUT_MS, function()
  for _, name in ipairs(targets) do
    local ok, pkg = pcall(mr.get_package, name)
    if ok and not pkg:is_installed() then return false end
  end
  return true
end, 2000)

local missing = {}
for _, name in ipairs(targets) do
  local ok, pkg = pcall(mr.get_package, name)
  if not ok or not pkg:is_installed() then missing[#missing + 1] = name end
end

if done and #missing == 0 then
  print(("全部 %d 個套件安裝完成"):format(#targets))
  vim.cmd("qa!")
else
  print(("尚缺 %d 個: %s（可在 nvim 內重跑 :MasonInstallAll）"):format(#missing, table.concat(missing, ", ")))
  vim.cmd("cq 1")
end
