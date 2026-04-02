#!/usr/bin/env bash
# =============================================================
# setup-nvchad.sh
# 在全新 Linux 上一鍵安裝 NvChad + 個人設定
# Usage: bash setup-nvchad.sh
# =============================================================

set -euo pipefail

GITHUB_USER="HANK572718"
GITHUB_REPO="git@github.com:${GITHUB_USER}/nvchad_config.git"

# ── 自架 GitLab：請替換為你的實際主機與使用者名稱 ──────────────
GITLAB_HOST="your-gitlab.example.com"   # 例如 gitlab.mycompany.com
GITLAB_USER="your-username"
GITLAB_REPO="git@${GITLAB_HOST}:${GITLAB_USER}/nvchad_config.git"

# NVCHAD_REPO 由 Step 5a 的互動選單決定（預設 GitHub）
NVCHAD_REPO="$GITHUB_REPO"
SKIP_NVIM_CONFIG=0

GIT_NAME="deploy-bot"
GIT_EMAIL="deploy-bot@noreply.local"
SSH_KEY="$HOME/.ssh/id_ed25519"

# ── 顏色輸出 ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERR]${RESET}  $*"; exit 1; }
step()    { echo -e "\n${BOLD}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD} $*${RESET}"; \
            echo -e "${BOLD}══════════════════════════════════════${RESET}"; }

# ── 偵測套件管理器 ────────────────────────────────────────────
detect_pkg_manager() {
  if command -v apt-get &>/dev/null; then
    PKG="apt-get"
    PKG_INSTALL="sudo apt-get install -y"
    PKG_UPDATE="sudo apt-get update -y"
  elif command -v dnf &>/dev/null; then
    PKG="dnf"
    PKG_INSTALL="sudo dnf install -y"
    PKG_UPDATE="sudo dnf check-update -y || true"
  elif command -v pacman &>/dev/null; then
    PKG="pacman"
    PKG_INSTALL="sudo pacman -S --noconfirm"
    PKG_UPDATE="sudo pacman -Sy"
  else
    error "找不到支援的套件管理器（apt/dnf/pacman）"
  fi
}

# ─────────────────────────────────────────────────────────────
# 步驟 1：安裝系統依賴
# ─────────────────────────────────────────────────────────────
step "步驟 1/8：安裝系統依賴"

detect_pkg_manager
info "使用套件管理器：$PKG"
$PKG_UPDATE

PACKAGES=(git curl wget build-essential gcc make ripgrep libreadline-dev)

info "安裝系統套件..."
$PKG_INSTALL "${PACKAGES[@]}"

# nodejs / npm：nodesource 版本已內建 npm，不可再裝 apt 的 npm（會衝突）
if command -v node &>/dev/null && node --version | grep -qE '^v(1[6-9]|[2-9][0-9])'; then
  success "Node.js $(node --version) 已安裝（跳過 apt nodejs/npm）"
else
  info "安裝 nodejs..."
  $PKG_INSTALL nodejs
fi

if ! command -v npm &>/dev/null; then
  # 只在 npm 真的不存在時才嘗試從 apt 裝（非 nodesource 環境）
  $PKG_INSTALL npm 2>/dev/null || warn "npm 安裝失敗，請手動處理"
else
  success "npm $(npm --version) 已可用"
fi

# Neovim：從 GitHub Releases 安裝最新版（確保 >= 0.11）
install_neovim() {
  local ARCH
  ARCH=$(uname -m)
  local NVIM_VERSION
  NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | grep -oP 'v[\d.]+')
  local TARBALL

  case "$ARCH" in
    x86_64)  TARBALL="nvim-linux-x86_64.tar.gz" ;;
    aarch64) TARBALL="nvim-linux-arm64.tar.gz" ;;
    *)       error "不支援的架構：$ARCH" ;;
  esac

  info "下載 Neovim $NVIM_VERSION ($ARCH)..."
  local URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${TARBALL}"
  curl -L "$URL" -o "/tmp/${TARBALL}"
  tar xzf "/tmp/${TARBALL}" -C /tmp
  local EXTRACT_DIR="/tmp/${TARBALL%.tar.gz}"
  sudo install -Dm755 "${EXTRACT_DIR}/bin/nvim" /usr/local/bin/nvim
  sudo cp -r "${EXTRACT_DIR}/lib" /usr/local/
  sudo cp -r "${EXTRACT_DIR}/share" /usr/local/
  rm -rf "/tmp/${TARBALL}" "$EXTRACT_DIR"
  success "Neovim $(nvim --version | head -1) 安裝完成"
}

