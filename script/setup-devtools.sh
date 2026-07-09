#!/usr/bin/env bash
# =====================================================
# setup-devtools.sh — tmux + jumpfwd(jf) 一鍵設定
#
# 把這台樹莓派上「終端多工（tmux）」與「port 轉發（jumpfwd/jf）」
# 兩套系統工具的設定與現況，複製到其他 Linux 機器（含 x86_64）。
# 跨發行版（apt / dnf / pacman / zypper）、互動式、可重複執行（冪等）。
#
#   上游入口：~/.config/nvim/script/setup-devtools.sh
#   內附資產：~/.config/nvim/script/devtools/
#             ├── tmux.conf                     tmux 設定（部署到 ~/.tmux.conf）
#             └── jumpfwd/
#                 ├── jf                        JumpForward CLI（部署到 ~/.local/bin/jf）
#                 ├── config.example.json       去識別化範例設定
#                 └── README.md                 jf 完整手冊
#   說明文件：~/.config/nvim/docs/DEVTOOLS_SETUP.md
# =====================================================

set -euo pipefail

# --- 路徑 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS_DIR="$SCRIPT_DIR/devtools"
TMUX_SRC="$DEVTOOLS_DIR/tmux.conf"
JF_SRC="$DEVTOOLS_DIR/jumpfwd/jf"
JF_CONF_EXAMPLE="$DEVTOOLS_DIR/jumpfwd/config.example.json"

# --- 顏色 ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()   { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()     { echo -e "${GREEN}✔${NC}  $*"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $*"; }
err()    { echo -e "${RED}✘${NC}  $*" >&2; }
die()    { err "$*"; exit 1; }
header() { echo -e "\n${BOLD}${CYAN}$*${NC}"; echo -e "${DIM}$(printf '─%.0s' {1..56})${NC}"; }

# =====================================================
# 套件管理器抽象（跨發行版）
# =====================================================
PM=""
detect_pm() {
    if   command -v apt-get &>/dev/null; then PM="apt"
    elif command -v dnf     &>/dev/null; then PM="dnf"
    elif command -v pacman  &>/dev/null; then PM="pacman"
    elif command -v zypper  &>/dev/null; then PM="zypper"
    else PM="unknown"; fi
}

# pkg_install <pkg...> — 只安裝尚未存在的套件（以對應的可執行檔判斷）
pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return 0
    [[ "$PM" == "unknown" ]] && { warn "無法辨識套件管理器，請手動安裝：${pkgs[*]}"; return 0; }
    local SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
    info "安裝套件（$PM）：${pkgs[*]}"
    case "$PM" in
        apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y "${pkgs[@]}" ;;
        dnf)    $SUDO dnf install -y "${pkgs[@]}" ;;
        pacman) $SUDO pacman -S --needed --noconfirm "${pkgs[@]}" ;;
        zypper) $SUDO zypper install -y "${pkgs[@]}" ;;
    esac
}

have() { command -v "$1" &>/dev/null; }

# 確保 ~/.local/bin 在 PATH（寫進 ~/.bashrc，冪等）
ensure_local_bin_path() {
    mkdir -p "$HOME/.local/bin"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) return 0 ;;
    esac
    if ! grep -qs '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ''
            echo '# 由 setup-devtools.sh 加入：讓 ~/.local/bin 裡的工具（如 jf）可直接執行'
            echo 'export PATH="$HOME/.local/bin:$PATH"'
        } >> "$HOME/.bashrc"
        warn "已把 ~/.local/bin 加入 ~/.bashrc 的 PATH，請重開 shell 或執行：source ~/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
}

backup_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    local bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$f" "$bak"
    info "已備份既有檔案 → $bak"
}

