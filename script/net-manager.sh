#!/bin/bash
# net-manager.sh — 互動式網路設定管理工具

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

TITLE="網路設定管理"
SUDO_PASS=""

# ── 工具函式 ─────────────────────────────────────────────────────────────────

msg()     { whiptail --title "$TITLE" --msgbox "$1" 20 72; }
confirm() { whiptail --title "$TITLE" --yesno "$1" 12 60; }

sudo_run() {
    if [[ -n "$SUDO_PASS" ]]; then
        echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
    else
        sudo "$@" 2>/dev/null
    fi
}

ask_sudo_password() {
    local pass
    pass=$(whiptail --title "$TITLE" \
        --passwordbox "請輸入 sudo 密碼：" 8 50 \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    if echo "$pass" | sudo -S true 2>/dev/null; then
        SUDO_PASS="$pass"
        return 0
    else
        whiptail --title "$TITLE" --msgbox "❌ 密碼錯誤" 8 40
        return 1
    fi
}

ensure_sudo() {
    [[ -z "$SUDO_PASS" ]] && { ask_sudo_password || return 1; }
    return 0
}

# ── 1. 網路總覽 ───────────────────────────────────────────────────────────────

view_overview() {
    local out=""

    out+="=== 網路介面 ===\n"
    while IFS=: read -r dev type state; do
        local ip
        ip=$(ip -4 addr show "$dev" 2>/dev/null | awk '/inet /{print $2}')
        local icon
        case "$state" in
            connected*)  icon="[UP]"   ;;
            disconnected) icon="[DOWN]" ;;
            unavailable)  icon="[N/A]"  ;;
            *)            icon="[?]"    ;;
        esac
        out+="${icon} ${dev} [${type}] ${state}"
        [[ -n "$ip" ]] && out+=" — ${ip}"
        out+="\n"
    done < <(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -v 'p2p-dev\|unmanaged')

    out+="\n=== 預設路由 ===\n"
    out+="$(ip route show default 2>/dev/null || echo '（無）')\n"

    out+="\n=== DNS 伺服器 ===\n"
    local dns_out
    dns_out=$(resolvectl status 2>/dev/null | grep 'DNS Servers' | head -5)
    out+="${dns_out:-$(grep nameserver /etc/resolv.conf 2>/dev/null | head -5)}\n"

    out+="\n=== 外部 IP ===\n"
    local ext_ip
    ext_ip=$(curl -s --max-time 4 https://api.ipify.org 2>/dev/null || echo "（無法取得）")
    out+="${ext_ip}\n"

    whiptail --title "網路總覽" --scrolltext --msgbox "$out" 30 78
}

# ── 2. 介面詳細資訊 ───────────────────────────────────────────────────────────