if command -v nvim &>/dev/null; then
  NVIM_MINOR=$(nvim --version | head -1 | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2)
  if [[ "$NVIM_MINOR" -lt 11 ]]; then
    warn "Neovim 版本過舊（< 0.11），重新安裝..."
    install_neovim
  else
    success "Neovim $(nvim --version | head -1)（已是 0.11+）"
  fi
else
  install_neovim
fi

success "系統依賴安裝完成"

# ─────────────────────────────────────────────────────────────
# 步驟 2：產生 SSH Key
# ─────────────────────────────────────────────────────────────
step "步驟 2/8：設定 SSH Key"

if [[ -f "$SSH_KEY" ]]; then
  success "SSH key 已存在：$SSH_KEY，跳過產生"
else
  info "產生 ed25519 SSH key..."
  read -rp "請輸入你的 GitHub email（用於 SSH key 註解）：" USER_EMAIL
  ssh-keygen -t ed25519 -C "$USER_EMAIL" -f "$SSH_KEY" -N ""
  success "SSH key 已產生"
fi

# 啟動 ssh-agent 並加入 key
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$SSH_KEY" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# 步驟 3：顯示公鑰，等待使用者新增至 GitHub
# ─────────────────────────────────────────────────────────────
step "步驟 3/8：新增 SSH Key 到 GitHub"

echo ""
echo -e "${YELLOW}請將以下公鑰複製，新增至 GitHub → Settings → SSH and GPG keys${RESET}"
echo ""
echo -e "${BOLD}────────── 公鑰內容（完整複製下方這行）──────────${RESET}"
cat "${SSH_KEY}.pub"
echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"
echo ""
echo -e "GitHub 新增位置：${CYAN}https://github.com/settings/ssh/new${RESET}"
echo ""
read -rp "完成新增後，按 Enter 繼續..."

# ─────────────────────────────────────────────────────────────
# 步驟 4：確認 SSH 連線
# ─────────────────────────────────────────────────────────────
step "步驟 4/8：確認 GitHub SSH 連線"

MAX_RETRY=3
for i in $(seq 1 $MAX_RETRY); do
  SSH_RESULT=$(ssh -T git@github.com 2>&1 || true)
  if echo "$SSH_RESULT" | grep -q "successfully authenticated"; then
    success "GitHub SSH 連線成功！"
    echo "$SSH_RESULT"
    break
  else
    warn "連線失敗（第 $i/$MAX_RETRY 次）：$SSH_RESULT"
    if [[ $i -lt $MAX_RETRY ]]; then
      read -rp "請確認已在 GitHub 新增公鑰，按 Enter 重試..."
    else
      error "SSH 連線失敗，請手動確認後重新執行腳本"
    fi
  fi
done

# ─────────────────────────────────────────────────────────────
# 步驟 5a：選擇 NvChad 設定來源
# ─────────────────────────────────────────────────────────────
step "步驟 5a/8：選擇設定來源"

echo ""
echo -e "請選擇要從哪裡拉取 NvChad 個人設定："
echo -e "  ${CYAN}[1]${RESET} GitHub  (${GITHUB_REPO})"
echo -e "  ${CYAN}[2]${RESET} GitLab  (${GITLAB_REPO})"
echo -e "  ${CYAN}[3]${RESET} 跳過    （只安裝 Neovim，不拉取個人設定）"
echo ""

