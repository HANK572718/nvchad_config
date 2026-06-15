-- ============================================================================
-- configs/bootstrap.lua — 機群可攜的啟動環境修復（編譯器 + node 上 PATH）
-- ----------------------------------------------------------------------------
-- 目標：一份 init.lua 跨整個機群（多台 Windows / Linux x86_64 / ARM Jetson）。
-- 零寫死：不寫死使用者名、磁碟代號、scoop 版本、msys 路徑——全部從環境變數
--         與 glob 推導。新增一台機器 = 加一條候選路徑樣式，不必改邏輯。
--
-- 解決兩個已驗證的問題：
--   1. Treesitter 編譯器（Windows）：預設 `gcc` 可能指到 Cygwin gcc，編出的
--      parser .so 依賴 cygwin1.dll → 原生 nvim 載入時隨機硬崩潰。用
--      `gcc -dumpmachine` 辨別並排除 *-cygwin / *-msys，挑原生 MinGW-w64。
--      詳見 docs/TREESITTER_CYGWIN_CRASH.md。
--   2. Node 上 PATH（markdown-preview）：scoop 的 `current` 是 junction，SSH
--      session 解析失敗 → executable('node')==0。改 glob 實體版本目錄避開
--      junction。詳見 docs/MARKDOWN_PREVIEW_NODE_SETUP.md。
--
-- 設計：資料驅動候選表 + 通用解析迴圈。純 Lua、快、工具不存在時靜默降級、
--       任何例外都被頂層 pcall 包住——永遠不會中斷 nvim 啟動。
-- 在 init.lua 最上方、載入 nvim-treesitter / markdown-preview 之前呼叫。
-- ============================================================================
local M = {}

-- ---- 平台指紋（只算一次）---------------------------------------------------
local uname  = vim.uv.os_uname()
M.platform = {
  is_win = vim.fn.has("win32") == 1,
  is_mac = vim.fn.has("mac") == 1,
  sys    = uname.sysname,   -- 'Windows_NT' | 'Linux' | 'Darwin'
  arch   = uname.machine,   -- 'x86_64' | 'aarch64' | 'arm64'
}
local IS_WIN = M.platform.is_win
local ARCH   = M.platform.arch
local SEP    = IS_WIN and ";" or ":"
local EXE    = IS_WIN and ".exe" or ""
local HOME   = vim.fn.expand("~")

-- ---- 小工具（不丟例外、不開 shell 除非必要）-------------------------------
local function env(name)
  local v = vim.env[name]
  return (v ~= nil and v ~= "") and v or nil
end
local function nz(s) return s ~= nil and s ~= "" end
local function fwd(p) return (p or ""):gsub("\\", "/") end

-- glob → list（空 list，永不報錯）
local function glob(pat) return (nz(pat) and vim.fn.glob(pat, true, true)) or {} end

-- 把 dir 補進 PATH 最前面。Windows PATH 大小寫不敏感 → 比對時都轉小寫，
-- 避免因大小寫不同而重複加入（graft 自 helper-lib）。寫入用原生分隔符。
local function prepend_path(dir)
  if not nz(dir) then return end
  local d = IS_WIN and dir:gsub("/", "\\") or dir
  local cur = vim.env.PATH or ""
  local hay = IS_WIN and cur:lower() or cur
  local needle = IS_WIN and d:lower() or d
  if not (SEP .. hay .. SEP):find(SEP .. needle .. SEP, 1, true) then
    vim.env.PATH = d .. SEP .. cur
  end
end

-- 跑 `exe -dumpmachine`，失敗回 ''。pcall 包住，工具不存在不報錯。
local function dumpmachine(exe)
  local ok, out = pcall(vim.fn.systemlist, { exe, "-dumpmachine" })
  if not ok or vim.v.shell_error ~= 0 then return "" end
  return (out and out[1]) or ""
end

-- gcc/clang 可用 ⇔ 目標 triple 不是 cygwin/msys 子系統（這就是整個 bug）。
local function is_native_gcc(exe)
  local t = dumpmachine(exe)
  return t ~= "" and not t:match("%-cygwin$") and not t:match("%-msys$")
end

