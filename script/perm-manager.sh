#!/bin/bash
# perm-manager.sh — 帳號權限互通管理工具

# ── 顏色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

TITLE="帳號權限管理工具"
SUDO_PASS=""

# ── 工具函式 ─────────────────────────────────────────────────────────────────

# 取得系統一般使用者清單
get_users() {
    getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}'
}

# 顯示訊息框
msg() { whiptail --title "$TITLE" --msgbox "$1" 10 60; }

# 顯示確認框
confirm() { whiptail --title "$TITLE" --yesno "$1" 10 60; }

# 用密碼執行 sudo 指令（不顯示密碼）
sudo_run() {
    echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
}

# 驗證 sudo 密碼
verify_sudo_password() {
    local user="$1"
    local pass="$2"
    echo "$pass" | sudo -S -u root true 2>/dev/null
    return $?
}

# 要求輸入 sudo 密碼（用 whiptail passwordbox）
ask_sudo_password() {
    local current_user
    current_user=$(whoami)
    local pass
    pass=$(whiptail --title "$TITLE" \
        --passwordbox "請輸入 ${current_user} 的 sudo 密碼：" 8 50 \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1

    # 驗證密碼
    if echo "$pass" | sudo -S true 2>/dev/null; then
        SUDO_PASS="$pass"
        return 0
    else
        whiptail --title "$TITLE" --msgbox "❌ 密碼錯誤，請重試。" 8 40
        return 1
    fi
}

# ── 查看目前 ACL 狀態 ────────────────────────────────────────────────────────

view_permissions() {
    local users=()
    while IFS= read -r u; do users+=("$u" ""); done < <(get_users)

    local target
    target=$(whiptail --title "$TITLE" \
        --menu "查看哪個帳號的家目錄權限？" 15 50 6 \
        "${users[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    local homedir="/home/$target"
    local output
    output=$(getfacl -R --skip-base "$homedir" 2>/dev/null | head -80)
    if [[ -z "$output" ]]; then
        output="（無額外 ACL 設定，使用預設 Unix 權限）"
    fi

    # 加上基本 ls 權限資訊
    local ls_info
    ls_info=$(ls -la "$homedir" 2>/dev/null | head -20)

    whiptail --title "[$target] 的目錄權限" \
        --scrolltext \
        --msgbox "=== ls -la ===\n${ls_info}\n\n=== ACL ===\n${output}" \
        30 78
}

# ── 選擇要授權的路徑範圍 ──────────────────────────────────────────────────────

select_scope() {
    local target="$1"  # 目標帳號（被授權的那方）
    local homedir="/home/$target"

    # 動態列出家目錄下的子目錄
    local subdirs=("整個家目錄 ($homedir)" "homedir")
    while IFS= read -r d; do
        local dname
        dname=$(basename "$d")
        subdirs+=("$dname" "$d")
    done < <(find "$homedir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    subdirs+=("自訂路徑" "custom")

    local choice
    choice=$(whiptail --title "$TITLE" \
        --menu "要開放 [$target] 的哪個範圍？" 20 60 10 \
        "${subdirs[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1

    if [[ "$choice" == "homedir" ]]; then
        SELECTED_PATH="$homedir"
    elif [[ "$choice" == "custom" ]]; then
        SELECTED_PATH=$(whiptail --title "$TITLE" \
            --inputbox "請輸入完整路徑：" 8 60 "/home/$target/" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 ]] && return 1
        if [[ ! -e "$SELECTED_PATH" ]]; then
            whiptail --title "$TITLE" --msgbox "❌ 路徑不存在：$SELECTED_PATH" 8 60
            return 1
        fi
    else
        SELECTED_PATH="$choice"
    fi
    return 0
}

# ── 選擇權限等級 ──────────────────────────────────────────────────────────────

select_permission_level() {
    local level
    level=$(whiptail --title "$TITLE" \
        --menu "要授予什麼等級的權限？" 15 60 4 \
        "r"   "唯讀（read-only）：只能查看，不能修改" \
        "rw"  "讀寫（read-write）：可查看、新增、修改" \
        "rwx" "完全開放（full）：讀、寫、執行全開" \
        "---" "撤銷：移除對該路徑的授權" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    SELECTED_PERM="$level"
    return 0
}

# ── 執行授權 ──────────────────────────────────────────────────────────────────

apply_permission() {
    local grantee="$1"   # 被授權的使用者
    local path="$2"      # 要開放的路徑
    local perm="$3"      # r / rw / rwx / ---

    local results=""
    local errors=""

    if [[ "$perm" == "---" ]]; then
        # 撤銷
        sudo_run setfacl -R  -x "u:${grantee}" "$path" 2>&1 && \
            results+="✅ 已撤銷 ${grantee} 對 ${path} 的 ACL\n" || \
            errors+="❌ 撤銷 ACL 失敗\n"
        sudo_run setfacl -Rd -x "u:${grantee}" "$path" 2>&1
    else
        # 確保父目錄有執行權（能進入）
        local parent="$path"
        while [[ "$parent" != "/" && "$parent" != "/home" ]]; do
            parent=$(dirname "$parent")
            sudo_run setfacl -m "u:${grantee}:--x" "$parent" 2>/dev/null
        done

        # 目錄需要 x 才能進入（cd），檔案則不需要
        local dir_perm="$perm"
        [[ "$perm" != *"x"* ]] && dir_perm="${perm}x"

        # 分開設定：目錄用 dir_perm，檔案用 perm（略過 .ssh 以免破壞 SSH 權限）
        echo "$SUDO_PASS" | sudo -S bash -c "
            find $(printf '%q' "$path") -type d -not -path '*/.ssh' -not -path '*/.ssh/*' -exec setfacl -m 'u:${grantee}:${dir_perm}' {} + 2>/dev/null
            find $(printf '%q' "$path") -type d -not -path '*/.ssh' -not -path '*/.ssh/*' -exec setfacl -dm 'u:${grantee}:${dir_perm}' {} + 2>/dev/null
            find $(printf '%q' "$path") -type f -not -path '*/.ssh/*' -exec setfacl -m 'u:${grantee}:${perm}' {} + 2>/dev/null
        " 2>/dev/null && \
            results+="✅ 設定 ACL — 目錄:${dir_perm} 檔案:${perm}\n" || \
            errors+="❌ 設定 ACL 失敗\n"
    fi

    local summary="${results}${errors}"
    [[ -z "$summary" ]] && summary="（無輸出）"
    whiptail --title "執行結果" --msgbox "$summary" 15 65
}

# ── 授權流程（主流程）────────────────────────────────────────────────────────

grant_flow() {
    local users=()
    while IFS= read -r u; do users+=("$u" ""); done < <(get_users)

    # 步驟 1：選擇被授權者（誰要獲得權限）
    local grantee
    grantee=$(whiptail --title "$TITLE" \
        --menu "步驟 1/4：哪個帳號要獲得存取權限？" 15 55 6 \
        "${users[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    # 步驟 2：選擇目標帳號（要開放誰的資料夾）
    local target
    target=$(whiptail --title "$TITLE" \
        --menu "步驟 2/4：要開放哪個帳號的資料夾給 [${grantee}]？" 15 60 6 \
        "${users[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    if [[ "$grantee" == "$target" ]]; then
        whiptail --title "$TITLE" --msgbox "⚠️  來源與目標是同一個帳號，無需設定。" 8 50
        return
    fi

    # 步驟 3：選擇路徑範圍
    SELECTED_PATH=""
    select_scope "$target" || return

    # 步驟 4：選擇權限等級
    SELECTED_PERM=""
    select_permission_level || return

    # 確認摘要
    local action_desc
    case "$SELECTED_PERM" in
        r)   action_desc="唯讀 (r)" ;;
        rw)  action_desc="讀寫 (rw)" ;;
        rwx) action_desc="完全開放 (rwx)" ;;
        ---) action_desc="撤銷授權" ;;
    esac

    confirm "確認執行以下操作？\n\n  授權對象：${grantee}\n  目標路徑：${SELECTED_PATH}\n  權限等級：${action_desc}" \
        || return

    # 確認有 sudo 密碼
    if [[ -z "$SUDO_PASS" ]]; then
        ask_sudo_password || return
    fi

    apply_permission "$grantee" "$SELECTED_PATH" "$SELECTED_PERM"
}

# ── 快速互通（兩帳號完全互通）────────────────────────────────────────────────

quick_mutual_flow() {
    local users=()
    while IFS= read -r u; do users+=("$u" ""); done < <(get_users)

    local user_a
    user_a=$(whiptail --title "$TITLE" \
        --menu "快速互通 — 選擇帳號 A：" 15 50 6 \
        "${users[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    local user_b
    user_b=$(whiptail --title "$TITLE" \
        --menu "快速互通 — 選擇帳號 B（與 ${user_a} 互通）：" 15 55 6 \
        "${users[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    [[ "$user_a" == "$user_b" ]] && { msg "⚠️  兩個帳號相同，無需設定。"; return; }

    local level
    level=$(whiptail --title "$TITLE" \
        --menu "要互相開放什麼等級的權限？" 12 60 3 \
        "rw"  "讀寫（推薦）" \
        "rwx" "完全開放" \
        "r"   "唯讀" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    confirm "確認：\n  ${user_a} ↔ ${user_b}\n  雙方家目錄互相開放 ${level} 權限？" || return

    if [[ -z "$SUDO_PASS" ]]; then
        ask_sudo_password || return
    fi

    local out=""
    # 目錄需要 x 才能進入，檔案不需要
    local dir_level="${level}x"
    [[ "$level" == *x* ]] && dir_level="$level"

    # A → B 的家目錄（略過 .ssh 以免破壞 SSH 權限）
    echo "$SUDO_PASS" | sudo -S bash -c "
        find /home/${user_b} -type d -not -path '*/.ssh' -not -path '*/.ssh/*' -exec setfacl -m 'u:${user_a}:${dir_level}' {} + 2>/dev/null
        find /home/${user_b} -type d -not -path '*/.ssh' -not -path '*/.ssh/*' -exec setfacl -dm 'u:${user_a}:${dir_level}' {} + 2>/dev/null
        find /home/${user_b} -type f -not -path '*/.ssh/*' -exec setfacl -m 'u:${user_a}:${level}' {} + 2>/dev/null
    " 2>/dev/null && \
        out+="✅ ${user_a} 可存取 /home/${user_b}\n" || out+="❌ 設定失敗\n"

    # B → A 的家目錄（略過 .ssh 以免破壞 SSH 權限）
    echo "$SUDO_PASS" | sudo -S bash -c "
        find /home/${user_a} -type d -not -path '*/.ssh' -not -path '*/.ssh/*' -exec setfacl -m 'u:${user_b}:${dir_level}' {} + 2>/dev/null
        find /home/${user_a} -type d -not -path '*/.ssh' -not -path '*/.ssh/*' -exec setfacl -dm 'u:${user_b}:${dir_level}' {} + 2>/dev/null
        find /home/${user_a} -type f -not -path '*/.ssh/*' -exec setfacl -m 'u:${user_b}:${level}' {} + 2>/dev/null
    " 2>/dev/null && \
        out+="✅ ${user_b} 可存取 /home/${user_a}\n" || out+="❌ 設定失敗\n"

    whiptail --title "執行結果" --msgbox "${out}" 12 60
}

# ── 主選單 ────────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE" \
            --menu "請選擇操作：" 18 65 6 \
            "1" "⚡ 快速互通  — 兩帳號完全互通（最常用）" \
            "2" "🔧 精細授權  — 逐步選擇帳號、路徑、權限等級" \
            "3" "👁  查看權限  — 查看帳號目前的 ACL 設定" \
            "4" "🔑 更換密碼  — 重新輸入 sudo 密碼" \
            "5" "❌ 離開" \
            3>&1 1>&2 2>&3)

        [[ $? -ne 0 || "$choice" == "5" ]] && break

        case "$choice" in
            1) quick_mutual_flow ;;
            2) grant_flow ;;
            3) view_permissions ;;
            4) SUDO_PASS=""; ask_sudo_password ;;
        esac
    done
}

# ── 入口 ──────────────────────────────────────────────────────────────────────

clear
echo -e "${BOLD}${CYAN}$TITLE${NC}"
echo -e "${YELLOW}需要 sudo 密碼才能修改權限。${NC}\n"

# 確認 setfacl 存在
if ! command -v setfacl &>/dev/null; then
    echo -e "${RED}找不到 setfacl，請先安裝：sudo apt install acl${NC}"
    exit 1
fi

main_menu
echo -e "\n${GREEN}已離開。${NC}"
