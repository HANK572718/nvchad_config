#!/usr/bin/env bash
# =============================================================
# setup-nvchad.sh
# 全新 Linux 一鍵開發環境部署（x86 / ARM）
# 支援：USB 本機安裝 / GitHub clone / GitLab clone
# Usage: bash setup-nvchad.sh
# =============================================================

set -euo pipefail

# ── 使用者設定 ────────────────────────────────────────────────
GITHUB_USER="HANK572718"
GITHUB_REPO="git@github.com:${GITHUB_USER}/nvchad_config.git"

# GitLab（自架）：請替換為你的實際值
GITLAB_HOST="your-gitlab.example.com"   # ← 例如 gitlab.mycompany.com
GITLAB_USER="your-username"             # ← 你的 GitLab 帳號
GITLAB_REPO="git@${GITLAB_HOST}:${GITLAB_USER}/nvchad_config.git"

GIT_NAME="deploy-bot"
GIT_EMAIL="deploy-bot@noreply.local"
SSH_KEY="$HOME/.ssh/id_ed25519"

# ── 路徑 ──────────────────────────────────────────────────────
NVIM_CONFIG="$HOME/.config/nvim"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_FOLDER=""   # 管理腳本目錄，在步驟 4 後確定

# ── 狀態 ──────────────────────────────────────────────────────
CONFIG_MODE=""      # local / github / gitlab / skip
NVCHAD_REPO=""

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
    PKG="apt-get"; PKG_INSTALL="sudo apt-get install -y"; PKG_UPDATE="sudo apt-get update -y"
  elif command -v dnf &>/dev/null; then
    PKG="dnf"; PKG_INSTALL="sudo dnf install -y"; PKG_UPDATE="sudo dnf check-update -y || true"
  elif command -v pacman &>/dev/null; then
    PKG="pacman"; PKG_INSTALL="sudo pacman -S --noconfirm"; PKG_UPDATE="sudo pacman -Sy"
  else
    error "找不到支援的套件管理器（apt/dnf/pacman）"
  fi
}

# ── 偵測本機設定狀態 ──────────────────────────────────────────
# 回傳值：
#   local_other  → 在 SCRIPT_DIR 找到設定，但不在 NVIM_CONFIG（USB / 其他路徑）
#   local_nvim   → 腳本就是從 NVIM_CONFIG 執行（已在正確位置）
#   exists       → NVIM_CONFIG 已有設定（腳本從別處執行）
#   none         → 完全沒有本機設定
detect_local_config() {
  if [[ -f "$SCRIPT_DIR/lua/chadrc.lua" && "$SCRIPT_DIR" != "$NVIM_CONFIG" ]]; then
    echo "local_other"
  elif [[ "$SCRIPT_DIR" == "$NVIM_CONFIG" && -f "$NVIM_CONFIG/lua/chadrc.lua" ]]; then
    echo "local_nvim"
  elif [[ -d "$NVIM_CONFIG" && -f "$NVIM_CONFIG/lua/chadrc.lua" ]]; then
    echo "exists"
  else
    echo "none"
  fi
}

# ─────────────────────────────────────────────────────────────
# 步驟 1：安裝系統依賴 + Neovim
# ─────────────────────────────────────────────────────────────
step "步驟 1：安裝系統依賴"

detect_pkg_manager
info "使用套件管理器：$PKG"
$PKG_UPDATE

PACKAGES=(git curl wget build-essential gcc make ripgrep libreadline-dev)
info "安裝系統套件..."
$PKG_INSTALL "${PACKAGES[@]}"

# nodejs / npm（nodesource 版本已內建 npm，不可重複安裝 apt npm）
if command -v node &>/dev/null && node --version | grep -qE '^v(1[6-9]|[2-9][0-9])'; then
  success "Node.js $(node --version) 已安裝"
else
  info "安裝 nodejs..."
  $PKG_INSTALL nodejs
fi

if ! command -v npm &>/dev/null; then
  $PKG_INSTALL npm 2>/dev/null || warn "npm 安裝失敗，請手動處理"