-- ============================================================================
-- 1) WINDOWS C 編譯器（為 nvim-treesitter 強制挑原生 gcc/clang）
-- ============================================================================
-- 資料驅動：{pat=glob, kind='gcc'|'clang'|'cl'|'zig'} 的有序候選表。
-- 新增工具鏈 = 加一列。gcc/clang 必須通過 -dumpmachine；cl/zig 免（不會是 cygwin）。
local function win_cc_candidates()
  local LOCALAPPDATA = env("LOCALAPPDATA")
  local PF           = env("ProgramFiles")
  local PFX86        = env("ProgramFiles(x86)")
  local SCOOP        = env("SCOOP") or (HOME .. "/scoop")
  local SCOOP_G      = env("SCOOP_GLOBAL") or "C:/ProgramData/scoop"

  -- MSYS2 安裝根（glob 全部；不存在就沒命中）。不寫死磁碟。
  local msys_roots = {
    "C:/msys64", "C:/msys32", "D:/msys64", "E:/msys64",
    LOCALAPPDATA and (LOCALAPPDATA .. "/scoop/apps/msys2/current"),
    SCOOP .. "/apps/msys2/current",
    SCOOP_G .. "/apps/msys2/current",
    "C:/ProgramData/chocolatey/lib/msys2/tools/msys64",
    env("USERPROFILE") and (env("USERPROFILE") .. "/msys64"),
    HOME .. "/msys64",
  }

  local C = {}
  local function add(pat, kind) if nz(pat) then C[#C + 1] = { pat = pat, kind = kind } end end

  -- MSYS2 原生工具鏈：ucrt64 > clang64 > mingw64 > mingw32。
  -- 絕不用 %root%/usr/bin（那是 x86_64-pc-msys 子系統）。
  for _, r in ipairs(msys_roots) do
    if nz(r) then
      add(r .. "/ucrt64/bin/gcc.exe", "gcc")
      add(r .. "/clang64/bin/clang.exe", "clang")
      add(r .. "/mingw64/bin/gcc.exe", "gcc")
      add(r .. "/mingw32/bin/gcc.exe", "gcc")
    end
  end

  -- 獨立 / winget / choco LLVM clang。
  add(PF and (PF .. "/LLVM/bin/clang.exe"), "clang")
  add(PFX86 and (PFX86 .. "/LLVM/bin/clang.exe"), "clang")

  -- scoop shims & 獨立 gcc/llvm（shim 可能包著 cygwin gcc → 仍會被 -dumpmachine 擋）。
  for _, root in ipairs({ SCOOP, SCOOP_G }) do
    add(root .. "/shims/gcc.exe", "gcc")
    add(root .. "/shims/clang.exe", "clang")
    add(root .. "/apps/llvm/current/bin/clang.exe", "clang")
    add(root .. "/apps/gcc/current/bin/gcc.exe", "gcc")
  end

  -- chocolatey mingw。
  add("C:/ProgramData/chocolatey/lib/mingw/tools/install/mingw64/bin/gcc.exe", "gcc")

  -- zig（跨平台 C 編譯器；nvim-treesitter 有 'zig' 項）。
  for _, root in ipairs({ SCOOP, SCOOP_G }) do
    add(root .. "/apps/zig/current/zig.exe", "zig")
  end
  add("C:/ProgramData/chocolatey/bin/zig.exe", "zig")
  add("C:/ProgramData/chocolatey/lib/zig/tools/*/zig.exe", "zig")

  -- MSVC cl.exe（透過 vswhere；需 Developer 環境，排最後）。
  local vswhere = PFX86 and (PFX86 .. "/Microsoft Visual Studio/Installer/vswhere.exe")
  if nz(vswhere) and vim.fn.executable(vswhere) == 1 then
    local host = (ARCH == "aarch64" or ARCH == "arm64") and "Hostarm64/arm64" or "Hostx64/x64"
    local ok, lines = pcall(vim.fn.systemlist, {
      vswhere, "-latest", "-products", "*",
      "-find", "VC/Tools/MSVC/**/bin/" .. host .. "/cl.exe",
    })
    if ok and vim.v.shell_error == 0 then
      for _, p in ipairs(lines or {}) do add(p, "cl") end
    end
  end

  return C
end

-- 解析候選表 → 第一個可用的絕對 exe（forward slash）。回傳 path, kind 或 nil。
local function discover_native_cc()
  for _, row in ipairs(win_cc_candidates()) do
    for _, hit in ipairs(glob(row.pat)) do
      if vim.fn.executable(hit) == 1 then
        if row.kind == "cl" or row.kind == "zig" then
          return fwd(hit), row.kind          -- 免 -dumpmachine
        elseif is_native_gcc(hit) then       -- gcc/clang 必須原生
          return fwd(hit), row.kind
        end
      end
    end
  end
  return nil
end

function M.setup_compiler()
  if env("CC") then return env("CC") end   -- 尊重使用者/父行程設的 $CC（所有平台）

  if IS_WIN then
    local cc, kind = discover_native_cc()
    if not cc then
      -- 沒找到原生編譯器：主動把 treesitter 預設清單裡的 bare gcc/cc（可能解析到
      -- Cygwin gcc）拿掉，避免它靜默挑到 Cygwin 又崩潰（graft 自對抗驗證）。
      local ok, install = pcall(require, "nvim-treesitter.install")
      if ok then install.compilers = { "clang", "cl", "zig" } end
      return nil
    end
    if kind ~= "zig" then
      vim.env.CC = cc   -- nvim-treesitter 第一順位讀 $CC
    end
    -- 把編譯器 bin 補進 PATH，讓 parser build 時找得到自身 runtime DLL
    -- （ucrt64 gcc 缺這個會「靜默失敗」exit 1 無輸出）。zig 也需在 PATH。
    prepend_path(fwd(vim.fn.fnamemodify(cc, ":h")))
    return cc
  end

  -- Linux / macOS / Jetson：信任預設 cc/gcc/clang。唯一要防的是 active conda
  -- 的無前綴 cc 蓋掉系統 cc。belt-and-suspenders，靜默降級。
  local conda = env("CONDA_PREFIX")
  if conda then
    local resolved
    for _, c in ipairs({ "cc", "gcc", "clang" }) do
      local p = vim.fn.exepath(c)
      if nz(p) then resolved = p; break end
    end
    -- 邊界對齊：CONDA_PREFIX 後補 '/'，避免 /opt/conda 誤判 /opt/condatools。
    local conda_pfx = conda:gsub("/+$", "") .. "/"
    if resolved and resolved:find(conda_pfx, 1, true) == 1 then
      for _, c in ipairs({
        "/usr/bin/cc", "/usr/bin/gcc", "/usr/bin/clang",
        "/usr/local/bin/gcc", "/usr/local/bin/clang",
      }) do
        if vim.fn.executable(c) == 1 then
          local ok, install = pcall(require, "nvim-treesitter.install")
          if ok then install.compilers = { c, "cc", "gcc", "clang" } end
          return c
        end
      end
    end
  end
  return nil
end

-- ============================================================================
-- 2) NODE 上 PATH（junction-safe；scoop/nvm/fnm/volta/系統；env 推導）
-- ============================================================================
-- 跳過名為 current/latest/default/node/lts 的 junction/symlink 段。
local SKIP_SEG = { current = true, latest = true, default = true, node = true, lts = true }

