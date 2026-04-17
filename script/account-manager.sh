#!/usr/bin/env bash
# =============================================================================
# Linux Account Management Tool
# Compatible with: Ubuntu, Debian, CentOS/RHEL, Arch Linux
# Requires: root or sudo privileges
# =============================================================================

# --- Color Definitions -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Utility Functions -------------------------------------------------------

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}${BOLD}   $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_info()    { echo -e "${WHITE}[INFO]${NC} $1"; }

pause() {
    echo ""
    read -rp "Press Enter to continue..."
}

confirm_yes_no() {
    # Usage: confirm_yes_no "Question" => returns 0 (yes) or 1 (no)
    local prompt="$1"
    while true; do
        read -rp "$(echo -e "${YELLOW}${prompt} (Y/N): ${NC}")" yn
        case "$yn" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo -e "${RED}Please enter Y or N${NC}" ;;
        esac
    done
}

confirm_typed() {
    # Usage: confirm_typed "Type YES to confirm" => returns 0 if user typed YES
    local prompt="$1"
    read -rp "$(echo -e "${RED}${prompt}: ${NC}")" response
    [[ "$response" == "YES" ]]
}

read_password() {
    # Usage: read_password "Prompt" => sets $PASSWORD_RESULT
    local prompt="$1"
    while true; do
        read -rsp "$(echo -e "${YELLOW}${prompt}: ${NC}")" pass1
        echo ""
        read -rsp "$(echo -e "${YELLOW}Confirm password: ${NC}")" pass2
        echo ""
        if [[ "$pass1" != "$pass2" ]]; then
            print_error "Passwords do not match, please try again."
        elif [[ ${#pass1} -lt 8 ]]; then
            print_warn "Password must be at least 8 characters."
        else
            PASSWORD_RESULT="$pass1"
            return 0
        fi
    done
}

# Detect which sudo group this distro uses
detect_sudo_group() {
    if getent group sudo &>/dev/null; then
        echo "sudo"
    elif getent group wheel &>/dev/null; then
        echo "wheel"
    else
        echo ""
    fi
}

# Filter out system accounts (UID < 1000, except nobody)
get_regular_users() {
    getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $0}'
}

# Get groups a user belongs to
get_user_groups() {
    local username="$1"
    id -nG "$username" 2>/dev/null | tr ' ' ','
}

# Check if user exists
user_exists() {
    id "$1" &>/dev/null
}

# Check if user is in a specific group
user_in_group() {
    local user="$1" group="$2"
    id -nG "$user" 2>/dev/null | grep -qw "$group"
}

# Get account expiry info from chage
get_account_info() {
    local username="$1"
    if command -v chage &>/dev/null; then
        chage -l "$username" 2>/dev/null
    else
        echo "  (chage not available)"
    fi
}

# Format passwd entry into readable table row
format_user_row() {
    local line="$1"
    local name uid gid gecos home shell
    IFS=: read -r name _ uid gid gecos home shell <<< "$line"
    local locked=""
    # Check if account is locked (! or * in shadow)
    if [[ -r /etc/shadow ]]; then
        local shadow_pw
        shadow_pw=$(getent shadow "$name" 2>/dev/null | cut -d: -f2)
        if [[ "$shadow_pw" == !* ]] || [[ "$shadow_pw" == \** ]]; then
            locked="${RED}LOCKED${NC}"
        else
            locked="${GREEN}active${NC}"
        fi
    else
        locked="${GRAY}unknown${NC}"
    fi
    printf "  %-20s %-6s %-6s %-8b %-30s %s\n" "$name" "$uid" "$gid" "$locked" "$gecos" "$home"
}

# --- Protected accounts (never delete without strong warning) ----------------
PROTECTED_ACCOUNTS=("root" "daemon" "bin" "sys" "sync" "games" "man" "lp"
                    "mail" "news" "uucp" "proxy" "www-data" "backup" "list"
                    "irc" "gnats" "nobody")

# --- Desktop / hardware groups (subset that actually exists on this system) --
# These are required for normal desktop/GUI/device access.
# Absence of these groups causes: no audio, no GPU, no USB, no Bluetooth, etc.
DESKTOP_GROUPS_DEFS=(
    "video:GPU 存取、螢幕錄製（缺少會導致桌面加速失效）"
    "audio:音效裝置（缺少無法播放音效）"
    "render:GPU 算圖（Vulkan / OpenCL 加速）"
    "input:鍵盤滑鼠觸控（X11/Wayland 輸入設備）"
    "plugdev:USB 隨插即用裝置"
    "netdev:使用者管理網路介面（NetworkManager）"
    "bluetooth:藍牙裝置"
    "dialout:序列埠 / GPIO / Arduino"
    "cdrom:光碟機存取"
    "scanner:掃描器"
    "lpadmin:印表機管理"
    "kvm:KVM 虛擬機存取"
    "docker:Docker（免 sudo 執行容器）"
)

# Build list of groups that actually exist on this system
get_available_desktop_groups() {
    local result=()
    for entry in "${DESKTOP_GROUPS_DEFS[@]}"; do
        local grp="${entry%%:*}"
        getent group "$grp" &>/dev/null && result+=("$grp")
    done
    echo "${result[@]}"
}

# Get description for a group
get_group_desc() {
    local target="$1"
    for entry in "${DESKTOP_GROUPS_DEFS[@]}"; do
        [[ "${entry%%:*}" == "$target" ]] && echo "${entry#*:}" && return
    done
    echo ""
}

# Interactive checklist to select and apply desktop groups to a user
# Usage: select_and_apply_groups <username> [auto]
#   auto = skip prompt, apply all recommended groups silently
select_and_apply_groups() {
    local username="$1"
    local mode="${2:-interactive}"

    # Build whiptail checklist items
    local items=()
    local available_groups
    read -ra available_groups <<< "$(get_available_desktop_groups)"

    for grp in "${available_groups[@]}"; do
        local desc
        desc=$(get_group_desc "$grp")
        # Pre-check if user already in group OR it's a core group
        local state="OFF"
        if user_in_group "$username" "$grp"; then
            state="ON"
        elif [[ "$grp" =~ ^(video|audio|render|input|plugdev|netdev|bluetooth)$ ]]; then
            state="ON"
        fi
        items+=("$grp" "$desc" "$state")
    done

    if [[ "$mode" == "auto" ]]; then
        # Apply all pre-checked groups without prompting
        for ((i=0; i<${#items[@]}; i+=3)); do
            local grp="${items[$i]}"
            local chk="${items[$((i+2))]}"
            [[ "$chk" == "ON" ]] && usermod -aG "$grp" "$username" 2>/dev/null
        done
        return 0
    fi

    # Interactive checklist
    if ! command -v whiptail &>/dev/null; then
        print_warn "whiptail not found, skipping group selection."
        return 1
    fi

    local selected
    selected=$(whiptail --title "群組權限設定 — ${username}" \
        --checklist "選擇要加入的群組（空白鍵切換、Enter 確認）：\n缺少 video/audio/input 會導致桌面功能異常！" \
        25 72 12 \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1

    # Remove quotes from whiptail output
    selected=$(echo "$selected" | tr -d '"')

    if [[ -z "$selected" ]]; then
        print_warn "未選擇任何群組。"
        return 0
    fi

    local added=() skipped=()
    for grp in $selected; do
        if usermod -aG "$grp" "$username" 2>/dev/null; then
            added+=("$grp")
        else
            skipped+=("$grp")
        fi
    done

    [[ ${#added[@]}   -gt 0 ]] && print_success "已加入群組：${added[*]}"
    [[ ${#skipped[@]} -gt 0 ]] && print_warn    "加入失敗：${skipped[*]}"
    return 0
}

# Show diff between current groups and recommended desktop groups
show_group_diff() {
    local username="$1"
    local available_groups
    read -ra available_groups <<< "$(get_available_desktop_groups)"

    echo -e "${CYAN}--- 群組健康檢查：${username} ---${NC}"
    printf "  %-16s %-8s %s\n" "群組" "狀態" "說明"
    echo "  ------------------------------------------------------------------"

    local missing=0
    for grp in "${available_groups[@]}"; do
        local desc
        desc=$(get_group_desc "$grp")
        if user_in_group "$username" "$grp"; then
            printf "  ${GREEN}%-16s [有]${NC}    %s\n" "$grp" "$desc"
        else
            # Only flag as warning for important groups
            if [[ "$grp" =~ ^(video|audio|render|input|plugdev|netdev|bluetooth|dialout)$ ]]; then
                printf "  ${RED}%-16s [缺]${NC}    %s\n" "$grp" "$desc"
                ((missing++))
            else
                printf "  ${GRAY}%-16s [無]${NC}    %s\n" "$grp" "$desc"
            fi
        fi
    done

    echo ""
    if [[ $missing -gt 0 ]]; then
        print_warn "偵測到 ${missing} 個重要群組缺失（標記為 [缺]），可能影響桌面功能。"
    else
        print_success "所有重要群組均已設定。"
    fi
}

is_protected() {
    local name="$1"
    for p in "${PROTECTED_ACCOUNTS[@]}"; do
        [[ "$name" == "$p" ]] && return 0
    done
    return 1
}

# =============================================================================
# Feature 1: Create New Account
# =============================================================================
create_account() {
    print_header "Create New Account"
    local SUDO_GROUP
    SUDO_GROUP=$(detect_sudo_group)

    # --- Username ------------------------------------------------------------
    read -rp "$(echo -e "${YELLOW}Enter new username: ${NC}")" username
    if [[ -z "$username" ]]; then
        print_error "Username cannot be empty."
        pause; return
    fi
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        print_error "Invalid username. Use lowercase letters, numbers, _ or - only."
        pause; return
    fi
    if user_exists "$username"; then
        print_error "Account '$username' already exists!"
        pause; return
    fi

    # --- Full Name / Comment -------------------------------------------------
    read -rp "$(echo -e "${YELLOW}Enter full name (optional): ${NC}")" fullname
    fullname="${fullname:-$username}"

    # --- Password ------------------------------------------------------------
    read_password "Enter password"
    local password="$PASSWORD_RESULT"

    # --- Home directory ------------------------------------------------------
    local homedir="/home/$username"

    # --- Create user ---------------------------------------------------------
    if useradd -m -c "$fullname" -s /bin/bash "$username" 2>/dev/null; then
        print_success "Account '$username' created (home: $homedir)"
    else
        print_error "Failed to create account '$username'."
        pause; return
    fi

    # --- Set password --------------------------------------------------------
    if echo "$username:$password" | chpasswd 2>/dev/null; then
        print_success "Password set successfully."
    else
        print_error "Failed to set password."
        userdel -r "$username" 2>/dev/null
        pause; return
    fi

    # --- Password never expires ----------------------------------------------
    if confirm_yes_no "Set password to never expire?"; then
        if command -v chage &>/dev/null; then
            chage -M -1 "$username"
            print_success "Password set to never expire."
        else
            print_warn "chage not found, skipping."
        fi
    fi

    # --- sudo (administrator) ------------------------------------------------
    if [[ -n "$SUDO_GROUP" ]]; then
        if confirm_yes_no "Grant administrator privileges (add to '$SUDO_GROUP' group)?"; then
            usermod -aG "$SUDO_GROUP" "$username"
            print_success "Added to '$SUDO_GROUP' group."
            print_warn "This account now has full administrative (sudo) access!"
        fi
    fi

    # --- SSH access ----------------------------------------------------------
    if confirm_yes_no "Allow SSH login for this account?"; then
        local ssh_dir="$homedir/.ssh"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$username:$username" "$ssh_dir"
        print_success "SSH directory created at $ssh_dir"
        print_info  "To add a public key: nano $ssh_dir/authorized_keys"
    fi

    # --- Desktop / hardware groups -------------------------------------------
    echo ""
    print_header "桌面與硬體群組設定"
    print_info "缺少 video / audio / input 等群組會導致：無法播音、GPU 加速失效、輸入裝置異常。"
    echo ""
    if confirm_yes_no "設定桌面/硬體群組權限（強烈建議）？"; then
        select_and_apply_groups "$username" "interactive"
    else
        print_warn "跳過群組設定。若之後桌面功能異常，請至「修改帳號設定 → 修復桌面群組」補設。"
    fi

    # --- Summary -------------------------------------------------------------
    echo ""
    echo -e "${CYAN}--- Account Summary ---${NC}"
    printf "  %-20s %s\n" "Username:"    "$username"
    printf "  %-20s %s\n" "Full Name:"   "$fullname"
    printf "  %-20s %s\n" "Home:"        "$homedir"
    printf "  %-20s %s\n" "Shell:"       "/bin/bash"
    printf "  %-20s %s\n" "Groups:"      "$(get_user_groups "$username")"
    echo ""
    print_success "Account '$username' setup complete."
    pause
}

# =============================================================================
# Feature 2: Change Account Password
# =============================================================================
change_password() {
    print_header "Change Account Password"
    local SUDO_GROUP
    SUDO_GROUP=$(detect_sudo_group)

    # List regular users
    echo -e "${YELLOW}Current local accounts:${NC}"
    printf "  ${BOLD}%-20s %-6s %-30s${NC}\n" "Username" "UID" "Groups"
    echo "  ----------------------------------------------------------"
    while IFS= read -r line; do
        local name uid
        IFS=: read -r name _ uid _ <<< "$line"
        printf "  %-20s %-6s %s\n" "$name" "$uid" "$(get_user_groups "$name")"
    done < <(get_regular_users)
    echo ""

    read -rp "$(echo -e "${YELLOW}Enter username to modify: ${NC}")" username
    if ! user_exists "$username"; then
        print_error "Account '$username' does not exist!"
        pause; return
    fi

    # --- New password --------------------------------------------------------
    read_password "Enter new password"
    local password="$PASSWORD_RESULT"

    if echo "$username:$password" | chpasswd 2>/dev/null; then
        print_success "Password updated for '$username'."
    else
        print_error "Failed to update password."
        pause; return
    fi

    # --- Password expiry -----------------------------------------------------
    if confirm_yes_no "Set password to never expire?"; then
        command -v chage &>/dev/null && chage -M -1 "$username"
        print_success "Password set to never expire."
    fi

    # --- sudo group ----------------------------------------------------------
    if [[ -n "$SUDO_GROUP" ]]; then
        if user_in_group "$username" "$SUDO_GROUP"; then
            print_info "Account is already in '$SUDO_GROUP' group."
        else
            if confirm_yes_no "Grant administrator privileges (add to '$SUDO_GROUP' group)?"; then
                usermod -aG "$SUDO_GROUP" "$username"
                print_success "Added to '$SUDO_GROUP' group."
                print_warn "This account now has full administrative (sudo) access!"
            fi
        fi
    fi

    # --- Group health check & repair -----------------------------------------
    echo ""
    print_header "桌面群組健康檢查"
    show_group_diff "$username"
    echo ""
    if confirm_yes_no "重新設定桌面/硬體群組權限？"; then
        select_and_apply_groups "$username" "interactive"
    fi

    echo ""
    print_success "Done. Account info:"
    printf "  %-20s %s\n" "Username:" "$username"
    printf "  %-20s %s\n" "Groups:"   "$(get_user_groups "$username")"
    pause
}

# =============================================================================
# Feature 3: View All Accounts
# =============================================================================
view_accounts() {
    print_header "All Local Accounts"

    # --- Table header --------------------------------------------------------
    printf "  ${BOLD}${CYAN}%-20s %-6s %-10s %-30s %s${NC}\n" \
        "Username" "UID" "Status" "Full Name" "Home"
    echo "  --------------------------------------------------------------------------"

    while IFS= read -r line; do
        local name uid gecos home
        IFS=: read -r name _ uid _ gecos home _ <<< "$line"
        local status
        if [[ -r /etc/shadow ]]; then
            local spw
            spw=$(getent shadow "$name" 2>/dev/null | cut -d: -f2)
            if [[ "$spw" == !* ]] || [[ "$spw" == \** ]]; then
                status=$(echo -e "${RED}locked${NC}")
            else
                status=$(echo -e "${GREEN}active${NC}")
            fi
        else
            status="${GRAY}unknown${NC}"
        fi
        printf "  %-20s %-6s %-19b %-30s %s\n" "$name" "$uid" "$status" "$gecos" "$home"
    done < <(get_regular_users)

    # --- Statistics ----------------------------------------------------------
    echo ""
    print_header "Account Statistics"
    local total active locked never_login
    total=$(get_regular_users | wc -l)
    active=0; locked=0; never_login=0

    while IFS= read -r line; do
        local name
        name=$(echo "$line" | cut -d: -f1)
        if [[ -r /etc/shadow ]]; then
            local spw
            spw=$(getent shadow "$name" 2>/dev/null | cut -d: -f2)
            if [[ "$spw" == !* ]] || [[ "$spw" == \** ]]; then
                ((locked++))
            else
                ((active++))
            fi
        fi
        local last_login
        last_login=$(lastlog -u "$name" 2>/dev/null | tail -1 | awk '{print $4}')
        [[ "$last_login" == "**Never" ]] || [[ -z "$last_login" ]] && ((never_login++))
    done < <(get_regular_users)

    printf "  %-30s %s\n" "Total accounts:"          "${WHITE}$total${NC}"
    printf "  %-30s %s\n" "Active accounts:"         "${GREEN}$active${NC}"
    printf "  %-30s %s\n" "Locked accounts:"         "${RED}$locked${NC}"
    printf "  %-30s %s\n" "Never logged in:"         "${GRAY}$never_login${NC}"

    # --- sudo group members --------------------------------------------------
    local SUDO_GROUP
    SUDO_GROUP=$(detect_sudo_group)
    if [[ -n "$SUDO_GROUP" ]]; then
        echo ""
        print_header "Administrator Group: $SUDO_GROUP"
        local members
        members=$(getent group "$SUDO_GROUP" | cut -d: -f4 | tr ',' '\n')
        if [[ -z "$members" ]]; then
            echo -e "  ${GRAY}(no members)${NC}"
        else
            while IFS= read -r m; do
                [[ -n "$m" ]] && echo -e "  ${MAGENTA}$m${NC}"
            done <<< "$members"
        fi
    fi

    # --- Detail view ---------------------------------------------------------
    echo ""
    if confirm_yes_no "View details of a specific account?"; then
        read -rp "$(echo -e "${YELLOW}Enter username: ${NC}")" target
        if ! user_exists "$target"; then
            print_error "Account '$target' not found."
            pause; return
        fi
        print_header "Account '$target' Details"
        local entry
        entry=$(getent passwd "$target")
        IFS=: read -r name _ uid gid gecos home shell <<< "$entry"
        printf "  %-25s %s\n" "Username:"    "$name"
        printf "  %-25s %s\n" "UID:"         "$uid"
        printf "  %-25s %s\n" "GID:"         "$gid"
        printf "  %-25s %s\n" "Full Name:"   "$gecos"
        printf "  %-25s %s\n" "Home:"        "$home"
        printf "  %-25s %s\n" "Shell:"       "$shell"
        printf "  %-25s %s\n" "Groups:"      "$(get_user_groups "$target")"
        echo ""
        echo -e "${CYAN}Password / Expiry Info:${NC}"
        get_account_info "$target" | sed 's/^/  /'
        echo ""
        echo -e "${CYAN}Last Login:${NC}"
        lastlog -u "$target" 2>/dev/null | tail -1 | sed 's/^/  /' || echo "  (lastlog not available)"
    fi
    pause
}

# =============================================================================
# Feature 4: Modify Account Settings
# =============================================================================
modify_account() {
    print_header "Modify Account Settings"
    local SUDO_GROUP
    SUDO_GROUP=$(detect_sudo_group)

    # List users
    echo -e "${YELLOW}Current local accounts:${NC}"
    while IFS= read -r line; do
        local name uid
        IFS=: read -r name _ uid _ <<< "$line"
        printf "  %-20s UID=%-6s Groups: %s\n" "$name" "$uid" "$(get_user_groups "$name")"
    done < <(get_regular_users)
    echo ""

    read -rp "$(echo -e "${YELLOW}Enter username to modify: ${NC}")" username
    if ! user_exists "$username"; then
        print_error "Account '$username' does not exist!"
        pause; return
    fi

    echo ""
    echo -e "${YELLOW}Select modification:${NC}"
    echo "  1. Lock account"
    echo "  2. Unlock account"
    echo "  3. Add to group"
    echo "  4. Remove from group"
    echo "  5. Change shell"
    echo "  6. Set account expiry date"
    echo "  7. Expire password (force change on next login)"
    echo -e "  ${CYAN}8. 桌面群組健康檢查與修復${NC}  ← 修復 video/audio/input 等群組缺失"
    echo -e "  ${CYAN}9. 修復家目錄權限${NC}           ← 解決 SCP/SSH 寫入 Permission denied"
    echo "  10. Back"
    echo ""
    read -rp "$(echo -e "${YELLOW}Option (1-10): ${NC}")" sub

    case "$sub" in
        1)
            usermod -L "$username" && print_success "Account '$username' locked." || print_error "Failed."
            ;;
        2)
            usermod -U "$username" && print_success "Account '$username' unlocked." || print_error "Failed."
            ;;
        3)
            read -rp "$(echo -e "${YELLOW}Enter group name to add: ${NC}")" grp
            if getent group "$grp" &>/dev/null; then
                usermod -aG "$grp" "$username" && \
                    print_success "Added '$username' to group '$grp'." || print_error "Failed."
            else
                print_error "Group '$grp' does not exist."
            fi
            ;;
        4)
            echo -e "  Current groups: ${CYAN}$(get_user_groups "$username")${NC}"
            read -rp "$(echo -e "${YELLOW}Enter group name to remove: ${NC}")" grp
            if [[ "$grp" == "$(id -gn "$username")" ]]; then
                print_error "Cannot remove primary group."
            else
                gpasswd -d "$username" "$grp" 2>/dev/null && \
                    print_success "Removed '$username' from group '$grp'." || print_error "Failed."
            fi
            ;;
        5)
            echo -e "  Current shell: ${CYAN}$(getent passwd "$username" | cut -d: -f7)${NC}"
            echo "  Available shells:"
            grep -v '^#' /etc/shells | sed 's/^/    /'
            read -rp "$(echo -e "${YELLOW}Enter new shell path: ${NC}")" newshell
            if grep -qx "$newshell" /etc/shells 2>/dev/null; then
                usermod -s "$newshell" "$username" && \
                    print_success "Shell changed to '$newshell'." || print_error "Failed."
            else
                print_error "Shell '$newshell' is not in /etc/shells."
            fi
            ;;
        6)
            read -rp "$(echo -e "${YELLOW}Enter expiry date (YYYY-MM-DD) or press Enter to remove: ${NC}")" expdate
            if [[ -z "$expdate" ]]; then
                usermod -e "" "$username" && print_success "Account expiry removed." || print_error "Failed."
            else
                usermod -e "$expdate" "$username" && \
                    print_success "Account expiry set to '$expdate'." || print_error "Failed."
            fi
            ;;
        7)
            command -v chage &>/dev/null || { print_error "chage not found."; pause; return; }
            chage -d 0 "$username" && \
                print_success "Password expired. '$username' must change password on next login." || \
                print_error "Failed."
            ;;
        8)
            echo ""
            show_group_diff "$username"
            echo ""
            if confirm_yes_no "開啟群組選擇介面進行修復？"; then
                select_and_apply_groups "$username" "interactive"
                echo ""
                print_success "修復完成，目前群組："
                printf "  %s\n" "$(get_user_groups "$username")"
                print_warn "需要重新登入後群組設定才會完全生效。"
            fi
            ;;
        9)
            echo ""
            local homedir
            homedir=$(getent passwd "$username" | cut -d: -f6)
            print_info "家目錄：${homedir}"
            echo ""

            # 顯示目前狀態
            echo -e "${CYAN}目前家目錄狀態：${NC}"
            ls -la "$homedir" 2>/dev/null | head -5 || print_error "無法讀取家目錄"
            echo ""
            local owner
            owner=$(stat -c '%U:%G' "$homedir" 2>/dev/null)
            local perms
            perms=$(stat -c '%a' "$homedir" 2>/dev/null)
            printf "  %-20s %s\n" "擁有者：" "$owner"
            printf "  %-20s %s\n" "權限：" "$perms"

            if [[ "$owner" != "${username}:${username}" ]]; then
                print_warn "擁有者不正確（應為 ${username}:${username}，實際為 ${owner}）"
            fi
            if [[ "$perms" != "755" && "$perms" != "750" && "$perms" != "700" ]]; then
                print_warn "權限可能不正確（目前 ${perms}，建議 755 或 700）"
            fi

            echo ""
            echo -e "${YELLOW}選擇修復操作：${NC}"
            echo "  1. 修復擁有者（chown -R username:username）"
            echo "  2. 修復目錄權限為 755"
            echo "  3. 修復目錄權限為 700（更安全）"
            echo "  4. 全部修復（擁有者 + 權限 755）"
            echo "  5. 取消"
            read -rp "$(echo -e "${YELLOW}選擇 (1-5): ${NC}")" fix_opt

            case "$fix_opt" in
                1)
                    chown -R "$username:$username" "$homedir" && \
                        print_success "擁有者已修正為 ${username}:${username}" || \
                        print_error "修復失敗"
                    ;;
                2)
                    chmod 755 "$homedir" && \
                        print_success "家目錄權限已設為 755" || \
                        print_error "修復失敗"
                    ;;
                3)
                    chmod 700 "$homedir" && \
                        print_success "家目錄權限已設為 700" || \
                        print_error "修復失敗"
                    ;;
                4)
                    chown -R "$username:$username" "$homedir" && chmod 755 "$homedir" && \
                        print_success "家目錄擁有者與權限均已修正" || \
                        print_error "修復失敗"
                    ;;
                *) print_info "取消。" ;;
            esac
            ;;
        10) return ;;
        *) print_error "Invalid option." ;;
    esac
    pause
}

