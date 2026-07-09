# 個人 Neovim 設定

以 [NvChad v2.5](https://github.com/NvChad/NvChad) 為基礎的深度客製化設定，**同時支援 Linux 與 Windows**，目標是讓任何人在任意平台上 clone 完就能直接開發。

本 repo 圍繞兩個核心主軸：

**① 終端機內的 IDE**
Neovim 作為主力編輯器，在純終端機環境中提供完整的現代開發體驗——語法高亮、自動補全、LSP 跳轉、DAP 除錯、Git 整合、模糊搜尋——不依賴任何 GUI 介面，SSH 遠端也能全功能使用。設定刻意兼容 Linux 與 Windows 雙平台。

**② 終端機管理 Linux**
一套針對 Linux 伺服器與嵌入式設備（Jetson、Raspberry Pi）的 shell 腳本集合，涵蓋帳號與權限管理、網路設定、遠端桌面部署、系統報告等日常維運工作，目標是讓你不需要 GUI 就能完全掌控一台 Linux 機器。

---

## 快速開始

### Linux — 一鍵部署

> 適用：Ubuntu / Debian / Raspberry Pi OS / Jetson 等 apt 系 Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.sh)
```

腳本會自動安裝 Neovim 0.11+、系統依賴、下載本設定，並同步所有插件。

### Windows — 一鍵部署

> 以**系統管理員**開啟 PowerShell，貼上一行即可（公開 repo，走 git+HTTPS，不需金鑰）：

```powershell
irm https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.ps1 | iex
```

腳本會自動：用 winget 裝 git 與 Neovim → 以 HTTPS clone 本設定到 `%LOCALAPPDATA%\nvim`
→ 安裝 MSYS2 工具鏈（ripgrep / fd / gcc / make / chafa / bat / fzf）與 Node.js LTS
→ headless 同步所有插件。跑完重開終端機即可 `nvim`。

> 想先看內容或傳參數（如指定分支）？先下載再跑：
> ```powershell
> irm https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.ps1 -OutFile setup-nvchad.ps1
> .\setup-nvchad.ps1 -Branch main
> ```
>
> 只想單獨裝／更新 MSYS2 工具鏈，可直接跑
> [`window_tool_script/install-msys2.ps1`](window_tool_script/install-msys2.ps1)。
> 詳見 [docs/MSYS2_SETUP_GUIDE.md](docs/MSYS2_SETUP_GUIDE.md) 與
> [docs/setup_nvchad.md](docs/setup_nvchad.md)。

---

## Neovim 設定（`lua/`）

設定有意識地兼顧雙平台，在 Linux 與 Windows 上行為一致：

| 面向 | 說明 |
|------|------|
| **LSP** | Pyright（Neovim 0.11+ 原生 API），自動偵測 `.venv` |
| **除錯** | nvim-dap + nvim-dap-ui，自動載入 `.vscode/launch.json` |
| **搜尋** | Telescope，Windows 下整合 MSYS2 fd 大幅提升速度 |
| **格式化** | conform.nvim（black + isort） |
| **狀態列** | 依視窗寬度動態隱藏模組，SSH 窄視窗也適用 |
| **圖片預覽** | chafa ASCII 預覽，SSH 遠端與 Windows Terminal 皆可用（[指南](IMAGE_PREVIEW_GUIDE.md)） |
| **網頁多媒體** | filebrowser 把資料夾丟瀏覽器看縮圖/影片/PDF，`<leader>fs`，區網可連（[指南](WEB_MEDIA_GUIDE.md)） |

---

## 跨平台依賴清單（維護用）

> 一張表看懂「每個工具在各平台從哪裡裝、誰裝不了、為什麼」。新機器上手或排查
> 缺工具時對照這張表即可。安裝由 Windows 的
> [`install-msys2.ps1`](window_tool_script/install-msys2.ps1) 與 Linux 的
> [`setup-nvchad.sh`](setup-nvchad.sh) 自動處理；本表是它們的「真相來源」。

**圖例**：✅ 自動裝　🔧 需手動一次　➖ 內建/免裝　❌ 該平台裝不了（附原因）

| 工具 | 用途 | Windows 來源 | Linux 來源 | 備註 / 無法安裝原因 |
|------|------|-------------|-----------|--------------------|
| **ripgrep (rg)** | Telescope 全文搜尋 | ✅ MSYS2 ucrt64 | ✅ apt/dnf/pacman | Windows 統一走 MSYS2，移除 winget 版避免版本分裂 |
| **fd** | Telescope 找檔 | ✅ MSYS2 ucrt64 | ✅ 套件管理器 | — |
| **gcc** | treesitter 原生 parser 編譯 | ✅ MSYS2 ucrt64 | ✅ build-essential | Windows 須用 ucrt64 gcc，**勿用 Cygwin gcc**（parser 不相容會閃退） |
| **make** | 部分插件 build | ✅ MSYS2 **usr**（非 ucrt64） | ✅ build-essential | ucrt64 的 make 只有 `mingw32-make.exe`；真正的 `make.exe` 在 MSYS 層 |
| **chafa** | 圖片 ASCII 預覽（`<leader>fp`） | ✅ MSYS2 ucrt64 | ✅ 套件管理器 | — |
| **bat / fzf** | CLI 增益 | ✅ MSYS2 ucrt64 | ✅ 套件管理器 | nice-to-have |
| **rsync** | scp 替代品 / 同步檔案 | ✅ MSYS2 **usr** | ✅ 套件管理器 | Windows **可裝**（MSYS 層），遠端用走 SSH+System PATH；見下方說明 |
| **Node.js LTS** | markdown-preview 執行期 | ✅ winget `OpenJS.NodeJS.LTS` | ✅ nodesource/套件管理器 | Windows 不依賴 scoop |
| **yarn** | 建 markdown-preview | 🔧 `npm i -g yarn` | ✅ `npm i -g yarn` | — |
| **git** | 版本控制 / clone | ➖ 通常已有（Git for Windows） | ✅ 套件管理器 | install-msys2 刻意**不**裝 git，避免第二個 git 搶 bash 優先序 |
| **filebrowser** | 網頁多媒體（`<leader>fs`） | 🔧 手動放 `filebrowser.exe` 到 PATH | 🔧 手動放 `~/.local/bin` | 靜態 Go 執行檔，無 runtime 依賴；見 [WEB_MEDIA_GUIDE.md](WEB_MEDIA_GUIDE.md) |
| **win32yank** | 系統剪貼簿 provider | ➖ Neovim Windows 內建 | — | Linux 改用 OSC52 / wl-copy / xclip |
| **lazygit** | Git TUI | 🔧 winget `JesseDuffield.lazygit` | ✅ 套件管理器 | ❌ MSYS2 repo **無**此套件，故用 winget |
| **git-delta** | git diff 美化 | 🔧 winget `dandavison.delta` | ✅ 套件管理器 | ❌ MSYS2 的 `delta` 是另一個壓縮庫，**非** git diff 工具 |
| **image.nvim 後端**<br>(ueberzug/kitty) | 高畫質終端圖片 | ❌ 不適用 | 🔧 選用 | ❌ Windows 無 ueberzug；Windows 一律走 chafa 方案 |

### rsync 在 Windows 可不可裝？可以。

`install-msys2.ps1` 會在 MSYS 層裝 `rsync`（`pacman -S rsync`），並把
`C:\msys64\usr\bin` 寫進 **User PATH 與 System PATH**（System PATH 是為了讓
**SSH 遠端登入**也找得到 rsync）。所以：

- **本機用**：開終端機直接 `rsync -avz 來源/ 目的/`。
- **當 rsync 目標（從 Linux 推檔到這台 Windows）**：需 Windows 開 OpenSSH Server，
  且 rsync 在 **System PATH**（腳本已處理）。範例：
  `rsync -avz /src/ user@windows-ip:/cygdrive/c/Users/.../`
- 詳細工具用途與平台差異另見 [docs/CROSS_PLATFORM_DEPS.md](docs/CROSS_PLATFORM_DEPS.md)。

---

## 文件（`docs/`）

涵蓋部署流程、設計筆記與環境調校：

| 文件 | 內容 |
|------|------|
| [`docs/setup_nvchad.md`](docs/setup_nvchad.md) | **⬅ 從這裡開始**：Linux / Windows 完整部署步驟、快捷鍵與背景知識 |
| [`docs/MSYS2_SETUP_GUIDE.md`](docs/MSYS2_SETUP_GUIDE.md) | Windows MSYS2 環境建置，讓 Telescope 搜尋速度提升 15-30 倍 |
| [`docs/X11VNC_SETUP.md`](docs/X11VNC_SETUP.md) | Jetson Orin Nano 遠端桌面（x11vnc + 顯示修正） |
| [`docs/TELESCOPE_GITIGNORE_CONFIG.md`](docs/TELESCOPE_GITIGNORE_CONFIG.md) | Telescope 大型專案搜尋慢的根因分析與優化方案 |
| [`docs/RIPGREP_FD_PATH_SETUP.md`](docs/RIPGREP_FD_PATH_SETUP.md) | Telescope 報 "ripgrep is required"：bootstrap 自動把 rg/fd 補上 PATH（機群可攜） |

### nvim 工具彙整（2026-06 新增，黃金圈 + 蘇格拉底 + mermaid）

| 文件 | 內容 |
|------|------|
| [`docs/NVIMTREE_KEYMAP.md`](docs/NVIMTREE_KEYMAP.md) | nvim-tree 完整快捷鍵學習清單（`<C-k>` 資訊、`c` 複製、`H` gitignore 客製等） |
| [`docs/CROSS_PLATFORM_DEPS.md`](docs/CROSS_PLATFORM_DEPS.md) | 跨平台依賴與安裝維護指南（搭配上方依賴清單表格的深入版） |
| [`docs/CLIPBOARD_OSC52_GUIDE.md`](docs/CLIPBOARD_OSC52_GUIDE.md) | 剪貼簿升級：tmux + SSH 下 `<leader>Y` 整檔複製到本機系統剪貼簿（OSC52 原理） |
| [`docs/PLATFORM_KEY_NORMALIZATION.md`](docs/PLATFORM_KEY_NORMALIZATION.md) | 跨平台按鍵統一：Ctrl/Alt+Backspace 在各平台都「刪一個詞」 |
| [`docs/ALTW_BUFFER_CLOSE.md`](docs/ALTW_BUFFER_CLOSE.md) | `<A-w>` 一次關閉 buffer：雙重關閉的根因與修正 |
| [`docs/SSH_CONFIG_GUIDE.md`](docs/SSH_CONFIG_GUIDE.md) | SSH 配置黃金圈 + 內建設定精靈 `:SshSetup`（小白免記參數產金鑰/部署/測試） |
| [`docs/MULTIMEDIA_OVER_SSH.md`](docs/MULTIMEDIA_OVER_SSH.md) | 終端多媒體與 SSH 下瀏覽能力矩陣 + web-media 深入（含 Windows db-lock 坑） |
| [`docs/TERMINAL_INTERACTIVITY_ECOSYSTEM.md`](docs/TERMINAL_INTERACTIVITY_ECOSYSTEM.md) | 終端編程互動性現成方案盤點（tmux+nvim / SSH / 多媒體 / 編輯器 UX，含 recommend/skip/already-have 判定） |
| [`docs/DEVTOOLS_SETUP.md`](docs/DEVTOOLS_SETUP.md) | 系統工具跨機器複製：tmux（設定+tpm）與 jumpfwd/`jf`（socat+Tailscale port 轉發），一鍵 `setup-devtools.sh` 帶本機現況基準 |

---

## Linux 部署腳本（`script/`）

用於在 Linux 伺服器或嵌入式設備（Jetson、Raspberry Pi）上快速建置管理環境，Windows 使用者不需理會此目錄：

| 腳本 | 用途 |
|------|------|
| `setup_x11vnc.sh` | 部署 x11vnc 遠端桌面（含 systemd service） |
| `setup-display.sh` | 部署 xorg.conf 與顯示修正腳本（Jetson 系列） |
| `account-manager.sh` | 使用者帳號管理（建立 / 群組 / 家目錄權限） |
| `net-manager.sh` | 網路介面設定 |
| `perm-manager.sh` | 檔案與目錄權限管理 |
| `sysreport.sh` | 系統狀態報告 |
| `setup-devtools.sh` | tmux + jumpfwd(`jf`) 一鍵設定（跨發行版、冪等）；把本機終端多工與 port 轉發環境複製到其他 Linux（含 x86_64），詳見 [docs/DEVTOOLS_SETUP.md](docs/DEVTOOLS_SETUP.md) |