-- 數字感知版本比較（避免 '9.5.0' > '24.11.1' 的字典序錯誤）。
local function ver_key(s)
  local t = {}
  for n in tostring(s):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end
local function ver_gt(a, b)
  local ka, kb = ver_key(a), ver_key(b)
  for i = 1, math.max(#ka, #kb) do
    local x, y = ka[i] or -1, kb[i] or -1
    if x ~= y then return x > y end
  end
  return tostring(a) > tostring(b)
end

-- 從命中路徑取「版本目錄段」。剝掉已知 wrapper（binary / bin / installation），
-- 取剩下的 leaf 當版本——這樣 nvm-nix(/bin)、fnm(installation/)、volta、scoop
-- 全部正確（對抗驗證實測修正：原本的 or-match 會錯抓成 'bin' 挑到最舊版）。
local function ver_seg(h, exe_file)
  local base = h:gsub("/" .. vim.pesc(exe_file) .. "$", "")
  base = base:gsub("/bin$", "")
  base = base:gsub("/installation$", "")
  return base:match("([^/]+)$")
end

-- exe='node'。roots=候選根。templates=以 '%s'=root 的 glob 樣板。
-- 回傳實體絕對路徑或 nil。
local function resolve_versioned_bin(exe, roots, templates)
  -- 1) OS resolver 已經能用就直接用（桌面 + 所有 Linux）。
  if vim.fn.executable(exe) == 1 then
    local p = vim.fn.exepath(exe)
    if nz(p) then return fwd(p) end
  end

  -- 2) glob 版本目錄；跳過 junction 段；最新版勝。
  local exe_file = exe .. EXE
  local best
  for _, root in ipairs(roots) do
    if nz(root) then
      for _, tmpl in ipairs(templates) do
        for _, hit in ipairs(glob(tmpl:format(root))) do
          local h = fwd(hit)
          local seg = ver_seg(h, exe_file)
          if seg and not SKIP_SEG[seg:lower()]
            and vim.fn.executable(h) == 1
            and (not best or ver_gt(seg, best.ver)) then
            best = { path = h, ver = seg }
          end
        end
      end
    end
  end
  if best then return best.path end

  -- 3) 最後手段：realpath 'current'（被擋的 junction 會丟例外 → pcall 包住）。
  for _, root in ipairs(roots) do
    for _, sub in ipairs({ "/current/" .. exe_file, "/current/bin/" .. exe_file }) do
      local ok, rp = pcall(vim.uv.fs_realpath, root .. sub)
      if ok and rp then return fwd(rp) end
    end
  end
  return nil