# =====================================================
# tmux
# =====================================================
setup_tmux() {
    header "設定 tmux"
    [[ -f "$TMUX_SRC" ]] || die "找不到 tmux 設定來源：$TMUX_SRC"

    have tmux || pkg_install tmux
    have git  || pkg_install git
    have tmux || die "tmux 安裝失敗，請手動安裝後重試"
    ok "tmux 已就緒：$(tmux -V)"

    # 部署 ~/.tmux.conf（先備份差異）
    if [[ -f "$HOME/.tmux.conf" ]] && ! cmp -s "$TMUX_SRC" "$HOME/.tmux.conf"; then
        backup_file "$HOME/.tmux.conf"
    fi
    cp "$TMUX_SRC" "$HOME/.tmux.conf"
    ok "已部署 ~/.tmux.conf"

    # 安裝 tpm（tmux plugin manager）
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ -d "$tpm_dir/.git" ]]; then
        info "tpm 已存在，更新中…"
        git -C "$tpm_dir" pull --ff-only --quiet 2>/dev/null || true
    else
        info "clone tpm…"
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir" --quiet
    fi
    ok "tpm 已就緒"

    # headless 安裝插件（tmux-resurrect 等）
    info "安裝 tmux 插件（headless）…"
    if tmux start-server 2>/dev/null && tmux new-session -d -s __tpm_bootstrap 2>/dev/null; then
        "$tpm_dir/bin/install_plugins" >/dev/null 2>&1 || true
        tmux kill-session -t __tpm_bootstrap 2>/dev/null || true
        ok "插件安裝完成（若不完整，可在 tmux 內按 prefix + I 補裝）"
    else
        warn "無法自動安裝插件，請進入 tmux 後按 prefix(Ctrl-b) + I 手動安裝"
    fi

    # 若目前在 tmux 內，順手 reload
    if [[ -n "${TMUX:-}" ]]; then
        tmux source-file "$HOME/.tmux.conf" 2>/dev/null && ok "已 reload 當前 tmux 設定"
    fi
    info "tmux 常用鍵：prefix=Ctrl-b；分割 |、-；Alt+Shift+數字 切 window；prefix + r 重載"
}

