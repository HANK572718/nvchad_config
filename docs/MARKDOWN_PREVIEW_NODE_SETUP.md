# markdown-preview.nvim 報錯 "prebuild and node is not found" — Node.js 安裝

> 故障排除實錄。發生日期：2026-06-15
> 相關文件：[MSYS2_SETUP_GUIDE.md](./MSYS2_SETUP_GUIDE.md)

## 一、症狀

執行 `:MarkdownPreview` 時報錯，大意為 **prebuild（預建二進位）找不到、node 找不到**。

## 二、根因

`markdown-preview.nvim` 的預覽功能是一支 **Node.js 寫的本機 server**，本質上**執行期就需要 Node**（不只是安裝時）。本機狀態：

- `node` 不在 PATH（`Get-Command node` 找不到）→ 對應 "node is not found"
- 插件 `app/bin/` 為空（沒有預建二進位）、`app/node_modules` 不存在（`yarn install` 從未跑過）→ 對應 "prebuild not found"

插件 spec（`lua/plugins/init.lua`）的 build 指令是 `cd app && yarn install`，沒有 node 整個 build 與執行都無法進行。

## 三、解法（已完成）

### 步驟 1：用 scoop 安裝 Node LTS

```powershell
scoop install nodejs-lts
```

- 裝出 Node `v24.11.1`、npm `11.6.2`（npm 隨 node 一起，位於 `~/scoop/apps/nodejs-lts/current/`）
- scoop 自動把 node 加入**持久化 User PATH**（`~/scoop/apps/nodejs-lts/current[/bin]` 與 `~/scoop/shims`）
- 安裝過程中 scoop 自我更新會噴一堆 git `dubious ownership` 警告，與 node 安裝無關，可忽略。順手修：
  ```powershell
  git config --global --add safe.directory C:/Users/suser/scoop/apps/scoop/current
  ```

### 步驟 2：建置 markdown-preview 的 app（用 npm 取代 yarn）

本機沒有 yarn，直接用 npm 在插件 app 目錄安裝（功能等價）：

```powershell
# 先把 node 加進「當前 session」PATH（scoop 的 PATH 更新只對新終端生效）
$nodeDir = "$env:USERPROFILE\scoop\apps\nodejs-lts\current"
$env:PATH = "$nodeDir;$env:USERPROFILE\scoop\shims;$env:PATH"

cd "$env:LOCALAPPDATA\nvim-data\lazy\markdown-preview.nvim\app"
npm install
```

- 結果：exit 0，`node_modules` 建立成功，`app/server.js` 就緒
- npm audit 報的 vulnerabilities 是插件 dev 依賴的警告，本機預覽用途無妨

## 四、驗證

- `node --version` → `v24.11.1` ✅
- 持久化 User PATH 已含 nodejs → **新開的終端 / nvim 都找得到 node** ✅
- `app/node_modules` 存在、`app/server.js` 存在 ✅

## 五、為何「裝了 node 還是報錯」——以及最終解法

裝完 node 後重開 nvim 仍報 "Pre build and node is not found"。實測 `:lua print(vim.fn.executable('node'))` 在全新 nvim 回傳 **0**。

**根因**：scoop 只把 node 加進**持久化 registry PATH**，僅對「之後新開的終端」生效。nvim 繼承的是**啟動它的那個父行程（終端）的 PATH**——若該終端是裝 node 之前就開著的，PATH 裡就沒有 node，nvim 也就找不到。`markdown-preview` 的 `rpc.vim` 在 `executable('node')` 為 0 時直接報這個錯。

**最終解法（已實作，跨終端穩定）**：不依賴「重開終端」，改在 `init.lua` 讓 nvim 自己保證 node 在 PATH。
最初版本只試 `current` junction（見下方），桌面有效但 SSH 失敗，最終版改為**同時列出實體版本目錄**
（完整程式碼與根因見「五之二」）：

```lua
-- init.lua（接在 treesitter gcc 的 PATH 區塊之後）— 概念版
if vim.fn.has("win32") == 1 and vim.fn.executable("node") == 0 then
  -- 候選含 current(junction) + 實體版本目錄(如 24.11.1)，後者在 SSH 下才解析得到
  -- 逐一試 executable(dir.."\\node.exe")，找到就插進 vim.env.PATH
end
```

