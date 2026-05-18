#!/bin/bash
# force-x11.sh — 強制 display manager 使用 X11，禁用 Wayland
#
# 動機：x11vnc 不支援 Wayland。本腳本把當下的 display manager 切到 X11 sessions，
#       讓 setup-screen.sh 部署的 x11vnc 在 Jetson / 樹莓派 / 桌機都能正常運作。
#
# 支援的 display manager：
#   - GDM / GDM3   寫入 WaylandEnable=false（Ubuntu / Jetson 預設）
#   - SDDM         寫 /etc/sddm.conf.d/10-force-x11.conf DisplayServer=x11（KDE）
#   - Raspberry Pi raspi-config nonint do_wayland W1（labwc → X11）
#   - LightDM      預設即為 X11，不需特別處理
#
# 變更皆冪等：重複執行不會造成壞影響。
#
# 通常透過上層 setup-screen.sh 呼叫，亦可單獨執行：
#   sudo bash ~/.config/nvim/script/sub/force-x11.sh

set -e

CHANGED=0

echo "=== 偵測並強制 X11 session ==="

# === 1. GDM ===
for conf in /etc/gdm3/custom.conf /etc/gdm/custom.conf; do
    [ -f "$conf" ] || continue
    if grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' "$conf"; then
        echo "  GDM: $conf 已是 WaylandEnable=false，略過"
    elif grep -qE '^[[:space:]]*#?[[:space:]]*WaylandEnable[[:space:]]*=' "$conf"; then
        # 已存在（被註解或設成別值）→ 改寫
        sudo sed -i -E 's|^[[:space:]]*#?[[:space:]]*WaylandEnable[[:space:]]*=.*|WaylandEnable=false|' "$conf"
        echo "  GDM: 已改寫 $conf 為 WaylandEnable=false"
        CHANGED=1
    elif grep -q '^\[daemon\]' "$conf"; then
        sudo sed -i '/^\[daemon\]/a WaylandEnable=false' "$conf"
        echo "  GDM: 已在 $conf 的 [daemon] 加入 WaylandEnable=false"
        CHANGED=1
    else
        # 整個檔案沒有 [daemon] 段 → append
        printf '\n[daemon]\nWaylandEnable=false\n' | sudo tee -a "$conf" > /dev/null
        echo "  GDM: 已 append [daemon]+WaylandEnable=false 到 $conf"
        CHANGED=1
    fi
done

# === 2. SDDM ===
if [ -x /usr/bin/sddm ] || [ -d /etc/sddm.conf.d ] || [ -f /etc/sddm.conf ]; then
    sudo mkdir -p /etc/sddm.conf.d
    target=/etc/sddm.conf.d/10-force-x11.conf
    desired="# Written by force-x11.sh — 讓 x11vnc 可用
[General]
DisplayServer=x11
"
    if [ -f "$target" ] && [ "$(cat "$target")" = "$desired" ]; then
        echo "  SDDM: $target 已就緒，略過"
    else
        echo "$desired" | sudo tee "$target" > /dev/null
        echo "  SDDM: 已寫入 $target (DisplayServer=x11)"
        CHANGED=1
    fi
fi

# === 3. Raspberry Pi (raspi-config 可用時) ===
# W1 = X11 (labwc 停用)、W2 = labwc、W3 = wayfire
if command -v raspi-config >/dev/null 2>&1; then
    if sudo raspi-config nonint do_wayland W1 2>/dev/null; then
        echo "  Raspberry Pi: raspi-config 已切回 X11 (do_wayland W1)"
        CHANGED=1
    else
        echo "  Raspberry Pi: raspi-config 切換失敗（已嘗試 do_wayland W1）"
    fi
fi

# === 4. LightDM — 預設 X11 only，無動作 ===
if [ -x /usr/sbin/lightdm ] || [ -d /etc/lightdm ]; then
    echo "  LightDM: 預設即為 X11，無需動作"
fi

echo ""
if [ "$CHANGED" = "0" ]; then
    echo "結果：未發現需要切換的 DM（純 X11 或無 GUI 環境）"
else
    echo "結果：已套用 X11 強制設定。變更會在下次登入/重開機後生效。"
fi
