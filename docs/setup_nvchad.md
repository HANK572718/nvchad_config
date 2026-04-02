# NvChad 安裝與設定指南

本文件說明如何在全新 Linux 機器上安裝 Neovim、拉取個人 NvChad 設定，以及長期維護 GitHub + GitLab 雙遠端的工作流程。

---

## 前置要求

| 工具 | 最低版本 | 說明 |
|------|----------|------|
| Neovim | 0.11+ | 使用原生 `vim.lsp.config` API |
| git | 任意 | clone 與遠端管理 |
| ripgrep | 任意 | Telescope 搜尋後端 |
| Node.js | 16+ | markdown-preview、Copilot 等插件依賴 |
| yarn | 任意 | markdown-preview 建置依賴 |

`setup-nvchad.sh` 會自動安裝以上所有工具，可直接跳到 [一鍵安裝](#一鍵安裝腳本) 章節。

---

## SSH Key 設定

```bash
# 產生 ed25519 金鑰（若尚未有）
ssh-keygen -t ed25519 -C "your-email@example.com" -f ~/.ssh/id_ed25519 -N ""

# 啟動 ssh-agent 並加入金鑰
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 顯示公鑰（複製後加入平台）
cat ~/.ssh/id_ed25519.pub
```

將公鑰加入對應平台：

- **GitHub**：Settings → SSH and GPG keys → New SSH key
  `https://github.com/settings/ssh/new`
- **GitLab（自架）**：登入後 → User Settings → SSH Keys
  `https://<GITLAB_HOST>/-/profile/keys`

確認連線：

```bash
ssh -T git@github.com       # 應出現 "successfully authenticated"
ssh -T git@<GITLAB_HOST>    # 應出現 "Welcome to GitLab, @<user>!"
```

---

## 克隆設定

### 方案一：從 GitHub clone

```bash
git clone git@github.com:HANK572718/nvchad_config.git ~/.config/nvim
cd ~/.config/nvim
```

### 方案二：從自架 GitLab clone

> 請將 `<GITLAB_HOST>` 和 `<GITLAB_USER>` 替換為你的實際值。

```bash
git clone git@<GITLAB_HOST>:<GITLAB_USER>/nvchad_config.git ~/.config/nvim
cd ~/.config/nvim
```

### 方案三：跳過 nvim 設定

若只想安裝 Neovim 本體而不拉取個人設定（例如在臨時機器上），可直接跳過 clone 步驟，或在腳本中選擇「跳過」選項（見下方說明）。

---

## 雙遠端長期維護（GitHub + GitLab）

兩個平台各作為獨立的 remote，分別 push 以保持同步。

### 初次設定

```bash
cd ~/.config/nvim

# 確認目前的 origin（預設為 clone 來源）
git remote -v

# 若 origin 是 GitHub，新增 GitLab 作為第二個 remote
git remote add gitlab git@<GITLAB_HOST>:<GITLAB_USER>/nvchad_config.git

# 若 origin 是 GitLab，新增 GitHub 作為第二個 remote
git remote add github git@github.com:HANK572718/nvchad_config.git
```

確認後應看到類似：

```
origin  git@github.com:HANK572718/nvchad_config.git (fetch)
origin  git@github.com:HANK572718/nvchad_config.git (push)
gitlab  git@<GITLAB_HOST>:<GITLAB_USER>/nvchad_config.git (fetch)
gitlab  git@<GITLAB_HOST>:<GITLAB_USER>/nvchad_config.git (push)
```

### 日常推送

```bash
git push origin main   # 推往 GitHub
git push gitlab main   # 推往 GitLab（自架）
```

或封裝成 alias 方便使用：

```bash
# 加入 ~/.bashrc 或 ~/.zshrc
alias gpush='git push origin main && git push gitlab main'
```

### 從任一遠端拉取

```bash
git pull origin main   # 從 GitHub 拉
git pull gitlab main   # 從 GitLab 拉
```

---

## 一鍵安裝腳本

`setup-nvchad.sh` 整合了上述所有步驟，在全新機器上執行一條命令即可完成：

```bash
bash setup-nvchad.sh
```

腳本支援兩種安裝情境，自動偵測並提示推薦選項：

**情境 A — USB / 本機已有設定**（腳本與設定在同一目錄，或 `~/.config/nvim` 已存在）
→ 步驟 3（SSH 設定）自動略過，直接進入複製與後續步驟

**情境 B — 遠端 clone**（全新機器，無任何本機設定）
→ 完整執行 SSH 金鑰產生、平台連線確認、clone

腳本流程（共 8 步驟）：

1. 安裝系統依賴（git、ripgrep、nodejs、Neovim 0.11+）
2. **選擇設定來源**（自動偵測並推薦）
   - `[1]` 使用本機設定（USB / 已複製到本機）
   - `[2]` 從 **GitHub** clone
   - `[3]` 從 **GitLab（自架）** clone
   - `[4]` 跳過，只安裝 Neovim 本體
3. SSH Key 產生 + 平台連線確認（僅選 2 / 3 時執行）
4. 複製或 clone 設定到 `~/.config/nvim`
5. Git 身份設定 + 雙遠端設定（互動提示）
6. 安裝 yarn
7. Headless Lazy sync（安裝所有 plugins）
8. **系統管理腳本選單**（可選，多選或跳過）
   - 帳號管理、網路管理、權限管理、系統報告、VNC、顯示設定

> 若選擇 GitLab，請先在腳本頂部填入 `GITLAB_HOST` 和 `GITLAB_USER` 變數。

---

## 後續步驟

安裝完成後，開啟 Neovim 執行：

```vim
:MasonInstall pyright black isort debugpy
```

首次開啟若有 plugin 未完整安裝，可執行：

```vim
:Lazy sync
```

更多鍵位與設計說明見 [`CLAUDE.md`](../CLAUDE.md)。