else
  success "npm $(npm --version) 已可用"
fi

# Neovim：從 GitHub Releases 安裝最新版（確保 >= 0.11）
install_neovim() {
  local ARCH; ARCH=$(uname -m)
  local NVIM_VERSION
  NVIM_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest \
    | grep '"tag_name"' | grep -oP 'v[\d.]+')
  local TARBALL
  case "$ARCH" in
    x86_64)  TARBALL="nvim-linux-x86_64.tar.gz" ;;
    aarch64) TARBALL="nvim-linux-arm64.tar.gz" ;;
    *)       error "不支援的架構：$ARCH" ;;
  esac
  info "下載 Neovim $NVIM_VERSION ($ARCH)..."
  curl -L "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${TARBALL}" \
    -o "/tmp/${TARBALL}"
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
# 步驟 2：選擇 NvChad 設定來源
# ─────────────────────────────────────────────────────────────
step "步驟 2：選擇設定來源"

LOCAL_STATUS=$(detect_local_config)

echo ""
case "$LOCAL_STATUS" in
  local_other)
    echo -e "${GREEN}[自動偵測]${RESET} 在 ${BOLD}$SCRIPT_DIR${RESET} 找到 NvChad 設定（USB / 本機複製）"
    echo -e "  ${CYAN}[1]${RESET} 使用本機設定 ${YELLOW}← 推薦${RESET}  （複製 $SCRIPT_DIR → $NVIM_CONFIG）"
    ;;
  local_nvim)
    echo -e "${GREEN}[自動偵測]${RESET} 腳本從設定目錄執行，設定已在 ${BOLD}$NVIM_CONFIG${RESET}"
    echo -e "  ${CYAN}[1]${RESET} 使用現有設定（原地繼續）${YELLOW}← 推薦${RESET}"
    ;;
  exists)
    echo -e "${YELLOW}[偵測]${RESET} ${BOLD}$NVIM_CONFIG${RESET} 已有個人設定"
    echo -e "  ${CYAN}[1]${RESET} 使用現有設定（不覆蓋）${YELLOW}← 推薦${RESET}"
    ;;
  none)
    echo -e "${CYAN}[INFO]${RESET} 未偵測到本機設定，請選擇遠端來源"
    echo -e "  ${CYAN}[1]${RESET} 使用本機設定  ${YELLOW}（未偵測到，選此項無效）${RESET}"
    ;;
esac
echo -e "  ${CYAN}[2]${RESET} 從 GitHub clone   ($GITHUB_REPO)"
echo -e "  ${CYAN}[3]${RESET} 從 GitLab clone   ($GITLAB_REPO)"
echo -e "  ${CYAN}[4]${RESET} 跳過              （只安裝 Neovim，不設定 nvim）"
echo ""

while true; do
  read -rp "請輸入選項 [1-4]：" REPO_CHOICE
  case "$REPO_CHOICE" in
    1)
      if [[ "$LOCAL_STATUS" == "none" ]]; then
        warn "未偵測到本機設定，請選擇 2、3 或 4"
        continue
      fi
      CONFIG_MODE="local"
      info "已選擇本機設定"
      break
      ;;
    2)
      CONFIG_MODE="github"
      NVCHAD_REPO="$GITHUB_REPO"
      info "已選擇 GitHub：$NVCHAD_REPO"
      break
      ;;
    3)
      if [[ "$GITLAB_HOST" == "your-gitlab.example.com" ]]; then
        warn "尚未設定 GITLAB_HOST / GITLAB_USER，請先編輯腳本頂部的對應變數後重新執行"
        exit 1
      fi
      CONFIG_MODE="gitlab"
      NVCHAD_REPO="$GITLAB_REPO"
      info "已選擇 GitLab：$NVCHAD_REPO"
      break
      ;;
    4)
      CONFIG_MODE="skip"
      info "跳過 nvim 設定"
      break
      ;;
    *)
      warn "請輸入 1、2、3 或 4"
      ;;
  esac
done