# =====================================================
# jumpfwd (jf)
# =====================================================
setup_jumpfwd() {
    header "設定 jumpfwd (jf)"
    [[ -f "$JF_SRC" ]] || die "找不到 jf 來源：$JF_SRC"

    # 必需依賴
    have jq    || pkg_install jq
    have socat || pkg_install socat
    have jq    || die "jq 安裝失敗，jf 無法運作"
    have socat || die "socat 安裝失敗，jf 無法運作"
    ok "必需依賴就緒：jq、socat"

    # 部署 jf 到 ~/.local/bin
    ensure_local_bin_path
    if [[ -f "$HOME/.local/bin/jf" ]] && ! cmp -s "$JF_SRC" "$HOME/.local/bin/jf"; then
        backup_file "$HOME/.local/bin/jf"
    fi
    cp "$JF_SRC" "$HOME/.local/bin/jf"
    chmod +x "$HOME/.local/bin/jf"
    ok "已部署 ~/.local/bin/jf"

    # 建立設定檔（若不存在才從範例複製，避免覆蓋既有規則）
    local conf_dir="$HOME/.config/jumpfwd"
    mkdir -p "$conf_dir"
    if [[ -f "$conf_dir/config.json" ]]; then
        info "已存在 $conf_dir/config.json（保留不覆蓋，共 $(jq '.forwards|length' "$conf_dir/config.json" 2>/dev/null || echo '?') 條規則）"
    else
        cp "$JF_CONF_EXAMPLE" "$conf_dir/config.json"
        ok "已從範例建立 $conf_dir/config.json（請自行編輯成你的設備與規則）"
    fi

    # 選用依賴提示（不同發行版套件名差異大，交由使用者決定）
    local missing_opt=()
    have tailscale  || missing_opt+=("tailscale（connect 顯示 tailnet IP、自啟排序）")
    have websockify || missing_opt+=("websockify+novnc（瀏覽器 VNC：jf novnc）")
    have fping      || missing_opt+=("fping+nc（區網掃描：jf scan）")
    if [[ ${#missing_opt[@]} -gt 0 ]]; then
        warn "以下為 jf 的選用功能依賴，未安裝（不影響基本轉發）："
        printf '   • %s\n' "${missing_opt[@]}"
        info "安裝方式見 docs/DEVTOOLS_SETUP.md 的「選用依賴」表"
    fi

    # systemd user service（開機自啟）
    if have systemctl; then
        read -rp "$(echo -e "${BOLD}要安裝 systemd 開機自啟服務（jumpfwd.service）嗎？[Y/n]: ${NC}")" yn
        if [[ "${yn:-y}" =~ ^[Yy]$ ]]; then
            "$HOME/.local/bin/jf" install
            # 讓使用者未登入時服務仍持續（socat 轉發需長駐）
            if ! loginctl show-user "$USER" -p Linger --value 2>/dev/null | grep -q yes; then
                local SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
                $SUDO loginctl enable-linger "$USER" 2>/dev/null \
                    && ok "已啟用 linger（未登入時 jumpfwd 仍運行）" \
                    || warn "啟用 linger 失敗，可稍後手動：sudo loginctl enable-linger $USER"
            fi
            systemctl --user start jumpfwd.service 2>/dev/null || true
            ok "jumpfwd.service 已安裝並啟動"
        else
            info "略過 systemd；之後可手動執行：jf install"
        fi
    fi
    info "jf 常用：jf status｜jf list｜jf start [目標]｜jf menu（完整手冊見 script/devtools/jumpfwd/README.md）"
}

# =====================================================
# 狀態檢視（不需 sudo）
# =====================================================
show_status() {
    header "tmux 狀態"
    if have tmux; then
        ok "tmux：$(tmux -V)"
        [[ -f "$HOME/.tmux.conf" ]] && ok "~/.tmux.conf 存在" || warn "~/.tmux.conf 不存在"
        if [[ -d "$HOME/.tmux/plugins" ]]; then
            echo "  已安裝插件："
            ls -1 "$HOME/.tmux/plugins" 2>/dev/null | sed 's/^/    - /'
        else
            warn "尚未安裝 tpm / 插件"
        fi
    else
        warn "未安裝 tmux"
    fi

    header "jumpfwd (jf) 狀態"
    if have jf || [[ -x "$HOME/.local/bin/jf" ]]; then
        ok "jf：$HOME/.local/bin/jf"
    else
        warn "未安裝 jf"
    fi
    have jq    && ok "jq 已安裝"    || warn "jq 未安裝（jf 必需）"
    have socat && ok "socat 已安裝" || warn "socat 未安裝（jf 必需）"
    local conf="$HOME/.config/jumpfwd/config.json"
    if [[ -f "$conf" ]] && have jq; then
        ok "設定檔：$conf"
        echo "  設備數：$(jq '.devices|length' "$conf")　規則數：$(jq '.forwards|length' "$conf")"
        echo "  群組：$(jq -r '[.forwards[].group]|unique|join(", ")' "$conf")"
    else
        warn "無設定檔或缺 jq：$conf"
    fi
    if have systemctl; then
        local en ac; en="$(systemctl --user is-enabled jumpfwd.service 2>/dev/null || echo '-')"
        ac="$(systemctl --user is-active jumpfwd.service 2>/dev/null || echo '-')"
        echo "  systemd user service：enabled=$en active=$ac"
    fi
    echo "  目前運行中的 socat 轉發：$(pgrep -x socat 2>/dev/null | wc -l)"
}

# =====================================================
# 互動選單
# =====================================================
menu() {
    while true; do
        header "setup-devtools — tmux + jumpfwd 設定"
        echo "  1) 全部安裝（tmux + jumpfwd）"
        echo "  2) 只裝 tmux"
        echo "  3) 只裝 jumpfwd (jf)"
        echo "  4) 顯示目前狀態"
        echo "  q) 離開"
        echo ""
        read -rp "  請選擇 > " c
        case "$c" in
            1) setup_tmux; setup_jumpfwd ;;
            2) setup_tmux ;;
            3) setup_jumpfwd ;;
            4) show_status ;;
            q|Q) echo "Bye!"; exit 0 ;;
            *) warn "無效選項" ;;
        esac
        echo ""; read -rp "按 Enter 繼續…" _
    done
}

usage() {
    cat <<EOF
setup-devtools.sh — tmux + jumpfwd(jf) 一鍵設定（跨發行版、冪等）

用法：
  bash script/setup-devtools.sh [旗標]

旗標：
  -a, --all         安裝 tmux 與 jumpfwd（等同互動選單 1）
  -t, --tmux        只設定 tmux（部署 ~/.tmux.conf + tpm + 插件）
  -j, --jumpfwd     只設定 jumpfwd（安裝 jf + 依賴 + systemd 服務）
  -s, --status      顯示目前狀態（不需 sudo）
  -h, --help        顯示本說明

不帶參數 → 進入互動選單。
完整說明見 docs/DEVTOOLS_SETUP.md
EOF
}

# =====================================================
# 主入口
# =====================================================
detect_pm
case "${1:-}" in
    -a|--all)      setup_tmux; setup_jumpfwd ;;
    -t|--tmux)     setup_tmux ;;
    -j|--jumpfwd)  setup_jumpfwd ;;
    -s|--status)   show_status ;;
    -h|--help)     usage ;;
    "")            menu ;;
    *)             err "未知旗標：$1"; usage; exit 1 ;;
esac
