#!/usr/bin/env bash
# =============================================================================
# CVE-2026-31431 "Copy Fail" — algif_aead Mitigation Manager
#
# 此腳本管理 Linux kernel 模組 algif_aead 的黑名單狀態，
# 以緩解 CVE-2026-31431 本地提權漏洞。
#
# 使用方式：sudo bash copy-fail-mitigation.sh
# =============================================================================

set -euo pipefail

# 當腳本透過 pipe（curl | bash）執行時，stdin 不是終端機。
# 用 wrapper 覆寫 whiptail，強制每次呼叫都從 /dev/tty 讀取鍵盤輸入。
whiptail() { command whiptail "$@" 0</dev/tty; }

# ── 常數 ──────────────────────────────────────────────────────────────────────
readonly BLACKLIST_FILE="/etc/modprobe.d/copy-fail-mitigation.conf"
readonly MODULE_NAME="algif_aead"
readonly CVE_ID="CVE-2026-31431"
readonly TITLE="Copy Fail — ${CVE_ID} 緩解管理工具"

# ── 權限檢查 ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] 此腳本需要 root 權限，請以 sudo 執行。" >&2
    exit 1
fi

# ── 工具檢查 ──────────────────────────────────────────────────────────────────
if ! command -v whiptail &>/dev/null; then
    echo "[ERROR] 需要 whiptail，請先執行：apt install whiptail" >&2
    exit 1
fi

# ── 輔助函式 ──────────────────────────────────────────────────────────────────

is_blacklisted() {
    [[ -f "$BLACKLIST_FILE" ]] && grep -q "blacklist ${MODULE_NAME}" "$BLACKLIST_FILE"
}

is_loaded() {
    lsmod | grep -q "^${MODULE_NAME}"
}

enable_mitigation() {
    echo "blacklist ${MODULE_NAME}" > "$BLACKLIST_FILE"
    update-initramfs -u 2>&1 | tail -5
    if is_loaded; then
        if rmmod "$MODULE_NAME" 2>/dev/null; then
            echo "模組已即時卸載。"
        else
            echo "模組卸載失敗（可能有程序正在使用），重開機後生效。"
        fi
    fi
}

disable_mitigation() {
    rm -f "$BLACKLIST_FILE"
    update-initramfs -u 2>&1 | tail -5
}

show_cve_info() {
    whiptail --title "漏洞說明 — ${CVE_ID}" \
             --scrolltext \
             --msgbox \
"【CVE-2026-31431「Copy Fail」】
CVSS 評分：7.8（High）  公開日：2026-04-29

━━ 漏洞原理 ━━
Linux kernel 加密子系統中，algif_aead 模組（AF_ALG socket）
與 splice() 系統呼叫的組合，造成任意本地使用者可對 page cache
進行受控的 4-byte 寫入。

page cache 是 kernel 管理所有檔案的共享記憶體快取。
攻擊者可藉此竄改 /usr/bin/su 等 setuid 程式在記憶體中的內容，
無需寫入磁碟，以 732 bytes Python 腳本即可穩定提權至 root。

━━ 影響範圍 ━━
• 受影響 kernel：2017 年至今所有主流發行版
• 已確認：Ubuntu 24.04、Amazon Linux 2023、RHEL 10、SUSE 16
• 樹莓派 RPT kernel（6.12.x）：漏洞存在，PoC 受 ARM64 阻礙
  但不代表安全，仍建議套用緩解
• Jetson（NVIDIA L4T）：推估受影響，官方修補尚未釋出

━━ 緩解方式 ━━
將 algif_aead 加入 kernel 模組黑名單。
此模組主要供加密工具開發測試使用，一般系統停用無影響。

━━ 正式修補版本 ━━
• Debian Trixie：kernel 6.12.85-1（通用版已修補）
• RPT 專屬 kernel：尚待釋出（監控 apt upgrade）" \
             24 72
}

show_status() {
    if is_blacklisted; then
        bl_text="✔ 已封鎖（黑名單生效）"
    else
        bl_text="✘ 未封鎖（存在風險）"
    fi

    if is_loaded; then
        loaded_text="⚠ 模組目前已載入（危險）"
    else
        loaded_text="✔ 模組未載入（安全）"
    fi

    whiptail --title "目前系統狀態" \
             --msgbox \
"主機名稱  ：$(hostname)
Kernel    ：$(uname -r)
系統時間  ：$(date '+%Y-%m-%d %H:%M')

━━ algif_aead 模組狀態 ━━
黑名單封鎖：${bl_text}
即時狀態  ：${loaded_text}
設定檔    ：${BLACKLIST_FILE}" \
             16 60
}

main_menu() {
    while true; do
        if is_blacklisted; then
            status_line="緩解狀態：[啟用中] algif_aead 已封鎖"
        else
            status_line="緩解狀態：[未啟用] 系統存在 CVE-2026-31431 風險"
        fi

        local choice
        choice=$(whiptail --title "$TITLE" \
                          --menu \
"${status_line}

請選擇操作：" \
                          18 64 6 \
                          "1" "啟用緩解  — 封鎖 algif_aead（建議）" \
                          "2" "停用緩解  — 移除封鎖（風險：漏洞暴露）" \
                          "3" "查看狀態  — 顯示目前模組與黑名單狀態" \
                          "4" "漏洞說明  — 查看 CVE-2026-31431 詳情" \
                          "5" "離開" \
                          3>&1 1>&2 2>&3) || exit 0

        case "$choice" in
            1)
                if is_blacklisted; then
                    whiptail --title "已是啟用狀態" \
                             --msgbox "algif_aead 黑名單已存在，無需重複套用。" \
                             8 50
                else
                    if whiptail --title "確認啟用緩解" \
                                --yesno "將執行：\n  1. 寫入黑名單設定檔\n  2. 重新產生 initramfs\n  3. 嘗試即時卸載模組

確定要繼續？" \
                                12 55; then
                        enable_mitigation
                        whiptail --title "完成" \
                                 --msgbox "緩解措施已套用。\n若模組卸載失敗，重開機後即生效。" \
                                 10 50
                    fi
                fi
                ;;
            2)
                if ! is_blacklisted; then
                    whiptail --title "尚未啟用" \
                             --msgbox "目前黑名單不存在，無需移除。" \
                             8 50
                else
                    if whiptail --title "⚠ 警告：停用緩解" \
                                --defaultno \
                                --yesno "停用後系統將再次暴露於 CVE-2026-31431 風險。

僅在已取得官方 kernel 修補版本後才建議執行。

確定要停用？" \
                                12 60; then
                        disable_mitigation
                        whiptail --title "完成" \
                                 --msgbox "黑名單已移除。重開機後模組可重新載入。" \
                                 10 50
                    fi
                fi
                ;;
            3) show_status ;;
            4) show_cve_info ;;
            5) exit 0 ;;
        esac
    done
}

show_cve_info
main_menu