view_interface_detail() {
    local items=()
    while IFS=: read -r dev type state; do
        items+=("$dev" "[${type}] ${state}")
    done < <(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -v 'p2p-dev\|lo:loopback\|unmanaged')

    local dev
    dev=$(whiptail --title "$TITLE" \
        --menu "選擇介面查看詳情：" 18 60 8 \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    local out
    out="$(ip addr show "$dev" 2>/dev/null)\n\n=== NetworkManager 資訊 ===\n$(nmcli dev show "$dev" 2>/dev/null)"
    whiptail --title "${dev} 詳細資訊" --scrolltext --msgbox "$out" 35 78
}

# ── 3. 有線網路設定 ───────────────────────────────────────────────────────────

ethernet_menu() {
    local items=()
    while IFS=: read -r dev type state; do
        [[ "$type" == "ethernet" ]] && items+=("$dev" "$state")
    done < <(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null)
    [[ ${#items[@]} -eq 0 ]] && { msg "沒有偵測到有線網路介面。"; return; }

    local dev
    dev=$(whiptail --title "$TITLE" \
        --menu "選擇有線介面：" 15 50 6 \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    local conn
    conn=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | grep ":${dev}$" | cut -d: -f1)
    [[ -z "$conn" ]] && conn=$(nmcli -t -f NAME,DEVICE con show 2>/dev/null | grep ":${dev}$" | head -1 | cut -d: -f1)

    while true; do
        local choice
        choice=$(whiptail --title "$TITLE — ${dev}" \
            --menu "有線網路設定：" 16 60 6 \
            "1" "查看目前設定" \
            "2" "切換為 DHCP（自動取得 IP）" \
            "3" "設定靜態 IP" \
            "4" "設定 DNS" \
            "5" "啟用 / 停用介面" \
            "6" "返回" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 || "$choice" == "6" ]] && return

        case "$choice" in
            1)
                whiptail --title "${dev} 設定" --scrolltext \
                    --msgbox "$(nmcli dev show "$dev" 2>/dev/null)" 30 72
                ;;
            2)
                [[ -z "$conn" ]] && { msg "❌ 找不到對應連線設定。"; continue; }
                confirm "將 [${conn}] 切換為 DHCP 自動取得 IP？" || continue
                ensure_sudo || continue
                sudo_run nmcli con mod "$conn" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
                sudo_run nmcli con up "$conn"
                msg "✅ 已切換為 DHCP，重新連線中..."
                ;;
            3)
                [[ -z "$conn" ]] && { msg "❌ 找不到對應連線設定。"; continue; }
                local ip gw dns
                ip=$(whiptail --title "$TITLE" --inputbox "IP 位址（含前綴，如 192.168.1.100/24）：" 8 60 "" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                gw=$(whiptail --title "$TITLE" --inputbox "預設閘道（如 192.168.1.1）：" 8 60 "" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                dns=$(whiptail --title "$TITLE" --inputbox "DNS（多個用逗號，如 8.8.8.8,1.1.1.1）：" 8 60 "8.8.8.8,1.1.1.1" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                ensure_sudo || continue
                sudo_run nmcli con mod "$conn" ipv4.method manual ipv4.addresses "$ip" ipv4.gateway "$gw" ipv4.dns "$dns"
                sudo_run nmcli con up "$conn"
                msg "✅ 靜態 IP：${ip}  閘道：${gw}  DNS：${dns}"
                ;;
            4)
                [[ -z "$conn" ]] && { msg "❌ 找不到對應連線設定。"; continue; }
                local dns
                dns=$(whiptail --title "$TITLE" --inputbox "設定 DNS（逗號分隔）：" 8 60 "8.8.8.8,1.1.1.1" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                ensure_sudo || continue
                sudo_run nmcli con mod "$conn" ipv4.dns "$dns"
                sudo_run nmcli con up "$conn"
                msg "✅ DNS 已設定為：${dns}"
                ;;
            5)
                local state
                state=$(nmcli -t -f STATE dev show "$dev" 2>/dev/null | grep "^GENERAL.STATE" | awk -F'[:(]' '{print $2}')
                if [[ "$state" == *"connected"* ]]; then
                    confirm "停用介面 ${dev}？" || continue
                    ensure_sudo || continue
                    sudo_run nmcli dev disconnect "$dev"
                    msg "✅ 已停用 ${dev}"
                else
                    confirm "啟用介面 ${dev}？" || continue
                    ensure_sudo || continue
                    sudo_run nmcli dev connect "$dev"
                    msg "✅ 已啟用 ${dev}"
                fi
                ;;
        esac
    done
}

# ── 4. WiFi 管理 ──────────────────────────────────────────────────────────────

wifi_menu() {
    local wifi_dev
    wifi_dev=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1}' | head -1)
    [[ -z "$wifi_dev" ]] && { msg "沒有偵測到 WiFi 介面。"; return; }

    while true; do
        local cur_ssid
        cur_ssid=$(nmcli -t -f ACTIVE,SSID dev wifi list ifname "$wifi_dev" 2>/dev/null | awk -F: '$1=="yes"{print $2}')
        local subtitle="介面：${wifi_dev}"
        [[ -n "$cur_ssid" ]] && subtitle+=" | 已連線：${cur_ssid}"

        local choice
        choice=$(whiptail --title "$TITLE — WiFi" \
            --menu "$subtitle" 17 65 7 \
            "1" "掃描並連線到 WiFi" \
            "2" "查看已儲存的網路" \
            "3" "切換 WiFi 開關" \
            "4" "斷開目前 WiFi" \
            "5" "刪除已儲存網路" \
            "6" "返回" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 || "$choice" == "6" ]] && return

        case "$choice" in
            1) wifi_scan_connect "$wifi_dev" ;;
            2) wifi_list_saved ;;
            3) wifi_toggle ;;
            4) wifi_disconnect "$wifi_dev" ;;
            5) wifi_delete_saved ;;
        esac
    done
}