while true; do
  read -rp "請輸入 1 / 2 / 3：" REPO_CHOICE
  case "$REPO_CHOICE" in
    1)
      NVCHAD_REPO="$GITHUB_REPO"
      info "已選擇 GitHub：$NVCHAD_REPO"
      break
      ;;
    2)
      if [[ "$GITLAB_HOST" == "your-gitlab.example.com" ]]; then
        warn "尚未設定 GITLAB_HOST / GITLAB_USER，請先編輯腳本頂部的對應變數後重新執行"
        exit 1
      fi
      NVCHAD_REPO="$GITLAB_REPO"
      info "已選擇 GitLab：$NVCHAD_REPO"
      break
      ;;
    3)
      SKIP_NVIM_CONFIG=1
      info "跳過 nvim 設定，只安裝 Neovim 本體"
      break
      ;;
    *)
      warn "請輸入 1、2 或 3"
      ;;
  esac
done

# ─────────────────────────────────────────────────────────────
# 步驟 5：Clone NvChad 設定（直接 clone 到 ~/.config/nvim）
# ─────────────────────────────────────────────────────────────
step "步驟 5/8：Clone NvChad 設定"

if [[ "$SKIP_NVIM_CONFIG" == "1" ]]; then
  info "（已跳過）不拉取 nvim 個人設定"
else

NVIM_CONFIG="$HOME/.config/nvim"

if [[ -d "$NVIM_CONFIG" ]]; then
  warn "~/.config/nvim 已存在"
  read -rp "備份並覆蓋？(y/N) " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    BACKUP="$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
    mv "$NVIM_CONFIG" "$BACKUP"
    info "已備份至 $BACKUP"
  else
    info "跳過 Clone，使用現有設定"
    cd "$NVIM_CONFIG"
    git remote set-url origin "$NVCHAD_REPO" 2>/dev/null || true
    success "確認 remote URL 正確"
    # 跳到步驟 6
  fi
fi

if [[ ! -d "$NVIM_CONFIG" ]]; then
  info "Clone $NVCHAD_REPO → $NVIM_CONFIG ..."
  git clone "$NVCHAD_REPO" "$NVIM_CONFIG"
  cd "$NVIM_CONFIG"
  success "Clone 完成，已在 $NVIM_CONFIG"
fi

fi  # end SKIP_NVIM_CONFIG

# ─────────────────────────────────────────────────────────────
# 步驟 6：設定 Git global identity
# ─────────────────────────────────────────────────────────────
step "步驟 6/8：設定 Git 身份"

git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
success "git user: $GIT_NAME <$GIT_EMAIL>"

if [[ "$SKIP_NVIM_CONFIG" != "1" ]]; then
  cd "$NVIM_CONFIG"
  success "工作目錄：$NVIM_CONFIG（remote: $(git remote get-url origin)）"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 7：安裝 yarn
# ─────────────────────────────────────────────────────────────
step "步驟 7/8：安裝 yarn（MarkdownPreview 依賴）"

if command -v yarn &>/dev/null; then
  success "yarn $(yarn --version) 已安裝"
else
  info "安裝 yarn..."
  sudo env PATH=$PATH npm install -g yarn
  success "yarn $(yarn --version) 安裝完成"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 8：首次啟動 Neovim，headless 安裝所有 plugins
# ─────────────────────────────────────────────────────────────
step "步驟 8/8：安裝 Neovim Plugins（Lazy.nvim）"

if [[ "$SKIP_NVIM_CONFIG" == "1" ]]; then
  info "（已跳過）未拉取個人設定，略過 Lazy sync"
else
  info "以 headless 模式啟動 nvim，同步所有 plugins（可能需要 2-5 分鐘）..."
  nvim --headless "+Lazy! sync" +qa 2>&1 || warn "Lazy sync 結束（部分 plugin 可能需要在 nvim 內手動完成）"
  success "Plugin 同步完成"
fi

# ─────────────────────────────────────────────────────────────
# 完成
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║        安裝完成！                        ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "下一步：開啟 nvim，執行以下指令安裝 LSP / Formatter："
echo ""
echo -e "  ${CYAN}:MasonInstall pyright black isort debugpy${RESET}"
echo ""
echo -e "常用快捷鍵（見 CLAUDE.md）："
echo -e "  ${YELLOW}<Space>ff${RESET}  - 搜尋檔案"
echo -e "  ${YELLOW}<Space>fw${RESET}  - 全域搜尋文字"
echo -e "  ${YELLOW}<F5>${RESET}       - DAP 啟動除錯"
echo ""
