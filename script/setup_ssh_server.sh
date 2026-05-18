#!/usr/bin/env bash
# =============================================================
# setup_ssh_server.sh
# Ubuntu SSH Server 安裝與密碼登入設定
# Usage: bash setup_ssh_server.sh
# =============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERR]${RESET}  $*"; exit 1; }
step()    { echo -e "\n${BOLD}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD} $*${RESET}"; \
            echo -e "${BOLD}══════════════════════════════════════${RESET}"; }

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"

# ─────────────────────────────────────────────────────────────
# 步驟 1：安裝 openssh-server
# ─────────────────────────────────────────────────────────────
step "步驟 1：安裝 openssh-server"

if dpkg -s openssh-server &>/dev/null; then
  success "openssh-server 已安裝，跳過"
else
  info "安裝 openssh-server..."
  sudo apt-get update -y
  sudo apt-get install -y openssh-server
  success "安裝完成"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 2：備份並修改 sshd_config
# ─────────────────────────────────────────────────────────────
step "步驟 2：設定 sshd_config"

info "備份原始設定 → $BACKUP"
sudo cp "$SSHD_CONFIG" "$BACKUP"

# 設定輔助函式：修改或新增某個 key
_set_sshd() {
  local key="$1"
  local val="$2"
  # 若 key 已存在（含被注釋的），直接替換整行；否則附加到檔尾
  if sudo grep -qiE "^#?[[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
    sudo sed -i -E "s|^#?[[:space:]]*${key}[[:space:]].*|${key} ${val}|" "$SSHD_CONFIG"
  else
    echo "${key} ${val}" | sudo tee -a "$SSHD_CONFIG" > /dev/null
  fi
}

# 允許密碼登入
_set_sshd "PasswordAuthentication" "yes"

# 保留公鑰登入（不關閉）
_set_sshd "PubkeyAuthentication" "yes"

# 詢問是否允許 root 密碼登入（預設禁止）
echo ""
echo -e "${YELLOW}是否允許 root 帳號使用密碼 SSH 登入？${RESET}"
echo -e "  ${CYAN}[1]${RESET} 禁止（建議，使用一般帳號 + sudo）"
echo -e "  ${CYAN}[2]${RESET} 允許（不建議，僅限特殊場景）"
echo ""
while true; do
  read -rp "請選擇 [1/2]：" ROOT_CHOICE
  case "$ROOT_CHOICE" in
    1)
      _set_sshd "PermitRootLogin" "prohibit-password"
      info "root 登入：僅允許金鑰，禁止密碼"
      break ;;
    2)
      _set_sshd "PermitRootLogin" "yes"
      warn "root 密碼登入已開啟（請確保 root 密碼足夠強壯）"
      break ;;
    *)
      warn "請輸入 1 或 2" ;;
  esac
done

# 詢問 SSH Port
echo ""
read -rp "SSH 監聽 Port（直接 Enter 使用預設 22）：" SSH_PORT
SSH_PORT="${SSH_PORT:-22}"
_set_sshd "Port" "$SSH_PORT"
info "SSH Port 設定為：$SSH_PORT"

success "sshd_config 設定完成"

# ─────────────────────────────────────────────────────────────
# 步驟 3：驗證設定語法
# ─────────────────────────────────────────────────────────────
step "步驟 3：驗證 sshd 設定語法"

if sudo sshd -t; then
  success "設定語法正確"
else
  error "設定有誤，已還原備份（$BACKUP）\n請手動檢查 $SSHD_CONFIG"
fi

# ─────────────────────────────────────────────────────────────
# 步驟 4：啟用並重啟 SSH 服務
# ─────────────────────────────────────────────────────────────
step "步驟 4：啟用並重啟 SSH 服務"

sudo systemctl enable ssh
sudo systemctl restart ssh
success "SSH 服務已啟動並設為開機自動啟動"

# ─────────────────────────────────────────────────────────────
# 步驟 5：防火牆（UFW）
# ─────────────────────────────────────────────────────────────
step "步驟 5：防火牆設定（UFW）"

if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
  info "UFW 已啟用，開放 Port $SSH_PORT..."
  if [[ "$SSH_PORT" == "22" ]]; then
    sudo ufw allow OpenSSH
  else
    sudo ufw allow "$SSH_PORT"/tcp
  fi
  success "UFW 規則已新增"
else
  info "UFW 未啟用或未安裝，跳過防火牆設定"
fi

# ─────────────────────────────────────────────────────────────
# 完成
# ─────────────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "（無法取得）")

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║        SSH Server 設定完成！             ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  本機 IP：${CYAN}${LOCAL_IP}${RESET}"
echo -e "  Port   ：${CYAN}${SSH_PORT}${RESET}"
echo -e "  連線指令：${YELLOW}ssh <使用者名稱>@${LOCAL_IP} -p ${SSH_PORT}${RESET}"
echo ""
echo -e "  設定備份：$BACKUP"
echo -e "  若需還原：${CYAN}sudo cp $BACKUP $SSHD_CONFIG && sudo systemctl restart ssh${RESET}"
echo ""
sudo systemctl status ssh --no-pager -l