# ─────────────────────────────────────────────────────────────
# 步驟 3：SSH 設定（僅遠端 clone 需要）
# ─────────────────────────────────────────────────────────────
if [[ "$CONFIG_MODE" == "github" || "$CONFIG_MODE" == "gitlab" ]]; then

  step "步驟 3：設定 SSH Key"

  if [[ -f "$SSH_KEY" ]]; then
    success "SSH key 已存在：$SSH_KEY，跳過產生"
  else
    info "產生 ed25519 SSH key..."
    read -rp "請輸入 email（用於 SSH key 註解）：" USER_EMAIL
    ssh-keygen -t ed25519 -C "$USER_EMAIL" -f "$SSH_KEY" -N ""
    success "SSH key 已產生"
  fi

  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$SSH_KEY" 2>/dev/null || true

  # 依來源決定平台資訊
  if [[ "$CONFIG_MODE" == "github" ]]; then
    PLATFORM_NAME="GitHub"
    PLATFORM_KEYS_URL="https://github.com/settings/ssh/new"
    SSH_HOST="git@github.com"
    SSH_CHECK_KEYWORD="successfully authenticated"
  else
    PLATFORM_NAME="GitLab（${GITLAB_HOST}）"
    PLATFORM_KEYS_URL="https://${GITLAB_HOST}/-/profile/keys"
    SSH_HOST="git@${GITLAB_HOST}"
    SSH_CHECK_KEYWORD="Welcome to GitLab"
  fi

  step "步驟 3b：新增 SSH Key 到 ${PLATFORM_NAME}"
  echo ""
  echo -e "${YELLOW}請將以下公鑰新增至 ${PLATFORM_NAME} → SSH Keys${RESET}"
  echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"
  cat "${SSH_KEY}.pub"
  echo -e "${BOLD}──────────────────────────────────────────────────${RESET}"
  echo -e "新增位置：${CYAN}${PLATFORM_KEYS_URL}${RESET}"
  echo ""
  read -rp "完成後按 Enter 繼續..."

  step "步驟 3c：確認 SSH 連線（${PLATFORM_NAME}）"
  MAX_RETRY=3
  for i in $(seq 1 $MAX_RETRY); do
    SSH_RESULT=$(ssh -T "$SSH_HOST" 2>&1 || true)
    if echo "$SSH_RESULT" | grep -qi "$SSH_CHECK_KEYWORD"; then
      success "${PLATFORM_NAME} SSH 連線成功！"
      break
    else
      warn "連線失敗（第 $i/$MAX_RETRY 次）：$SSH_RESULT"
      if [[ $i -lt $MAX_RETRY ]]; then
        read -rp "請確認已在 ${PLATFORM_NAME} 新增公鑰，按 Enter 重試..."
      else
        error "SSH 連線失敗，請手動確認後重新執行腳本"
      fi
    fi
  done

fi  # end SSH section

# ─────────────────────────────────────────────────────────────
# 步驟 4：部署 / Clone NvChad 設定
# ─────────────────────────────────────────────────────────────
step "步驟 4：部署 NvChad 設定"

_backup_existing_nvim() {
  if [[ -d "$NVIM_CONFIG" ]]; then
    warn "~/.config/nvim 已存在"
    read -rp "備份並覆蓋？(y/N) " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
      BACKUP="$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"
      mv "$NVIM_CONFIG" "$BACKUP"
      info "已備份至 $BACKUP"
      return 0  # 已清除，可繼續
    fi
    return 1  # 保留現有
  fi
  return 0  # 目錄不存在，可繼續
}