wifi_scan_connect() {
    local wifi_dev="$1"
    whiptail --title "$TITLE" --infobox "正在掃描 WiFi..." 6 40
    nmcli dev wifi rescan ifname "$wifi_dev" 2>/dev/null
    sleep 1

    local items=()
    while IFS= read -r line; do
        local ssid signal security active
        ssid=$(echo "$line" | cut -d: -f1)
        signal=$(echo "$line" | cut -d: -f2)
        security=$(echo "$line" | cut -d: -f3)
        active=$(echo "$line" | cut -d: -f4)
        [[ -z "$ssid" || "$ssid" == "--" ]] && continue
        local tag=""
        [[ "$active" == "yes" ]] && tag="[已連線] "
        items+=("$ssid" "${tag}訊號:${signal}% ${security}")
    done < <(nmcli -t -f SSID,SIGNAL,SECURITY,ACTIVE dev wifi list ifname "$wifi_dev" 2>/dev/null \
        | sort -t: -k2 -rn | head -20)

    [[ ${#items[@]} -eq 0 ]] && { msg "沒有偵測到任何 WiFi 網路。"; return; }

    local ssid
    ssid=$(whiptail --title "$TITLE" \
        --menu "選擇 WiFi 網路：" 22 65 12 \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return

    ensure_sudo || return

    if nmcli con show "$ssid" &>/dev/null; then
        confirm "使用已儲存的設定連線到 [${ssid}]？" || return
        local result
        result=$(sudo_run nmcli con up "$ssid" 2>&1)
        [[ $? -eq 0 ]] && msg "✅ 已連線到 ${ssid}" || msg "❌ 連線失敗：\n${result}"
    else
        local pw
        pw=$(whiptail --title "$TITLE" \
            --passwordbox "[${ssid}] 的密碼（開放網路請留空）：" 8 55 \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 ]] && return
        local result
        if [[ -z "$pw" ]]; then
            result=$(sudo_run nmcli dev wifi connect "$ssid" ifname "$wifi_dev" 2>&1)
        else
            result=$(sudo_run nmcli dev wifi connect "$ssid" password "$pw" ifname "$wifi_dev" 2>&1)
        fi
        [[ $? -eq 0 ]] && msg "✅ 已連線到 ${ssid}" || msg "❌ 連線失敗：\n${result}"
    fi
}

wifi_list_saved() {
    local out
    out=$(nmcli -f NAME,TYPE,TIMESTAMP-REAL con show 2>/dev/null | grep -i "wireless")
    whiptail --title "已儲存的 WiFi 網路" --scrolltext \
        --msgbox "${out:-（無儲存的 WiFi 設定）}" 20 72
}

wifi_toggle() {
    local state
    state=$(nmcli radio wifi 2>/dev/null)
    if [[ "$state" == "enabled" ]]; then
        confirm "停用 WiFi？" || return
        ensure_sudo || return
        sudo_run nmcli radio wifi off
        msg "✅ WiFi 已關閉"
    else
        confirm "啟用 WiFi？" || return
        ensure_sudo || return
        sudo_run nmcli radio wifi on
        msg "✅ WiFi 已開啟"
    fi
}

wifi_disconnect() {
    local wifi_dev="$1"
    local cur_ssid
    cur_ssid=$(nmcli -t -f ACTIVE,SSID dev wifi list ifname "$wifi_dev" 2>/dev/null | awk -F: '$1=="yes"{print $2}')
    [[ -z "$cur_ssid" ]] && { msg "目前未連線到任何 WiFi。"; return; }
    confirm "斷開目前 WiFi [${cur_ssid}]？" || return
    ensure_sudo || return
    sudo_run nmcli dev disconnect "$wifi_dev"
    msg "✅ 已斷開 ${cur_ssid}"
}

wifi_delete_saved() {
    local items=()
    while IFS= read -r name; do
        items+=("$name" "")
    done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2~/wireless/{print $1}')
    [[ ${#items[@]} -eq 0 ]] && { msg "沒有已儲存的 WiFi 設定。"; return; }

    local name
    name=$(whiptail --title "$TITLE" \
        --menu "選擇要刪除的 WiFi 設定：" 18 55 8 \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return
    confirm "確認刪除 [${name}] 的儲存設定？" || return
    ensure_sudo || return
    sudo_run nmcli con delete "$name"
    msg "✅ 已刪除 ${name}"
}

# ── 5. VPN 管理 ───────────────────────────────────────────────────────────────

vpn_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE — VPN" \
            --menu "VPN 管理：" 14 55 4 \
            "1" "查看 VPN 連線清單" \
            "2" "連線 VPN" \
            "3" "斷開 VPN" \
            "4" "返回" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 || "$choice" == "4" ]] && return

        case "$choice" in
            1)
                local out
                out=$(nmcli -f NAME,TYPE,STATE con show 2>/dev/null | grep -i vpn)
                whiptail --title "VPN 清單" --scrolltext \
                    --msgbox "${out:-（無已設定的 VPN 連線）}" 18 72
                ;;
            2)
                local items=()
                while IFS= read -r name; do items+=("$name" ""); done \
                    < <(nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2~/vpn/{print $1}')
                [[ ${#items[@]} -eq 0 ]] && { msg "沒有已設定的 VPN 連線。\n請先匯入 VPN 設定檔。"; continue; }
                local name
                name=$(whiptail --title "$TITLE" --menu "選擇 VPN：" 16 55 6 \
                    "${items[@]}" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                ensure_sudo || continue
                local result
                result=$(sudo_run nmcli con up "$name" 2>&1)
                [[ $? -eq 0 ]] && msg "✅ VPN [${name}] 已連線" || msg "❌ 連線失敗：\n${result}"
                ;;
            3)
                local items=()
                while IFS= read -r name; do items+=("$name" ""); done \
                    < <(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null | awk -F: '$2~/vpn/{print $1}')
                [[ ${#items[@]} -eq 0 ]] && { msg "目前沒有作用中的 VPN 連線。"; continue; }
                local name
                name=$(whiptail --title "$TITLE" --menu "選擇要斷開的 VPN：" 16 55 6 \
                    "${items[@]}" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                ensure_sudo || continue
                sudo_run nmcli con down "$name"
                msg "✅ VPN [${name}] 已斷開"
                ;;
        esac
    done
}

# ── 6. DNS 設定 ───────────────────────────────────────────────────────────────

dns_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE — DNS" \
            --menu "DNS 管理：" 14 60 4 \
            "1" "查看目前 DNS 設定" \
            "2" "套用預設 DNS 組合" \
            "3" "自訂 DNS" \
            "4" "返回" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 || "$choice" == "4" ]] && return

        case "$choice" in
            1)
                local out
                out=$(resolvectl status 2>/dev/null | grep -A5 'Link\|DNS\|Domain')
                [[ -z "$out" ]] && out=$(grep nameserver /etc/resolv.conf 2>/dev/null)
                whiptail --title "DNS 設定" --scrolltext --msgbox "$out" 25 72
                ;;
            2)
                local preset
                preset=$(whiptail --title "$TITLE" \
                    --menu "選擇 DNS 預設組合：" 14 65 4 \
                    "google"     "Google DNS：8.8.8.8 / 8.8.4.4" \
                    "cloudflare" "Cloudflare DNS：1.1.1.1 / 1.0.0.1" \
                    "quad9"      "Quad9（隱私）：9.9.9.9 / 149.112.112.112" \
                    "opendns"    "OpenDNS：208.67.222.222 / 208.67.220.220" \
                    3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                local dns_str
                case "$preset" in
                    google)     dns_str="8.8.8.8,8.8.4.4" ;;
                    cloudflare) dns_str="1.1.1.1,1.0.0.1" ;;
                    quad9)      dns_str="9.9.9.9,149.112.112.112" ;;
                    opendns)    dns_str="208.67.222.222,208.67.220.220" ;;
                esac
                dns_apply_to_active "$dns_str"
                ;;
            3)
                local dns_str
                dns_str=$(whiptail --title "$TITLE" \
                    --inputbox "輸入 DNS（多個用逗號分隔）：" 8 60 "8.8.8.8,1.1.1.1" \
                    3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                dns_apply_to_active "$dns_str"
                ;;
        esac
    done
}

dns_apply_to_active() {
    local dns="$1"
    ensure_sudo || return
    local applied=0
    while IFS= read -r conn; do
        sudo_run nmcli con mod "$conn" ipv4.dns "$dns" 2>/dev/null && ((applied++))
        sudo_run nmcli con up "$conn" 2>/dev/null
    done < <(nmcli -t -f NAME con show --active 2>/dev/null | grep -v '^lo')
    [[ $applied -gt 0 ]] \
        && msg "✅ DNS 已套用到 ${applied} 個連線：${dns}" \
        || msg "❌ 套用失敗，請確認有作用中的連線。"
}

# ── 7. 防火牆 (UFW) ───────────────────────────────────────────────────────────

firewall_menu() {
    while true; do
        ensure_sudo 2>/dev/null
        local ufw_status
        ufw_status=$(sudo_run ufw status 2>/dev/null | head -1)

        local choice
        choice=$(whiptail --title "$TITLE — 防火牆 (UFW)" \
            --menu "狀態：${ufw_status:-需要 sudo}" 17 65 7 \
            "1" "查看防火牆規則" \
            "2" "啟用防火牆" \
            "3" "停用防火牆" \
            "4" "允許連接埠" \
            "5" "封鎖連接埠" \
            "6" "刪除規則" \
            "7" "返回" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 || "$choice" == "7" ]] && return

        case "$choice" in
            1)
                whiptail --title "防火牆規則" --scrolltext \
                    --msgbox "$(sudo_run ufw status verbose 2>/dev/null)" 30 72
                ;;
            2)
                confirm "啟用防火牆？（未明確允許的連線將被阻擋）" || continue
                ensure_sudo || continue
                msg "結果：\n$(echo "$SUDO_PASS" | sudo -S ufw --force enable 2>&1)"
                ;;
            3)
                confirm "停用防火牆？（所有連線將不受限制）" || continue
                ensure_sudo || continue
                msg "結果：\n$(sudo_run ufw disable 2>&1)"
                ;;
            4)
                local port
                port=$(whiptail --title "$TITLE" \
                    --inputbox "允許的連接埠（如 80, 443, 22/tcp, 8080:8090/tcp）：" 8 65 "" \
                    3>&1 1>&2 2>&3)
                [[ $? -ne 0 || -z "$port" ]] && continue
                ensure_sudo || continue
                msg "✅ 已允許 ${port}：\n$(sudo_run ufw allow "$port" 2>&1)"
                ;;
            5)
                local port
                port=$(whiptail --title "$TITLE" \
                    --inputbox "封鎖的連接埠（如 23, 3389, 445/tcp）：" 8 65 "" \
                    3>&1 1>&2 2>&3)
                [[ $? -ne 0 || -z "$port" ]] && continue
                ensure_sudo || continue
                msg "✅ 已封鎖 ${port}：\n$(sudo_run ufw deny "$port" 2>&1)"
                ;;
            6)
                ensure_sudo || continue
                local rules=()
                local i=1
                while IFS= read -r line; do
                    [[ "$line" =~ ^\[ ]] && rules+=("$i" "${line}") && ((i++))
                done < <(sudo_run ufw status numbered 2>/dev/null)
                [[ ${#rules[@]} -eq 0 ]] && { msg "沒有可刪除的規則。"; continue; }
                local num
                num=$(whiptail --title "$TITLE" --menu "選擇要刪除的規則：" 20 72 10 \
                    "${rules[@]}" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                confirm "確認刪除規則 #${num}？" || continue
                msg "結果：\n$(echo "$SUDO_PASS" | sudo -S ufw --force delete "$num" 2>&1)"
                ;;
        esac
    done
}

# ── 8. 連線診斷工具 ───────────────────────────────────────────────────────────

diagnostic_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE — 連線診斷" \
            --menu "選擇工具：" 17 60 7 \
            "1" "Ping 測試" \
            "2" "路由追蹤 (traceroute)" \
            "3" "DNS 查詢 (dig)" \
            "4" "連接埠狀態 (ss)" \
            "5" "下載速度測試 (curl)" \
            "6" "查看路由表" \
            "7" "返回" \
            3>&1 1>&2 2>&3)
        [[ $? -ne 0 || "$choice" == "7" ]] && return

        case "$choice" in
            1)
                local host count
                host=$(whiptail --title "$TITLE" --inputbox "Ping 目標（主機名稱或 IP）：" 8 55 "8.8.8.8" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 || -z "$host" ]] && continue
                count=$(whiptail --title "$TITLE" --inputbox "次數：" 8 30 "5" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                whiptail --title "Ping ${host}" --scrolltext \
                    --msgbox "$(ping -c "${count:-5}" -W 3 "$host" 2>&1)" 20 72
                ;;
            2)
                if ! command -v traceroute &>/dev/null; then
                    msg "未安裝 traceroute。\n請執行：sudo apt install traceroute"
                    continue
                fi
                local host
                host=$(whiptail --title "$TITLE" --inputbox "路由追蹤目標：" 8 55 "8.8.8.8" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 || -z "$host" ]] && continue
                whiptail --title "$TITLE" --infobox "正在追蹤路由到 ${host}..." 6 50
                whiptail --title "路由追蹤 ${host}" --scrolltext \
                    --msgbox "$(traceroute -m 15 -w 2 "$host" 2>&1)" 25 78
                ;;
            3)
                local host qtype
                host=$(whiptail --title "$TITLE" --inputbox "DNS 查詢目標（網域名稱）：" 8 55 "google.com" 3>&1 1>&2 2>&3)
                [[ $? -ne 0 || -z "$host" ]] && continue
                qtype=$(whiptail --title "$TITLE" \
                    --menu "查詢類型：" 14 45 5 \
                    "A"    "IPv4 位址" \
                    "AAAA" "IPv6 位址" \
                    "MX"   "郵件伺服器" \
                    "TXT"  "文字記錄" \
                    "ANY"  "所有記錄" \
                    3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                whiptail --title "DNS 查詢 ${host} (${qtype})" --scrolltext \
                    --msgbox "$(dig "$qtype" "$host" 2>&1)" 25 78
                ;;
            4)
                local filter
                filter=$(whiptail --title "$TITLE" \
                    --menu "查看連線狀態：" 14 55 5 \
                    "established" "已建立的連線" \
                    "listen"      "監聽中的連接埠" \
                    "all"         "全部連線" \
                    "tcp"         "TCP 連線" \
                    "udp"         "UDP 連線" \
                    3>&1 1>&2 2>&3)
                [[ $? -ne 0 ]] && continue
                local result
                case "$filter" in
                    established) result=$(ss -tnp state established 2>&1) ;;
                    listen)      result=$(ss -tlnp 2>&1) ;;
                    all)         result=$(ss -tunap 2>&1) ;;
                    tcp)         result=$(ss -tnap 2>&1) ;;
                    udp)         result=$(ss -unap 2>&1) ;;
                esac
                whiptail --title "連線狀態 (${filter})" --scrolltext --msgbox "$result" 30 90
                ;;
            5)
                whiptail --title "$TITLE" --infobox "正在測試下載速度（最多 10 秒）..." 6 50
                local speed
                speed=$(curl -s -o /dev/null -w "%{speed_download}" \
                    --max-time 10 "http://speedtest.tele2.net/10MB.zip" 2>/dev/null)
                local out=""
                if [[ -n "$speed" && "$speed" != "0.000000" ]]; then
                    local mb mbps
                    mb=$(awk "BEGIN{printf \"%.2f\", $speed/1024/1024}")
                    mbps=$(awk "BEGIN{printf \"%.1f\", $speed*8/1024/1024}")
                    out="下載速度：${mb} MB/s\n（約 ${mbps} Mbps）\n\n測試伺服器：speedtest.tele2.net"
                else
                    out="❌ 無法取得速度（請確認網路連線）"
                fi
                whiptail --title "速度測試結果" --msgbox "$out" 12 55
                ;;
            6)
                local result
                result="=== IPv4 路由表 ===\n$(ip route show 2>/dev/null)\n\n=== IPv6 路由表 ===\n$(ip -6 route show 2>/dev/null)"
                whiptail --title "路由表" --scrolltext --msgbox "$result" 25 78
                ;;
        esac
    done
}

