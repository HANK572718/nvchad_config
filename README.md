# 個人 Neovim 設定

以 [NvChad v2.5](https://github.com/NvChad/NvChad) 為基礎的深度客製化設定，**同時支援 Linux 與 Windows**，目標是讓任何人在任意平台上 clone 完就能直接開發。

---

## 快速開始

### Linux — 一鍵部署

> 適用：Ubuntu / Debian / Raspberry Pi OS / Jetson 等 apt 系 Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.sh)
```

腳本會自動安裝 Neovim 0.11+、系統依賴、下載本設定，並同步所有插件。

### Windows — 手動部署

> Windows 的 Neovim 安裝涉及 GUI 精靈與 PATH 設定，需要手動操作

1. 安裝 [Neovim 0.11+](https://github.com/neovim/neovim/releases/latest)（下載 `nvim-win64.msi`）
2. 安裝 [Node.js LTS](https://nodejs.org)，完成後執行 `npm install -g yarn`
3. 安裝 ripgrep：`winget install BurntSushi.ripgrep.MSVC`
4. Clone 此 repo，將資料夾內容複製到 `%LOCALAPPDATA%\nvim\`
5. 開啟 `nvim`，等待插件自動安裝完成

詳細步驟見 [docs/setup_nvchad.md](docs/setup_nvchad.md)。

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
| **圖片預覽** | chafa ASCII 預覽，SSH 遠端與 Windows Terminal 皆可用 |

---

## 文件（`docs/`）

涵蓋部署流程、設計筆記與環境調校：

| 文件 | 內容 |
|------|------|
| [`docs/setup_nvchad.md`](docs/setup_nvchad.md) | **⬅ 從這裡開始**：Linux / Windows 完整部署步驟、快捷鍵與背景知識 |
| [`docs/MSYS2_SETUP_GUIDE.md`](docs/MSYS2_SETUP_GUIDE.md) | Windows MSYS2 環境建置，讓 Telescope 搜尋速度提升 15-30 倍 |
| [`docs/X11VNC_SETUP.md`](docs/X11VNC_SETUP.md) | Jetson Orin Nano 遠端桌面（x11vnc + 顯示修正） |
| [`docs/TELESCOPE_GITIGNORE_CONFIG.md`](docs/TELESCOPE_GITIGNORE_CONFIG.md) | Telescope 大型專案搜尋慢的根因分析與優化方案 |

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