# =============================================================================
# Feature 5: Delete Account
# =============================================================================
delete_account() {
    print_header "Delete Account"
    print_warn "Deleting an account is irreversible!"
    echo ""

    echo -e "${YELLOW}Current local accounts:${NC}"
    while IFS= read -r line; do
        local name uid gecos
        IFS=: read -r name _ uid _ gecos _ <<< "$line"
        printf "  %-20s UID=%-6s %s\n" "$name" "$uid" "$gecos"
    done < <(get_regular_users)
    echo ""

    read -rp "$(echo -e "${YELLOW}Enter username to delete: ${NC}")" username

    # Existence check
    if ! user_exists "$username"; then
        print_error "Account '$username' does not exist!"
        pause; return
    fi

    # Current user check
    if [[ "$username" == "$USER" ]] || [[ "$username" == "$(logname 2>/dev/null)" ]]; then
        print_error "Cannot delete the currently logged-in user '$username'!"
        pause; return
    fi

    # Protected account check
    if is_protected "$username"; then
        print_warn "'$username' is a system-protected account!"
        confirm_typed "Type YES to force delete (NOT recommended)" || {
            print_info "Delete cancelled."
            pause; return
        }
    fi

    # Show account info
    echo ""
    echo -e "${YELLOW}Account to be deleted:${NC}"
    local entry
    entry=$(getent passwd "$username")
    IFS=: read -r name _ uid gid gecos home shell <<< "$entry"
    printf "  %-20s %s\n" "Username:" "$name"
    printf "  %-20s %s\n" "UID:"      "$uid"
    printf "  %-20s %s\n" "Home:"     "$home"
    printf "  %-20s %s\n" "Groups:"   "$(get_user_groups "$username")"

    # Home directory option
    echo ""
    local remove_home=false
    if confirm_yes_no "Also delete home directory ($home) and mail spool?"; then
        remove_home=true
    fi

    # Final confirmation
    echo ""
    print_warn "THIS CANNOT BE UNDONE!"
    confirm_typed "Type YES to confirm deletion of '$username'" || {
        print_info "Delete cancelled."
        pause; return
    }

    # Execute deletion
    if $remove_home; then
        userdel -r "$username" 2>/dev/null && \
            print_success "Account '$username' and home directory deleted." || \
            print_error "Failed to delete account."
    else
        userdel "$username" 2>/dev/null && \
            print_success "Account '$username' deleted (home directory preserved)." || \
            print_error "Failed to delete account."
    fi

    echo ""
    echo -e "${CYAN}Remaining accounts:${NC}"
    while IFS= read -r line; do
        local n u
        IFS=: read -r n _ u _ <<< "$line"
        printf "  %-20s UID=%s\n" "$n" "$u"
    done < <(get_regular_users)
    pause
}

