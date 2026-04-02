# 個人 Neovim 設定與 Linux 部署工具箱

本 repo 圍繞兩個核心目標持續維護：

1. **Neovim 設定優化**——以 NvChad v2.5 為基礎，針對日常開發需求深度客製化
2. **Linux 部署與管理腳本**——快速在全新機器上建立一致的工作環境

---

## Neovim 設定（`lua/`）

以 [NvChad](https://github.com/NvChad/NvChad) 作為插件載入，主要客製化方向：

| 面向 | 說明 |
|------|------|
| **LSP** | Pyright（Neovim 0.11+ 原生 API），自動偵測 `.venv` |
| **除錯** | nvim-dap + nvim-dap-ui，自動載入 `.vscode/launch.json` |
| **搜尋** | Telescope + MSYS2 fd，解決大型專案搜尋慢的問題 |
| **格式化** | conform.nvim（black + isort） |
| **狀態列** | 依視窗寬度動態隱藏模組，窄視窗也不擁擠 |
| **圖片預覽** | chafa ASCII 預覽，SSH 遠端也能用 |

詳細鍵位與設計決策見 [`CLAUDE.md`](CLAUDE.md)。

---

## Linux 部署腳本（`script/`）

集中管理在全新 Linux 機器上快速部署與日常維護的 shell 腳本：

| 腳本 | 用途 |
|------|------|
| [`setup-nvchad.sh`](setup-nvchad.sh) | 一鍵安裝 Neovim + 拉取個人設定（支援 GitHub / GitLab / 跳過） |
| `setup_x11vnc.sh` | 部署 x11vnc 遠端桌面服務（含 systemd service） |
| `setup-display.sh` | 部署 xorg.conf 與顯示模式腳本（Jetson 系列） |
| `display-mode.sh` | 強制 DP-0 以 60Hz 輸出（修正被動式 DP→HDMI 轉接器問題） |
| `x11vnc-wrapper.sh` | 動態追蹤 Xorg 狀態，自動銜接 VT 切換 |
| `account-manager.sh` | 使用者帳號管理（建立 / 設定群組 / 修復家目錄權限） |
| `net-manager.sh` | 網路設定與介面管理 |
| `perm-manager.sh` | 檔案與目錄權限管理 |
| `sysreport.sh` | 系統狀態報告 |

---

## 踩坑文件（`docs/`）

記錄 Neovim 與 Linux 環境配置過程中遇到的實際問題與解法：

| 文件 | 內容 |
|------|------|
| [`docs/setup_nvchad.md`](docs/setup_nvchad.md) | NvChad 完整安裝流程、雙遠端（GitHub + GitLab）維護方式 |
| [`docs/X11VNC_SETUP.md`](docs/X11VNC_SETUP.md) | Jetson Orin Nano 遠端桌面完整設定（x11vnc + 顯示修正） |
| [`docs/MSYS2_SETUP_GUIDE.md`](docs/MSYS2_SETUP_GUIDE.md) | Windows MSYS2 開發環境建立，Telescope fd 加速 |
| [`docs/TELESCOPE_GITIGNORE_CONFIG.md`](docs/TELESCOPE_GITIGNORE_CONFIG.md) | 大型專案 Telescope 搜尋慢的根因分析與優化方案 |

---

## 快速開始

```bash
# 全自動安裝（安裝 Neovim + 拉取本設定）
bash <(curl -fsSL https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.sh)
```

詳細步驟與雙遠端設定見 [`docs/setup_nvchad.md`](docs/setup_nvchad.md)。