end

local function node_roots()
  local SCOOP   = env("SCOOP") or (HOME .. "/scoop")
  local SCOOP_G = env("SCOOP_GLOBAL")
  local r = {
    SCOOP .. "/apps/nodejs-lts",
    SCOOP .. "/apps/nodejs",
    SCOOP_G and (SCOOP_G .. "/apps/nodejs-lts"),
    SCOOP_G and (SCOOP_G .. "/apps/nodejs"),
    env("NVM_HOME"),                                 -- nvm-windows: v<ver>/node.exe（扁平）
    env("NVM_DIR") or (HOME .. "/.nvm"),             -- nvm-nix: versions/node/v*/bin/node
    env("FNM_DIR"),
    env("XDG_DATA_HOME") and (env("XDG_DATA_HOME") .. "/fnm"),
    HOME .. "/.fnm",
    HOME .. "/.local/share/fnm",
    env("LOCALAPPDATA") and (env("LOCALAPPDATA") .. "/fnm"),
    env("VOLTA_HOME") or (HOME .. "/.volta"),
  }
  if not IS_WIN then
    vim.list_extend(r, {
      "/usr/local", "/usr", "/opt/nodejs",
      "/usr/local/n/versions/node", "/snap/node",
    })
  end
  return r
end

-- 涵蓋各 node 安裝器佈局。'%s'=root。沒命中就沒事。
local NODE_GLOBS = {
  "%s/*/node" .. EXE,                              -- scoop, nvm-windows 扁平
  "%s/*/bin/node",                                 -- nvm-nix, n, /usr/local
  "%s/versions/node/*/bin/node",                   -- nvm-nix
  "%s/node-versions/*/installation/node" .. EXE,   -- fnm windows
  "%s/node-versions/*/installation/bin/node",      -- fnm nix
  "%s/tools/image/node/*/node" .. EXE,             -- volta windows
  "%s/tools/image/node/*/bin/node",                -- volta nix
  "%s/bin/node" .. EXE,                            -- /usr/local/bin, /usr/bin
  "%s/node" .. EXE,                                -- ProgramFiles/nodejs（系統/winget/MSI）
}

function M.setup_node()
  local node = resolve_versioned_bin("node", node_roots(), NODE_GLOBS)
  if not node then return nil end   -- 靜默降級

  -- junction 穿越問題是 Windows-only；Linux symlink 在 SSH 下正常，step 1 已搞定。
  if IS_WIN then
    prepend_path(fwd(vim.fn.fnamemodify(node, ":h")))
  end
  return node
end

-- ---- 入口（每階段各自 pcall，任何例外都不會中斷 nvim 啟動）----------------
function M.setup()
  local summary = { platform = M.platform }
  pcall(function() summary.cc = M.setup_compiler() end)
  pcall(function() summary.node = M.setup_node() end)
  M.last = summary
  return summary
end

return M