# =============================================================================
# Main Menu
# =============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root or with sudo.${NC}"
        echo -e "${YELLOW}Usage: sudo $0${NC}"
        exit 1
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        echo "  ╔══════════════════════════════════════╗"
        echo "  ║     Linux Account Management Tool    ║"
        echo "  ║    $(uname -n) | $(date '+%Y-%m-%d %H:%M')    ║"
        echo "  ╚══════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "  ${YELLOW}Select an operation:${NC}"
        echo ""
        echo -e "  ${WHITE}1.${NC} Create new account"
        echo -e "  ${WHITE}2.${NC} Change account password"
        echo -e "  ${WHITE}3.${NC} View all accounts"
        echo -e "  ${WHITE}4.${NC} Modify account settings"
        echo -e "  ${WHITE}5.${NC} Delete account"
        echo -e "  ${WHITE}6.${NC} Exit"
        echo ""
        read -rp "$(echo -e "  ${CYAN}Enter option (1-6): ${NC}")" choice

        case "$choice" in
            1) create_account ;;
            2) change_password ;;
            3) view_accounts ;;
            4) modify_account ;;
            5) delete_account ;;
            6)
                echo -e "${YELLOW}Goodbye!${NC}"
                exit 0
                ;;
            *)
                print_error "Invalid option '$choice'."
                pause
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================
check_root
main_menu