case "$CONFIG_MODE" in
  local)
    case "$LOCAL_STATUS" in
      local_other)
        if _backup_existing_nvim; then
          if [[ ! -d "$NVIM_CONFIG" ]]; then
            info "複製 $SCRIPT_DIR → $NVIM_CONFIG ..."
            cp -a "$SCRIPT_DIR" "$NVIM_CONFIG"
            success "複製完成"
          fi
        else
          info "保留現有設定，繼續後續步驟"
        fi
        ;;
      local_nvim | exists)
        success "設定已在 $NVIM_CONFIG，無需搬移"
        ;;
    esac
    ;;

  github | gitlab)
    if _backup_existing_nvim; then
      if [[ ! -d "$NVIM_CONFIG" ]]; then
        info "Clone $NVCHAD_REPO → $NVIM_CONFIG ..."
        git clone "$NVCHAD_REPO" "$NVIM_CONFIG"
        success "Clone 完成"
      fi
    else
      info "保留現有設定，更新 remote origin"
      cd "$NVIM_CONFIG"
      git remote set-url origin "$NVCHAD_REPO" 2>/dev/null || true
      success "remote origin 已更新"
    fi
    ;;

  skip)
    info "（已跳過）不部署 nvim 個人設定"
    ;;
esac

# 確定管理腳本目錄位置
if [[ -d "$NVIM_CONFIG/script" ]]; then
  SCRIPTS_FOLDER="$NVIM_CONFIG/script"
elif [[ -d "$SCRIPT_DIR/script" ]]; then
  SCRIPTS_FOLDER="$SCRIPT_DIR/script"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 5：Git 身份 + 雙遠端設定
# ─────────────────────────────────────────────────────────────
step "步驟 5：設定 Git 身份"

git config --global user.name  "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
success "git user: $GIT_NAME <$GIT_EMAIL>"

if [[ "$CONFIG_MODE" != "skip" && -d "$NVIM_CONFIG/.git" ]]; then
  cd "$NVIM_CONFIG"
  CURRENT_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "（未設定）")
  success "工作目錄：$NVIM_CONFIG（origin: $CURRENT_ORIGIN）"

  # 提示設定第二遠端（雙遠端長期維護）
  HAVE_GITLAB=$(git remote | grep -q "^gitlab$" && echo "yes" || echo "no")
  HAVE_GITHUB=$(git remote | grep -q "^github$" && echo "yes" || echo "no")

  if [[ "$HAVE_GITLAB" == "no" && "$GITLAB_HOST" != "your-gitlab.example.com" ]]; then
    echo ""
    read -rp "是否設定 GitLab 為第二遠端 (gitlab remote)？(y/N) " ADD_GITLAB
    if [[ "$ADD_GITLAB" =~ ^[Yy]$ ]]; then
      git remote add gitlab "$GITLAB_REPO"
      success "已新增 remote: gitlab → $GITLAB_REPO"
    fi
  fi

  if [[ "$HAVE_GITHUB" == "no" && "$CURRENT_ORIGIN" != *"github.com"* ]]; then
    echo ""
    read -rp "是否設定 GitHub 為第二遠端 (github remote)？(y/N) " ADD_GITHUB
    if [[ "$ADD_GITHUB" =~ ^[Yy]$ ]]; then
      git remote add github "$GITHUB_REPO"
      success "已新增 remote: github → $GITHUB_REPO"
    fi
  fi

  echo ""
  info "目前 remotes："
  git remote -v
fi

# ─────────────────────────────────────────────────────────────
# 步驟 6：安裝 yarn
# ─────────────────────────────────────────────────────────────
step "步驟 6：安裝 yarn（MarkdownPreview 依賴）"

if command -v yarn &>/dev/null; then
  success "yarn $(yarn --version) 已安裝"
else
  info "安裝 yarn..."
  sudo env PATH=$PATH npm install -g yarn
  success "yarn $(yarn --version) 安裝完成"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 7：Neovim Plugin 同步（Lazy.nvim）
# ─────────────────────────────────────────────────────────────
step "步驟 7：安裝 Neovim Plugins（Lazy.nvim）"

if [[ "$CONFIG_MODE" == "skip" ]]; then
  info "（已跳過）未部署個人設定，略過 Lazy sync"
else
  info "以 headless 模式啟動 nvim，同步所有 plugins（可能需要 2-5 分鐘）..."
  nvim --headless "+Lazy! sync" +qa 2>&1 \
    || warn "Lazy sync 結束（部分 plugin 可能需要在 nvim 內手動完成）"
  success "Plugin 同步完成"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 8（可選）：執行系統管理腳本