效果：即使從完全沒有 node、或只有 junction 解析不了的 SSH session 啟動，nvim 載入 config 後
`executable('node') = 1`，`mkdp#rpc#start_server()` 不再落到 node-not-found 分支。
**這才是真正讓問題消失的修復**，步驟 1～2 只是前置（裝 node + build app）。

## 五之二、最棘手情境：SSH 進來「本機 OK、SSH 不行」——真正根因是 junction

**症狀**：本機桌面的 nvim 能用 markdown preview，但從遠端 SSH 進來的 nvim 不行。即使
殺光所有 nvim 進程、重開全新 nvim 仍是 `executable('node') = 0`。

**架構**：遠端 → Raspberry Pi → tmux → SSH 到這台 Windows（`192.168.1.58`）→ 開 nvim。

### 排查方法（關鍵：用啟動 log 抓「真實 SSH session」的環境）

桌面模擬一直成功、SSH 卻失敗，代表有模擬不到的差異。做法：在 `init.lua` 最前面與 node-fix
後各埋一段 log，把每次啟動的 `USERPROFILE` / `HOME` / `PATH` / `executable('node')` /
某絕對路徑是否存在，寫到 `nvim-data\startup-diag.log`。然後請使用者從 SSH 開一次 nvim，
再從桌面端讀那個 log —— 這樣就拿到 SSH session 啟動 nvim 的**第一手環境**。

### 根因（log 證實）

SSH session 的 log 顯示：

```
SSH_CONNECTION=192.168.1.1 ... 192.168.1.58 22     ← 確認是真 SSH
PATH=...;C:\Users\suser\scoop\apps\nodejs-lts\current\bin;...\current;...  ← PATH 其實有 node 路徑！
scoop_node_exe_exists=0                              ← 但這個 current\node.exe 解析「失敗」
```

`...\nodejs-lts\current` 是 scoop 建的 **junction**（連到實體目錄 `24.11.1`）。
**從 SSH 進來的 session 解析這個 junction 會失敗**——所以即使 PATH 裡有 `current\bin`，
`executable('node')` 仍是 0。桌面 session 能解析 junction、SSH 不能，這就是
「本機 OK、SSH 不行」的真正原因（先前以為是 tmux 凍結 PATH，其實 PATH 沒問題，是 junction）。

### 解法（已實作）

補 node 到 PATH 時，**不只試 `current`（junction），同時 glob 出實體版本目錄**（如 `24.11.1`）
一起當候選。SSH 下走實體路徑就成功：

```lua
local base = up .. "\\scoop\\apps\\nodejs-lts"
local candidates = { base .. "\\current" }
for _, p in ipairs(vim.fn.glob(base .. "\\*", true, true)) do
  local d = p:gsub("/", "\\")
  if not d:lower():find("\\current$") then table.insert(candidates, d) end  -- 實體目錄，避開 junction
end
-- ...逐一試 executable(dir.."\\node.exe")，找到就插進 PATH
```

**驗證**（SSH session log）：`node_AFTER_fix=1`、`exepath_AFTER=...\nodejs-lts\24.11.1\node.EXE`
（走的正是實體目錄，非 junction）。實機 SSH 進來 `:MarkdownPreview` 可正常啟動。

> 關鍵教訓：Windows 上 scoop 的 `current` 是 junction，跨 session context（桌面 vs SSH vs 服務）
> 解析行為可能不同。**靠 junction 路徑找執行檔在 SSH 下不可靠，要用實體版本目錄**。

## 五之三、機群可攜化（2026-06-15，取代寫死路徑）

原本的修復把 `C:\Users\suser\scoop\...\24.11.1` 等路徑寫死在 init.lua，只對這台機器有效。
已抽成機群可攜的 **`lua/configs/bootstrap.lua`**（與 treesitter 編譯器修復同一個模組），
由 init.lua 一行 `require("configs.bootstrap").setup()` 呼叫。

### 可攜 node 偵測（零寫死，跨 Windows/Linux/ARM）