# ── 9. 主機名稱設定 ───────────────────────────────────────────────────────────

hostname_menu() {
    local current_hostname
    current_hostname=$(hostnamectl --static 2>/dev/null || hostname)

    local choice
    choice=$(whiptail --title "$TITLE — 主機名稱" \
        --menu "目前主機名稱：${current_hostname}" 12 60 3 \
        "1" "查看詳細主機資訊" \
        "2" "修改主機名稱" \
        "3" "返回" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 || "$choice" == "3" ]] && return

    case "$choice" in
        1)
            whiptail --title "主機資訊" --scrolltext \
                --msgbox "$(hostnamectl 2>/dev/null)" 20 65
            ;;
        2)
            local new_name
            new_name=$(whiptail --title "$TITLE" \
                --inputbox "新主機名稱：" 8 50 "$current_hostname" \
                3>&1 1>&2 2>&3)
            [[ $? -ne 0 || -z "$new_name" ]] && return
            ensure_sudo || return
            sudo_run hostnamectl set-hostname "$new_name"
            msg "✅ 主機名稱已改為：${new_name}"
            ;;
    esac
}

# ── 10. 代理設定 ──────────────────────────────────────────────────────────────

proxy_menu() {
    local cur_http="${HTTP_PROXY:-${http_proxy:-（未設定）}}"

    local choice
    choice=$(whiptail --title "$TITLE — 代理設定" \
        --menu "HTTP_PROXY：${cur_http}" 14 65 4 \
        "1" "查看目前代理設定" \
        "2" "設定代理伺服器" \
        "3" "清除代理設定" \
        "4" "返回" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 || "$choice" == "4" ]] && return

    case "$choice" in
        1)
            local out=""
            out+="HTTP_PROXY:  ${HTTP_PROXY:-（未設定）}\n"
            out+="HTTPS_PROXY: ${HTTPS_PROXY:-（未設定）}\n"
            out+="NO_PROXY:    ${NO_PROXY:-（未設定）}\n"
            out+="\n/etc/environment 代理設定：\n"
            out+="$(grep -i proxy /etc/environment 2>/dev/null || echo '（無）')\n"
            out+="\nAPT 代理設定：\n"
            out+="$(cat /etc/apt/apt.conf.d/*proxy* 2>/dev/null || echo '（無）')\n"
            whiptail --title "代理設定" --scrolltext --msgbox "$out" 22 72
            ;;
        2)
            local proxy
            proxy=$(whiptail --title "$TITLE" \
                --inputbox "代理伺服器（如 http://proxy.example.com:3128）：" 8 65 "" \
                3>&1 1>&2 2>&3)
            [[ $? -ne 0 || -z "$proxy" ]] && return
            ensure_sudo || return
            sudo_run bash -c "
                sed -i '/^[Hh][Tt][Tt][Pp][Ss]\?_[Pp][Rr][Oo][Xx][Yy]/Id' /etc/environment
                printf 'http_proxy=%s\nhttps_proxy=%s\nHTTP_PROXY=%s\nHTTPS_PROXY=%s\n' \
                    '${proxy}' '${proxy}' '${proxy}' '${proxy}' >> /etc/environment
            "
            msg "✅ 代理已設定為 ${proxy}\n（重新登入後生效）"
            ;;
        3)
            ensure_sudo || return
            sudo_run bash -c "sed -i '/^[Hh][Tt][Tt][Pp][Ss]\?_[Pp][Rr][Oo][Xx][Yy]/Id' /etc/environment"
            msg "✅ 代理設定已清除（重新登入後生效）"
            ;;
    esac
}