# ─────────────────────────────────────────────────────────────
step "步驟 8：系統管理腳本（可選）"

if [[ -z "$SCRIPTS_FOLDER" ]]; then
  warn "找不到 script/ 目錄，跳過此步驟"
else
  # 腳本清單：格式 "檔名|說明"
  SCRIPT_NAMES=(
    "account-manager.sh"
    "net-manager.sh"
    "perm-manager.sh"
    "sysreport.sh"
    "setup_x11vnc.sh"
    "setup-display.sh"
  )
  SCRIPT_DESCS=(
    "帳號管理（建立使用者、設定群組、修復家目錄權限）"
    "網路管理（網卡設定、IP、DNS）"
    "權限管理（檔案與目錄權限修復）"
    "系統報告（查看系統狀態與硬體資訊）"
    "VNC 遠端桌面（x11vnc + systemd，Jetson / Ubuntu）"
    "顯示設定（xorg.conf + 60Hz 修正，Jetson 系列）"
  )

  echo ""
  echo -e "以下腳本可在部署後立即執行，請選擇要執行的項目："
  echo -e "（輸入數字如 ${CYAN}1 3${RESET}，多個以空格分隔；${CYAN}all${RESET} 全選；${CYAN}0${RESET} 或直接 Enter 跳過）"
  echo ""

  MAX_IDX=${#SCRIPT_NAMES[@]}
  for (( i=0; i<MAX_IDX; i++ )); do
    DISP_NUM=$((i+1))
    FNAME="${SCRIPT_NAMES[$i]}"
    FDESC="${SCRIPT_DESCS[$i]}"
    if [[ -f "$SCRIPTS_FOLDER/$FNAME" ]]; then
      echo -e "  ${CYAN}[$DISP_NUM]${RESET} $FDESC"
    else
      echo -e "  ${YELLOW}[$DISP_NUM]${RESET} $FDESC  ${YELLOW}（腳本不存在）${RESET}"
    fi
  done
  echo ""

  read -rp "請輸入選項：" SCRIPT_SELECTION

  if [[ -z "$SCRIPT_SELECTION" || "$SCRIPT_SELECTION" == "0" ]]; then
    info "跳過系統管理腳本"
  else
    if [[ "$SCRIPT_SELECTION" == "all" ]]; then
      SELECTED_IDXS=()
      for (( i=0; i<MAX_IDX; i++ )); do SELECTED_IDXS+=($i); done
    else
      SELECTED_IDXS=()
      for num in $SCRIPT_SELECTION; do
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= MAX_IDX )); then
          SELECTED_IDXS+=($((num-1)))
        else
          warn "無效選項：$num，跳過"
        fi
      done
    fi

    for idx in "${SELECTED_IDXS[@]}"; do
      FNAME="${SCRIPT_NAMES[$idx]}"
      FDESC="${SCRIPT_DESCS[$idx]}"
      FPATH="$SCRIPTS_FOLDER/$FNAME"
      if [[ -f "$FPATH" ]]; then
        echo ""
        step "執行：$FDESC"
        bash "$FPATH" || warn "$FNAME 執行過程有警告，請檢查輸出"
      else
        warn "找不到腳本：$FPATH，跳過"
      fi
    done
  fi
fi

# ─────────────────────────────────────────────────────────────
# 完成
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║        部署完成！                        ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
if [[ "$CONFIG_MODE" != "skip" ]]; then
  echo -e "下一步：開啟 nvim，安裝 LSP / Formatter："
  echo -e "  ${CYAN}:MasonInstall pyright black isort debugpy${RESET}"
  echo ""
fi
echo -e "常用快捷鍵："
echo -e "  ${YELLOW}<Space>ff${RESET}  搜尋檔案   ${YELLOW}<Space>fw${RESET}  全域搜尋   ${YELLOW}<F5>${RESET}  DAP 除錯"
echo ""
