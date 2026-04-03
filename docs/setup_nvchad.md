# NvChad 設定部署指南

本設定以 [NvChad](https://github.com/NvChad/NvChad) 為基礎客製化，支援 **Linux（x86 / ARM）** 與 **Windows（MSYS2）** 兩種平台。
Clone 此 repo 後依照本文件操作，幾分鐘內即可完成開發環境部署。

---

## 選擇部署方式

| 情境 | 建議路線 |
|------|----------|
| Linux，想一條命令搞定 | [一鍵腳本](#一鍵腳本linux) |
| Linux，自行 clone 後手動部署 | [Linux 手動部署](#linux-手動部署) |
| Windows，手動安裝工具後套用設定 | [Windows 手動部署](#windows-手動部署) |

---

## 前置要求

| 工具 | 最低版本 | 用途 |
|------|----------|------|
| Neovim | **0.11+** | 使用原生 LSP API，版本不可低於此 |
| git | 任意 | clone 此 repo |
| ripgrep | 任意 | Telescope 檔案搜尋後端 |
| Node.js | 16+ | markdown-preview 等插件依賴 |
| yarn | 任意 | markdown-preview 建置依賴 |

---

## Linux 手動部署

適合：已自行 clone 此 repo，或想完全掌控每個步驟的使用者。

### 1. 安裝系統依賴

```bash
# Debian / Ubuntu / Raspberry Pi OS / Jetson
sudo apt-get update
sudo apt-get install -y git curl ripgrep build-essential nodejs npm

# 安裝 yarn
sudo npm install -g yarn
```

### 2. 安裝 Neovim 0.11+

發行版的 apt 通常版本過舊，建議從 GitHub Releases 直接安裝：

```bash
# 偵測架構後下載對應版本
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  TARBALL="nvim-linux-x86_64.tar.gz" ;;
  aarch64) TARBALL="nvim-linux-arm64.tar.gz" ;;
esac

VER=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest \
  | grep '"tag_name"' | grep -oP 'v[\d.]+')

curl -L "https://github.com/neovim/neovim/releases/download/${VER}/${TARBALL}" -o /tmp/nvim.tar.gz
tar xzf /tmp/nvim.tar.gz -C /tmp
sudo install -Dm755 /tmp/${TARBALL%.tar.gz}/bin/nvim /usr/local/bin/nvim

nvim --version   # 確認顯示 0.11+
```

### 3. 將此 repo 放到 Neovim 設定目錄

```bash
# 方法 A：直接 clone 到目標位置
git clone https://github.com/HANK572718/nvchad_config.git ~/.config/nvim

# 方法 B：若已 clone 在其他目錄，複製過去
cp -a /path/to/nvchad_config/. ~/.config/nvim/

# 方法 C：若從 USB 執行，在 repo 根目錄下
cp -a . ~/.config/nvim/
```

> 若 `~/.config/nvim` 已存在，先備份再放入：
> ```bash
> mv ~/.config/nvim ~/.config/nvim.bak
> ```

### 4. 開啟 Neovim，等待自動安裝

```bash
nvim
```

首次開啟時 lazy.nvim 會自動下載並安裝所有插件，**等待安裝完成後重啟 nvim 即可**。

若想以 headless 模式預先安裝（不開 UI）：

```bash
nvim --headless "+Lazy! sync" +qa
```

---

## Windows 手動部署

適合：Windows 環境，圖形介面工具需要手動安裝，最後套用 nvim 設定。

### 1. 安裝 Neovim

前往 [Neovim Releases](https://github.com/neovim/neovim/releases/latest) 下載 `nvim-win64.msi`，執行安裝精靈。

或使用 winget：
```powershell
winget install Neovim.Neovim
```

安裝後確認版本（在 PowerShell 或 cmd）：
```powershell
nvim --version
```

### 2. 安裝 Node.js 與 yarn

至 [nodejs.org](https://nodejs.org) 下載 LTS 版安裝，安裝後：

```powershell
npm install -g yarn
```

### 3. 安裝 ripgrep

```powershell
winget install BurntSushi.ripgrep.MSVC
```

或至 [ripgrep Releases](https://github.com/BurntSushi/ripgrep/releases) 下載 `ripgrep-x86_64-pc-windows-msvc.zip`，解壓後將 `rg.exe` 加入 PATH。

### 4. 取得此 repo

```powershell
# clone（需先安裝 git：winget install Git.Git）
git clone https://github.com/HANK572718/nvchad_config.git

# 或直接從 GitHub 下載 ZIP 解壓
```

### 5. 複製設定到 Neovim 設定目錄

Windows 的 Neovim 設定目錄為 `%LOCALAPPDATA%\nvim`，通常是：

```
C:\Users\<你的使用者名稱>\AppData\Local\nvim\
```

在 PowerShell 中執行：

```powershell
# 若目錄已存在先備份
$nvimDir = "$env:LOCALAPPDATA\nvim"
if (Test-Path $nvimDir) {
    Rename-Item $nvimDir "$nvimDir.bak"
}

# 複製 repo 內容到設定目錄
Copy-Item -Path ".\nvchad_config\*" -Destination $nvimDir -Recurse -Force
```

或者直接在檔案總管中：將 repo 資料夾改名為 `nvim` 後放入 `AppData\Local\` 即可。

### 6. 開啟 Neovim

開啟 PowerShell 或 Windows Terminal，輸入：

```powershell
nvim
```

首次開啟時 lazy.nvim 會自動安裝所有插件，等待完成後重啟即可使用。

---

## 一鍵腳本（Linux）

Linux 平台可使用 `setup-nvchad.sh` 自動完成以上所有步驟：

```bash
# 若已 clone 此 repo
bash setup-nvchad.sh

# 或直接從網路執行
bash <(curl -fsSL https://raw.githubusercontent.com/HANK572718/nvchad_config/main/setup-nvchad.sh)
```

腳本會自動偵測本機狀態、選擇安裝來源（本機 / GitHub / GitLab），並在最後提供系統管理腳本選單。

---

## 首次開啟後的設定

安裝完成後，進入 nvim 執行以下指令安裝 LSP 與格式化工具：

```vim
:MasonInstall pyright black isort debugpy
```

| 工具 | 用途 |
|------|------|
| `pyright` | Python 語言伺服器（LSP） |
| `black` | Python 格式化 |
| `isort` | import 排序 |
| `debugpy` | Python 除錯（DAP） |

若插件未完整安裝，可手動觸發同步：

```vim
:Lazy sync
```

---

## Neovim 背景知識

### 模式編輯（Modal Editing）

Neovim 最核心的概念：不同模式下鍵盤有不同用途，手不必離開主鍵區。

| 模式 | 進入方式 | 用途 |
|------|----------|------|
| **Normal** | `Esc` 或 `jk` | 預設模式，移動游標、執行操作 |
| **Insert** | `i` / `a` / `o` | 輸入文字，像一般編輯器 |
| **Visual** | `v`（字元）`V`（整行）`Ctrl-v`（區塊） | 選取文字後批次操作 |
| **Command** | `;` 或 `:` | 執行指令，如 `:w` 存檔、`:q` 離開 |

> **新手提示**：卡住按 `Esc`（或 `jk`）回到 Normal 模式，再按 `;q!` 強制離開。

### Leader 鍵

本設定的 Leader 鍵為 `Space`（空白鍵）。大部分功能快捷鍵格式為：

```
<Space> + 一或兩個字母
```

例如 `<Space>ff` = 按住空白鍵，再按 `f`、`f`。

### NvChad 架構

```
NvChad（UI 框架 + 基礎設定）
  └─ lazy.nvim（插件管理器）
       ├─ nvim-tree（檔案樹）
       ├─ Telescope（模糊搜尋）
       ├─ nvim-cmp（自動補全）
       └─ ... 其餘插件
本 repo 的 lua/ 在上面追加：LSP、DAP、格式化、個人鍵位
```

- 首次開啟時 lazy.nvim 自動下載所有插件
- 輸入 `:Lazy` 可查看插件狀態
- 輸入 `<Space>ch` 可開啟 NvChad 內建快捷鍵速查表

---

## 快捷鍵總覽

### 模式切換

| 按鍵 | 動作 |
|------|------|
| `i` | 游標前進入 Insert |
| `a` | 游標後進入 Insert |
| `o` | 新增下一行並進入 Insert |
| `jk` | Insert → Normal（本設定自訂） |
| `;` | Normal → Command（本設定自訂，取代 `:`） |
| `v` / `V` | 進入 Visual / Visual Line |

### 檔案與搜尋

| 按鍵 | 動作 |
|------|------|
| `<Space>ff` | 搜尋檔案（遵守 .gitignore） |
| `<Space>fF` | 搜尋所有檔案（含隱藏 / ignored） |
| `<Space>fw` | 全域搜尋文字（live grep） |
| `<Space>fW` | 全域搜尋（含 ignored 目錄） |
| `<Space>fb` | 搜尋已開啟的 buffer |
| `<Space>e` | 開關檔案樹（nvim-tree） |

### 緩衝區（Buffer）與視窗

| 按鍵 | 動作 |
|------|------|
| `<Alt-1>` ~ `<Alt-9>` | 直接跳到第 N 個 buffer |
| `<Space>x` | 關閉目前 buffer |
| `<Ctrl-h/j/k/l>` | 跨視窗移動游標 |

### LSP（語言伺服器）

| 按鍵 | 動作 |
|------|------|
| `gd` | 跳到定義 |
| `gI` / `gr` | 查找所有引用 |
| `K` | 顯示文件說明（hover） |
| `<Space>o` | 目前檔案的符號清單 |
| `<Space>O` | 整個專案的符號清單 |
| `<Space>ci` | 查看誰呼叫此函式（incoming calls） |
| `<Space>co` | 查看此函式呼叫了誰（outgoing calls） |
| `<Space>ra` | 重新命名符號 |
| `<Space>ca` | Code action |
| `[d` / `]d` | 上 / 下一個診斷錯誤 |

### 除錯（DAP）

| 按鍵 | 動作 |
|------|------|
| `<F5>` | 啟動 / 繼續除錯 |
| `<F10>` | Step over（跨過） |
| `<F11>` | Step into（進入） |
| `<F12>` | Step out（跳出） |
| `<Space>db` | 切換中斷點 |
| `<Space>du` | 開關除錯 UI |

### 終端機

| 按鍵 | 動作 |
|------|------|
| `<Space>h` | 水平分割終端機 |
| `<Space>v` | 垂直分割終端機 |
| `<Ctrl-x>` | 在終端機內切回 Normal 模式 |

> 完整鍵位定義見 [`lua/mappings.lua`](../lua/mappings.lua)，NvChad 原生鍵位見 `<Space>ch`。