# ── 主選單 ────────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "$TITLE" \
            --menu "請選擇操作：" 22 72 10 \
            "1"  "[總覽]    網路總覽 — 介面、IP、DNS、外部 IP" \
            "2"  "[介面]    介面詳情 — 查看任何介面的詳細資訊" \
            "3"  "[有線]    有線網路 — IP / DHCP / 靜態 IP 設定" \
            "4"  "[WiFi]    無線網路 — 掃描、連線、管理儲存網路" \
            "5"  "[VPN]     VPN 管理 — 連線、斷開 VPN" \
            "6"  "[DNS]     DNS 設定 — 查看、變更 DNS 伺服器" \
            "7"  "[防火牆]  UFW 管理 — 規則、允許、封鎖連接埠" \
            "8"  "[診斷]    連線診斷 — Ping / Traceroute / DNS 查詢" \
            "9"  "[主機]    主機名稱 — 查看、修改主機名稱" \
            "10" "[代理]    代理設定 — HTTP Proxy 管理" \
            "11" "離開" \
            3>&1 1>&2 2>&3)

        [[ $? -ne 0 || "$choice" == "11" ]] && break

        case "$choice" in
            1)  view_overview ;;
            2)  view_interface_detail ;;
            3)  ethernet_menu ;;
            4)  wifi_menu ;;
            5)  vpn_menu ;;
            6)  dns_menu ;;
            7)  firewall_menu ;;
            8)  diagnostic_menu ;;
            9)  hostname_menu ;;
            10) proxy_menu ;;
        esac
    done
}

# ── 入口 ──────────────────────────────────────────────────────────────────────

clear
echo -e "${BOLD}${CYAN}${TITLE}${NC}"
echo -e "${YELLOW}部分操作需要 sudo 密碼（首次操作時會詢問）。${NC}\n"

if ! command -v nmcli &>/dev/null; then
    echo -e "${RED}找不到 nmcli，請安裝：sudo apt install network-manager${NC}"
    exit 1
fi
if ! command -v whiptail &>/dev/null; then
    echo -e "${RED}找不到 whiptail，請安裝：sudo apt install whiptail${NC}"
    exit 1
fi

main_menu
echo -e "\n${GREEN}已離開。${NC}"