- **通用解析器**：給定一組「含版本子目錄（可能還有會壞的 `current` junction）的根目錄」，
  回傳最新版的實體 node。步驟：① `executable('node')` 已能用就直接用（桌面 + 所有 Linux）；
  ② glob 版本目錄、跳過名為 `current/latest/default/node/lts` 的 junction 段、數字感知挑最新版；
  ③ 最後才 `pcall(fs_realpath)`（被擋的 junction 會丟例外，pcall 包住）。
- **根目錄全從環境變數推導**：`SCOOP`/`SCOOP_GLOBAL`/`NVM_HOME`/`NVM_DIR`/`FNM_DIR`/
  `XDG_DATA_HOME`/`VOLTA_HOME`/`LOCALAPPDATA`/`~`。**零寫死使用者名、版本、磁碟**。
- **glob 樣板涵蓋各安裝器佈局**：scoop 扁平（`<ver>/node.exe`）、nvm-nix（`/bin/`）、
  nvm-windows 扁平、fnm（`installation/`）、volta（`tools/image/`）、系統/winget。
  新增佈局 = 加一條樣板。
- **版本選擇修正**（對抗驗證抓到的真 bug）：原本用 `or`-match 取段會把 `bin`/`installation`
  誤當版本 → Linux 上挑到**最舊**版。改用 `ver_seg`（剝掉 binary/bin/installation wrapper
  取 leaf）+ 數字感知 `ver_gt`。**7 種佈局單元測試全過**（scoop/nvm-nix/fnm-nix/fnm-win/
  volta/nvm-win/junction-skip）。

### 驗證（2026-06-15）

- 本機正常 + 模擬 SSH（PATH 清空 node/scoop）兩種環境：模組都找到實體
  `.../24.11.1/node.exe`（避開 junction），`executable('node')=1`，零寫死。
- 7 佈局版本選擇單元測試：**7 PASS / 0 FAIL**（含 Linux/ARM 機器無法在此跑的佈局）。

## 六、使用方式

- 執行 `:MarkdownPreview` 後從 cmdline 複製 URL，在瀏覽器開啟。
- 插件設定 bind `0.0.0.0`、固定 port `8090`（見 `lua/plugins/init.lua` 的 mkdp 設定）。
- **SSH / tmux 場景**：server bind 在這台 Windows 的區網 IP（如 `http://192.168.1.58:8090/...`）。要從**能連到該 IP 的瀏覽器**開啟；若瀏覽器在 Pi 端或其他網段，需設 SSH port forwarding（`ssh -L 8090:192.168.1.58:8090 ...`）再用 `localhost:8090`。

## 七、更新記錄

- **2026-06-15**：建立。scoop 裝 Node v24.11.1、用 npm 建置 markdown-preview app。
- **2026-06-15**：補根因（桌面）——在 `init.lua` 加 node-on-PATH guard，桌面 nvim `executable(node)=1`、`start_server ok`。
- **2026-06-15**：SSH 仍失敗，深挖出**真正根因 = scoop `current` junction 在 SSH session 解析失敗**。
  排查靠埋啟動 log 抓真實 SSH 環境（log 證實 `scoop_node_exe_exists=0` 但 PATH 有 current）。
  修法改為 glob 實體版本目錄（`24.11.1`）一起當候選，避開 junction。SSH log 驗證
  `node_AFTER_fix=1` / `exepath_AFTER=...\24.11.1\node.EXE`，實機 SSH `:MarkdownPreview` 正常。
  排查用的啟動 log 程式碼已從 init.lua 移除。
- **2026-06-15（可攜化）**：把寫死路徑抽成 `lua/configs/bootstrap.lua`（多代理工作流設計 +
  對抗驗證）。env 推導 + glob 版本目錄 + 數字感知選新版，零寫死，跨 Windows/Linux/ARM。
  修掉對抗驗證抓到的 Linux 版本選擇 bug（`bin`/`installation` 被誤當版本挑到最舊）。
  7 佈局單元測試全過；本機正常與模擬 SSH 兩環境皆 `executable(node)=1`。詳見第五之三節。
