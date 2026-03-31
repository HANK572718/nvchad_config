#!/bin/bash
# ============================================================
# Universal Linux System Report Generator
# 通用 Linux 硬體資訊報告產生器（類 CPU-Z）
# 支援：Jetson Orin/Xavier/Nano、Raspberry Pi、一般 x86/ARM Linux
# ============================================================

set -uo pipefail

# ---------- 唯一識別碼收集 ----------
HOSTNAME_STR=$(hostname 2>/dev/null || echo "unknown")
DATE_STR=$(date '+%Y-%m-%d')
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
DATE_READABLE=$(date '+%Y-%m-%d %H:%M:%S')

# 優先順序：device-tree serial > DMI serial > RPi cpuinfo > machine-id 前8碼
SN_DT=$(tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null | xargs || echo "")
SN_DMI=$(cat /sys/class/dmi/id/product_serial 2>/dev/null | xargs || echo "")
SN_BOARD=$(cat /sys/class/dmi/id/board_serial 2>/dev/null | xargs || echo "")
SN_RPI=$(grep "^Serial" /proc/cpuinfo 2>/dev/null | awk '{print $3}' | xargs || echo "")
SN_MACHINE=$(cat /etc/machine-id 2>/dev/null | head -c 8 || echo "")
SN_NVME=$(cat /sys/block/nvme0n1/device/serial 2>/dev/null | xargs | tr -d ' ' || echo "")
SN_MAC=$(cat /sys/class/net/$(ls /sys/class/net/ 2>/dev/null | grep -v "^lo$\|^docker\|^veth\|^br-" | head -1)/address 2>/dev/null | tr -d ':' || echo "")

# 選出最佳序號作為識別碼（過濾空值與常見無效值）
is_valid_sn() {
    local v="$1"
    [[ -z "$v" ]] && return 1
    echo "$v" | grep -qiE "^(N/A|na|none|unknown|default|not|to be filled|0+)$" && return 1
    [[ "${#v}" -lt 4 ]] && return 1
    return 0
}

SERIAL_NUMBER="N/A"
for _candidate in "$SN_DT" "$SN_DMI" "$SN_BOARD" "$SN_RPI" "$SN_NVME"; do
    if is_valid_sn "$_candidate"; then
        SERIAL_NUMBER="$_candidate"
        break
    fi
done

# machine-id 作最後備援
if [[ "$SERIAL_NUMBER" == "N/A" ]] && is_valid_sn "$SN_MACHINE"; then
    SERIAL_NUMBER="mid-${SN_MACHINE}"
fi

# 檔名用的序號：取前12碼並去除特殊字元
SN_SHORT=$(echo "$SERIAL_NUMBER" | tr -dc '[:alnum:]-' | head -c 12)
[[ -z "$SN_SHORT" ]] && SN_SHORT="nosn"

# 檔名後綴：主機名_序號_日期
_SUFFIX="_${HOSTNAME_STR}_${SN_SHORT}_${DATE_STR}"
if [[ -n "${1:-}" ]]; then
    _RAW="${1}"
    if [[ "$_RAW" == *.* ]]; then
        _BASE="${_RAW%.*}"; _EXT="${_RAW##*.}"
    else
        _BASE="$_RAW"; _EXT="md"
    fi
    OUTPUT_FILE="${_BASE}${_SUFFIX}.${_EXT}"
else
    OUTPUT_FILE="sysreport${_SUFFIX}.md"
fi

# ---------- 終端顏色 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*" >&2; }

# ---------- 輔助函式 ----------
# 執行指令，失敗時回傳指定預設值
try() { local default="${1:-N/A}"; shift; eval "$*" 2>/dev/null || echo "$default"; }

# 讀取檔案，失敗回 N/A
rfile() { cat "$1" 2>/dev/null || echo "N/A"; }

# 去除 ANSI escape codes
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g' | tr -d '\000' | xargs; }

# 位元組轉換
bytes_to_human() {
    local b="${1:-0}"
    if   (( b >= 1073741824 )); then printf "%.1f GB" "$(echo "scale=1; $b/1073741824" | bc)";
    elif (( b >= 1048576 ));    then printf "%.1f MB" "$(echo "scale=1; $b/1048576" | bc)";
    elif (( b >= 1024 ));       then printf "%.1f KB" "$(echo "scale=1; $b/1024" | bc)";
    else printf "%d B" "$b"; fi
}

# KB 轉人類可讀
kb_to_human() {
    local kb="${1:-0}"
    if   (( kb >= 1048576 )); then printf "%.1f GB" "$(echo "scale=1; $kb/1048576" | bc)";
    elif (( kb >= 1024 ));    then printf "%.1f MB" "$(echo "scale=1; $kb/1024" | bc)";
    else printf "%d KB" "$kb"; fi
}

# check mark
ckmark() {
    local val="$1" na="${2:-未安裝}"
    if [[ "$val" == "N/A" || "$val" == "$na" || -z "$val" ]]; then echo "❌ ${na}"; else echo "✅ ${val}"; fi
}

# 工具是否存在
has() { command -v "$1" &>/dev/null; }

# ============================================================
# 0. 偵測平台類型
# ============================================================
log "偵測平台類型..."

PLATFORM="generic"
DEVICE_MODEL="N/A"

# 讀取裝置樹型號（ARM 板常見）
if [[ -f /proc/device-tree/model ]]; then
    DEVICE_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "N/A")
fi

# 嘗試 DMI / SMBIOS（x86 常見）
if [[ "$DEVICE_MODEL" == "N/A" ]] && has dmidecode; then
    DEVICE_MODEL=$(dmidecode -s system-product-name 2>/dev/null | head -1 || echo "N/A")
fi
if [[ "$DEVICE_MODEL" == "N/A" ]]; then
    DEVICE_MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "N/A")
fi

ARCH=$(uname -m)
KERNEL_VER=$(uname -r)

# 判斷平台
if echo "$DEVICE_MODEL $KERNEL_VER" | grep -qi "jetson\|tegra\|orin\|xavier" || \
   [[ -f /etc/nv_tegra_release ]] || \
   ls /sys/class/devfreq/ 2>/dev/null | grep -q "\.gpu$"; then
    PLATFORM="jetson"
elif echo "$DEVICE_MODEL" | grep -qi "raspberry\|rpi\|bcm"; then
    PLATFORM="rpi"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "i686" ]]; then
    PLATFORM="x86"
elif [[ "$ARCH" == aarch64* || "$ARCH" == arm* ]]; then
    PLATFORM="arm"
fi

log "平台: ${PLATFORM} | 架構: ${ARCH}"

# ============================================================
# 1. 作業系統 & 核心
# ============================================================
log "收集 OS 資訊..."

OS_NAME=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "N/A")
OS_ID=$(. /etc/os-release 2>/dev/null && echo "$ID" || echo "N/A")
HOSTNAME_FULL=$(hostname -f 2>/dev/null || hostname)
UPTIME_STR=$(uptime -p 2>/dev/null || uptime | awk -F'up' '{print $2}' | awk -F',' '{print $1}' | xargs)
BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")
TIMEZONE=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || cat /etc/timezone 2>/dev/null || echo "N/A")
LOCALE=$(locale 2>/dev/null | grep LANG= | head -1 || echo "N/A")

# ============================================================
# 2. CPU
# ============================================================
log "收集 CPU 資訊..."

CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || \
            grep -m1 "Model name" <(lscpu 2>/dev/null) | awk -F': ' '{print $2}' | xargs || \
            grep -m1 "Hardware" /proc/cpuinfo | awk -F': ' '{print $2}' || echo "N/A")
CPU_VENDOR=$(grep -m1 "vendor_id\|CPU implementer" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || echo "N/A")
CPU_FAMILY=$(grep -m1 "cpu family" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || echo "N/A")
CPU_STEPPING=$(grep -m1 "stepping" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' || echo "N/A")
CPU_CORES_LOGICAL=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo || echo "N/A")
CPU_CORES_PHYSICAL=$(lscpu 2>/dev/null | grep "^Core(s) per" | awk '{print $NF}' || echo "N/A")
CPU_SOCKETS=$(lscpu 2>/dev/null | grep "^Socket(s)" | awk '{print $NF}' || echo "1")
CPU_THREADS_PER_CORE=$(lscpu 2>/dev/null | grep "^Thread(s) per core" | awk '{print $NF}' || echo "N/A")
CPU_MAX_MHZ=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $NF}' || echo "N/A")
CPU_MIN_MHZ=$(lscpu 2>/dev/null | grep "CPU min MHz" | awk '{print $NF}' || echo "N/A")
CPU_CUR_MHZ="N/A"
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    _freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    CPU_CUR_MHZ=$(echo "scale=1; $_freq / 1000" | bc 2>/dev/null || echo "N/A")
fi
CPU_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
CPU_BOGOMIPS=$(grep -m1 "BogoMIPS\|bogomips" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' | xargs || echo "N/A")

# CPU 快取
CPU_L1D=$(lscpu 2>/dev/null | grep "L1d" | awk -F: '{print $2}' | xargs)
CPU_L1I=$(lscpu 2>/dev/null | grep "L1i" | awk -F: '{print $2}' | xargs)
CPU_L2=$(lscpu 2>/dev/null | grep "L2 cache" | awk -F: '{print $2}' | xargs)
CPU_L3=$(lscpu 2>/dev/null | grep "L3 cache" | awk -F: '{print $2}' | xargs)
# sysfs 備援
[[ -z "$CPU_L1D" ]] && CPU_L1D=$(cat /sys/devices/system/cpu/cpu0/cache/index0/size 2>/dev/null | xargs && echo " (per core)" || echo "")
[[ -z "$CPU_L2" ]]  && CPU_L2=$(cat /sys/devices/system/cpu/cpu0/cache/index2/size 2>/dev/null | xargs && echo " (per core)" || echo "")
[[ -z "$CPU_L1D" ]] && CPU_L1D="N/A"
[[ -z "$CPU_L1I" ]] && CPU_L1I="N/A"
[[ -z "$CPU_L2" ]]  && CPU_L2="N/A"
[[ -z "$CPU_L3" ]]  && CPU_L3="N/A"

# CPU 功能旗標
CPU_FLAGS=$(grep -m1 "^flags\|^Features" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}' | \
    tr ' ' '\n' | grep -E "^(sse|avx|aes|neon|vmx|svm|hypervisor|vfp)" | sort -u | tr '\n' ' ' || echo "N/A")

# 虛擬化
CPU_VIRT=$(lscpu 2>/dev/null | grep "Virtualization" | awk -F: '{print $2}' | xargs || \
           grep -qm1 "vmx" /proc/cpuinfo 2>/dev/null && echo "VT-x" || \
           grep -qm1 "svm" /proc/cpuinfo 2>/dev/null && echo "AMD-V" || echo "N/A")

# 每顆 CPU 目前頻率列表
CPU_ALL_FREQS=""
for i in $(seq 0 $((CPU_CORES_LOGICAL - 1))); do
    f=$(cat /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq 2>/dev/null || echo "")
    if [[ -n "$f" ]]; then
        CPU_ALL_FREQS+="CPU${i}: $(echo "scale=0; $f/1000" | bc)MHz  "
    fi
done
[[ -z "$CPU_ALL_FREQS" ]] && CPU_ALL_FREQS="N/A"

# 溫度（各核心）
CPU_TEMP="N/A"
for zone in /sys/class/thermal/thermal_zone*/; do
    _type=$(cat "${zone}type" 2>/dev/null || echo "")
    if echo "$_type" | grep -qi "cpu\|soc\|core\|pkg\|x86"; then
        _temp=$(cat "${zone}temp" 2>/dev/null || echo "")
        if [[ -n "$_temp" && "$_temp" -gt 1000 ]]; then
            CPU_TEMP=$(echo "scale=1; $_temp/1000" | bc)°C
            break
        fi
    fi
done

# ============================================================
# 3. 記憶體
# ============================================================
log "收集記憶體資訊..."

MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_BUFFERS_KB=$(grep Buffers /proc/meminfo | awk '{print $2}')
MEM_CACHED_KB=$(grep "^Cached:" /proc/meminfo | awk '{print $2}')
MEM_USED_KB=$(( MEM_TOTAL_KB - MEM_AVAIL_KB ))
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
MEM_DIRTY_KB=$(grep "^Dirty:" /proc/meminfo | awk '{print $2}' || echo "0")
HUGEPAGE_SIZE=$(grep Hugepagesize /proc/meminfo | awk '{print $2, $3}' || echo "N/A")
HUGEPAGE_TOTAL=$(grep HugePages_Total /proc/meminfo | awk '{print $2}' || echo "N/A")

MEM_TOTAL_H=$(kb_to_human $MEM_TOTAL_KB)
MEM_USED_H=$(kb_to_human $MEM_USED_KB)
MEM_AVAIL_H=$(kb_to_human $MEM_AVAIL_KB)
MEM_BUFFERS_H=$(kb_to_human $MEM_BUFFERS_KB)
MEM_CACHED_H=$(kb_to_human $MEM_CACHED_KB)
SWAP_TOTAL_H=$(kb_to_human $SWAP_TOTAL_KB)
MEM_USED_PCT=$(echo "scale=1; $MEM_USED_KB * 100 / $MEM_TOTAL_KB" | bc 2>/dev/null || echo "N/A")

# 實體 DIMM 資訊（需要 dmidecode）
MEM_SLOTS="N/A"; MEM_TYPE="N/A"; MEM_SPEED="N/A"; MEM_FORM="N/A"
if has dmidecode; then
    MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep "Type:" | grep -v "Error\|Unknown\|None" | head -1 | awk '{print $2}' || echo "N/A")
    MEM_SPEED=$(dmidecode -t memory 2>/dev/null | grep "Speed:" | grep -v "Unknown\|N/A" | head -1 | awk '{print $2, $3}' || echo "N/A")
    MEM_FORM=$(dmidecode -t memory 2>/dev/null | grep "Form Factor:" | grep -v "Unknown" | head -1 | awk -F': ' '{print $2}' | xargs || echo "N/A")
    MEM_SLOTS=$(dmidecode -t memory 2>/dev/null | grep "Number Of Devices:" | awk '{print $NF}' | head -1 || echo "N/A")
fi

# ============================================================
# 4. 磁碟 — 分區詳情
# ============================================================
log "收集磁碟 & 分區資訊..."

# 4a. 實體磁碟
DISK_LIST=$(lsblk -d -o NAME,SIZE,TYPE,ROTA,MODEL,TRAN,VENDOR 2>/dev/null | grep -v "^loop\|^zram\|^NAME" || \
            lsblk -d -o NAME,SIZE,TYPE 2>/dev/null | grep -v loop || echo "N/A")

# 4b. 所有分區（含掛載點 & 使用率）
PART_TABLE=""
while IFS= read -r line; do
    PART_TABLE+="$line\n"
done < <(df -h --output=source,fstype,size,used,avail,pcent,target 2>/dev/null | \
         grep -v "^tmpfs\|^devtmpfs\|^udev\|^none\|^Filesystem" | \
         awk 'NR==1 || $7 != "" {print}' || \
         df -h 2>/dev/null | grep -v "^tmpfs\|^devtmpfs\|^Filesystem")

# 4c. 磁碟分區表 (lsblk 樹狀)
LSBLK_TREE=$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null | grep -v "^loop" || echo "N/A")

# 4d. SMART 狀態（若有 smartctl）
SMART_INFO=""
if has smartctl; then
    for dev in $(lsblk -d -o NAME,TYPE 2>/dev/null | grep disk | awk '{print "/dev/"$1}' | grep -v zram); do
        _smart=$(smartctl -H "$dev" 2>/dev/null | grep "SMART overall-health" | awk -F': ' '{print $2}' | xargs || echo "N/A")
        SMART_INFO+="$dev: $_smart  "
    done
fi
[[ -z "$SMART_INFO" ]] && SMART_INFO="N/A (需要 smartmontools)"

# 4e. inode 使用率
INODE_TABLE=$(df -i 2>/dev/null | grep -v "^tmpfs\|^devtmpfs\|^udev\|^Filesystem" | \
              awk 'NR==1 || ($6 ~ /[0-9]/ && $6 != "0%")' || echo "N/A")

# ============================================================
# 5. GPU
# ============================================================
log "收集 GPU 資訊..."

GPU_FOUND=false

# --- 5a. NVIDIA (含 Jetson Tegra) ---
NVIDIA_DRV_VER=$(cat /proc/driver/nvidia/version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "")
GPU_DEVFREQ=$(ls /sys/class/devfreq/ 2>/dev/null | grep -E "\.gpu$" | head -1 || echo "")

if [[ -n "$NVIDIA_DRV_VER" || -n "$GPU_DEVFREQ" ]]; then
    GPU_FOUND=true
    GPU_VENDOR="NVIDIA"
    GPU_DRIVER="${NVIDIA_DRV_VER:-N/A}"
    if [[ -n "$GPU_DEVFREQ" ]]; then
        GPU_MAX_HZ=$(cat "/sys/class/devfreq/${GPU_DEVFREQ}/max_freq" 2>/dev/null || echo "0")
        GPU_CUR_HZ=$(cat "/sys/class/devfreq/${GPU_DEVFREQ}/cur_freq" 2>/dev/null || echo "0")
        GPU_AVAIL_HZ=$(cat "/sys/class/devfreq/${GPU_DEVFREQ}/available_frequencies" 2>/dev/null || echo "")
        GPU_MAX_MHZ=$(echo "scale=0; ${GPU_MAX_HZ}/1000000" | bc 2>/dev/null || echo "N/A")
        GPU_CUR_MHZ=$(echo "scale=0; ${GPU_CUR_HZ}/1000000" | bc 2>/dev/null || echo "N/A")
        GPU_AVAIL_MHZ=$(echo "$GPU_AVAIL_HZ" | tr ' ' '\n' | awk '{printf "%.0f ", $1/1000000}' | xargs || echo "N/A")
    else
        GPU_MAX_MHZ="N/A"; GPU_CUR_MHZ="N/A"; GPU_AVAIL_MHZ="N/A"
    fi
    # nvidia-smi（有則用）
    _nsmi_test=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -v "Unable\|Error\|error" | head -1)
    if [[ -n "$_nsmi_test" ]]; then
        GPU_NAME=$_nsmi_test
        GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | grep -v "Unable\|Error" | head -1 || echo "N/A")
        GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | grep -v "Unable\|Error" | head -1 || echo "N/A")
        _nsmi_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | grep -v "Unable\|Error" | head -1 || echo "N/A")
        GPU_TEMP="${_nsmi_temp}°C"
        GPU_PWR=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader 2>/dev/null | grep -v "Unable\|Error" | head -1 || echo "N/A")
    else
        # Tegra iGPU：nvidia-smi 不支援，從 sysfs 或 l4t 取名
        _l4t_major=$(cat /etc/nv_tegra_release 2>/dev/null | grep -oP 'R\K\d+' | head -1 || echo "0")
        case "$_l4t_major" in
            36) GPU_NAME="Jetson Orin iGPU (Ampere)" ;;
            35|34) GPU_NAME="Jetson Xavier iGPU (Volta)" ;;
            32) GPU_NAME="Jetson Nano iGPU (Maxwell)" ;;
            *) GPU_NAME="NVIDIA Tegra iGPU" ;;
        esac
        GPU_MEM="Unified (共用系統記憶體)"; GPU_UTIL="N/A"; GPU_TEMP="N/A"; GPU_PWR="N/A"
    fi
fi

# --- 5b. AMD (ROCm / AMDGPU) ---
if ! $GPU_FOUND && has rocm-smi; then
    GPU_FOUND=true
    GPU_VENDOR="AMD"
    GPU_NAME=$(rocm-smi --showproductname 2>/dev/null | grep "Card series" | awk -F': ' '{print $2}' | xargs || echo "N/A")
    GPU_DRIVER=$(rocm-smi --showdriverversion 2>/dev/null | grep "Driver" | awk '{print $NF}' || echo "N/A")
    GPU_TEMP=$(rocm-smi --showtemp 2>/dev/null | grep -oP 'Temp.*: \K[\d.]+' | head -1 || echo "N/A")°C
    GPU_UTIL=$(rocm-smi --showuse 2>/dev/null | grep -oP 'GPU use.*: \K[\d]+' | head -1 || echo "N/A")%
    GPU_MEM="N/A"; GPU_MAX_MHZ="N/A"; GPU_CUR_MHZ="N/A"; GPU_AVAIL_MHZ="N/A"; GPU_PWR="N/A"
fi

# --- 5c. Intel iGPU ---
if ! $GPU_FOUND; then
    _intel_gpu=$(lspci 2>/dev/null | grep -i "VGA\|Display\|3D" | head -3)
    if echo "$_intel_gpu" | grep -qi "Intel"; then
        GPU_FOUND=true
        GPU_VENDOR="Intel"
        GPU_NAME=$(echo "$_intel_gpu" | grep -i Intel | head -1 | awk -F': ' '{print $2}' | xargs || echo "N/A")
        GPU_DRIVER=$(cat /sys/bus/pci/devices/*/uevent 2>/dev/null | grep DRIVER | grep -i "i915\|xe" | head -1 | awk -F= '{print $2}' || echo "N/A")
        GPU_TEMP=$(cat /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1 | awk '{printf "%.1f", $1/1000}' || echo "N/A")°C
        GPU_MEM="Shared"; GPU_UTIL="N/A"; GPU_MAX_MHZ="N/A"; GPU_CUR_MHZ="N/A"; GPU_AVAIL_MHZ="N/A"; GPU_PWR="N/A"
    fi
fi

# --- 5d. Raspberry Pi VideoCore / Broadcom ---
if ! $GPU_FOUND && echo "$DEVICE_MODEL" | grep -qi "raspberry\|rpi"; then
    GPU_FOUND=true
    GPU_VENDOR="Broadcom"
    GPU_NAME="VideoCore"
    GPU_DRIVER="vc4/v3d"
    GPU_MEM=$(vcgencmd get_mem gpu 2>/dev/null | awk -F= '{print $2}' || echo "N/A")
    GPU_TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "N/A")°C
    GPU_UTIL="N/A"; GPU_MAX_MHZ="N/A"; GPU_CUR_MHZ="N/A"; GPU_AVAIL_MHZ="N/A"; GPU_PWR="N/A"
fi

# --- 5e. 從 lspci 列出所有顯示卡 ---
GPU_LSPCI=$(lspci 2>/dev/null | grep -iE "VGA|Display|3D controller|GPU" || echo "N/A")

if ! $GPU_FOUND; then
    GPU_VENDOR="N/A"; GPU_NAME="N/A"; GPU_DRIVER="N/A"; GPU_MEM="N/A"
    GPU_UTIL="N/A"; GPU_TEMP="N/A"; GPU_PWR="N/A"; GPU_MAX_MHZ="N/A"; GPU_CUR_MHZ="N/A"; GPU_AVAIL_MHZ="N/A"
fi

# Jetson 補充：GPU 架構 / CC
GPU_ARCH="N/A"; GPU_CC="N/A"; GPU_CUDA_CORES="N/A"; GPU_DLA="N/A"
if [[ "$PLATFORM" == "jetson" ]]; then
    L4T_MAJOR=$(cat /etc/nv_tegra_release 2>/dev/null | grep -oP 'R\K\d+' | head -1 || echo "0")
    if [[ "$L4T_MAJOR" == "36" ]]; then
        GPU_ARCH="Ampere"; GPU_CC="8.7"; GPU_CUDA_CORES="1024"; GPU_DLA="2×"
    elif [[ "$L4T_MAJOR" == "35" || "$L4T_MAJOR" == "34" ]]; then
        GPU_ARCH="Volta";  GPU_CC="7.2"; GPU_CUDA_CORES="512";  GPU_DLA="2×"
    elif [[ "$L4T_MAJOR" == "32" ]]; then
        GPU_ARCH="Maxwell";GPU_CC="5.3"; GPU_CUDA_CORES="128";  GPU_DLA="N/A"
    fi
fi

# ============================================================
# 6. CUDA / AI 堆疊（Jetson & 一般 NVIDIA）
# ============================================================
log "收集 AI/CUDA 堆疊資訊..."

CUDA_VERSION="N/A"
for d in /usr/local/cuda /usr/local/cuda-1[0-9] /usr/local/cuda-[0-9]; do
    [[ -f "$d/version.json" ]] && \
        CUDA_VERSION=$(python3 -c "import json; d=json.load(open('$d/version.json')); print(list(d.values())[0]['version'])" 2>/dev/null) && break
    [[ -f "$d/version.txt" ]] && \
        CUDA_VERSION=$(grep -oP 'V[\d.]+' "$d/version.txt" | tr -d V) && break
done
[[ -z "$CUDA_VERSION" || "$CUDA_VERSION" == "N/A" ]] && \
    CUDA_VERSION=$(nvcc --version 2>/dev/null | grep -oP 'release \K[\d.]+' || echo "N/A")

NVCC_PATH=$(which nvcc 2>/dev/null || find /usr/local/cuda*/bin -name nvcc 2>/dev/null | head -1 || echo "N/A")

CUDNN_VER=$(dpkg -l 2>/dev/null | grep -E "libcudnn[0-9]" | awk '{print $3}' | head -1 || \
            python3 -c "import ctypes; l=ctypes.CDLL('libcudnn.so'); print(l.cudnnGetVersion())" 2>/dev/null || echo "N/A")
TRT_VER=$(python3 -c "import tensorrt; print(tensorrt.__version__)" 2>/dev/null || \
          dpkg -l tensorrt 2>/dev/null | awk '/^ii/{print $3}' | head -1 || echo "N/A")
VPI_VER=$(dpkg -l nvidia-vpi 2>/dev/null | awk '/^ii/{print $3}' | head -1 || echo "N/A")

PYTORCH_VER=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "N/A")
PYTORCH_CUDA=$(python3 -c "import torch; print(torch.version.cuda or 'N/A')" 2>/dev/null || echo "N/A")
PYTORCH_GPU=$(python3 -c "import torch; print('YES' if torch.cuda.is_available() else 'NO')" 2>/dev/null || echo "N/A")
PYTORCH_GPU_NAME=$(python3 -c "import torch; print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'N/A')" 2>/dev/null || echo "N/A")

OPENCV_VER=$(python3 -W ignore -c "import cv2; print(cv2.__version__)" 2>/dev/null | head -1 || echo "N/A")
OPENCV_CUDA=$(python3 -W ignore -c "
import cv2
bi = cv2.getBuildInformation()
for l in bi.splitlines():
    if 'USE_CUDA' in l or 'CUDA Toolkit' in l:
        print('YES' if 'YES' in l else 'NO'); break
else: print('NO')
" 2>/dev/null | head -1 || echo "N/A")

ONNXRT_VER=$(python3 -c "import onnxruntime; print(onnxruntime.__version__)" 2>/dev/null || echo "N/A")
TF_VER=$(python3 -c "import tensorflow; print(tensorflow.__version__)" 2>/dev/null || echo "N/A")

# ============================================================
# 7. 網路介面 & 網路資訊
# ============================================================
log "收集網路資訊..."

# 介面列表（含 MAC、速度、狀態）
NET_TABLE=""
while IFS= read -r iface; do
    [[ "$iface" == "lo" ]] && continue
    _mac=$(cat "/sys/class/net/${iface}/address" 2>/dev/null || echo "N/A")
    _state=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || echo "N/A")
    _speed=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null 2>/dev/null || echo "N/A")
    _type=$(cat "/sys/class/net/${iface}/type" 2>/dev/null || echo "N/A")
    # IP 位址
    _ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet )\S+' | head -1 || echo "—")
    _ipv6=$(ip -6 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet6 )\S+' | grep -v "^fe80\|^::1" | head -1 || echo "—")
    # MTU
    _mtu=$(ip link show "$iface" 2>/dev/null | grep -oP '(?<=mtu )\d+' || echo "N/A")
    # 判斷介面類型
    _kind="Ethernet"
    [[ -d "/sys/class/net/${iface}/wireless" ]] && _kind="WiFi"
    [[ "$iface" == can* ]] && _kind="CAN Bus"
    [[ "$iface" == docker* || "$iface" == veth* || "$iface" == br-* ]] && _kind="Virtual"
    [[ "$iface" == tun* || "$iface" == tap* ]] && _kind="VPN/Tunnel"

    NET_TABLE+="| \`${iface}\` | ${_kind} | \`${_mac}\` | ${_ipv4} | ${_ipv6:-—} | ${_state} | ${_speed} Mbps | ${_mtu} |\n"
done < <(ls /sys/class/net/ 2>/dev/null)

# DNS & 路由
DNS_SERVERS=$(cat /etc/resolv.conf 2>/dev/null | grep "^nameserver" | awk '{print $2}' | tr '\n' ' ' || echo "N/A")
DEFAULT_GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1 || route -n 2>/dev/null | grep "^0.0.0.0" | awk '{print $2}' | head -1 || echo "N/A")
DEFAULT_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1 || echo "N/A")
HOSTNAME_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")

# 網域
DOMAIN=$(cat /etc/resolv.conf 2>/dev/null | grep "^domain\|^search" | awk '{print $2}' | head -1 || echo "N/A")

# WiFi 資訊
WIFI_SSID="N/A"; WIFI_SIGNAL="N/A"; WIFI_CHANNEL="N/A"; WIFI_DRIVER="N/A"
WIFI_IF=$(ls /sys/class/net/ 2>/dev/null | xargs -I{} sh -c 'test -d /sys/class/net/{}/wireless && echo {}' 2>/dev/null | head -1)
if [[ -n "$WIFI_IF" ]]; then
    if has iwconfig; then
        WIFI_SSID=$(iwconfig "$WIFI_IF" 2>/dev/null | grep ESSID | grep -oP '"\K[^"]+' || echo "N/A")
        WIFI_SIGNAL=$(iwconfig "$WIFI_IF" 2>/dev/null | grep -oP 'Signal level=\K\S+' || echo "N/A")
    fi
    if has iw; then
        WIFI_CHANNEL=$(iw dev "$WIFI_IF" info 2>/dev/null | grep channel | awk '{print $2}' || echo "N/A")
        WIFI_SSID=$(iw dev "$WIFI_IF" info 2>/dev/null | grep ssid | awk '{print $2}' || echo "$WIFI_SSID")
    fi
    WIFI_DRIVER=$(readlink /sys/class/net/${WIFI_IF}/device/driver 2>/dev/null | xargs basename 2>/dev/null || echo "N/A")
fi

# NIC 硬體資訊（lspci）
NIC_LSPCI=$(lspci 2>/dev/null | grep -iE "Ethernet|Network|Wireless|WiFi|CAN" || echo "N/A")

# 網路統計
NET_STATS=""
for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v "^lo$"); do
    _rx=$(cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null || echo "0")
    _tx=$(cat "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null || echo "0")
    _rx_e=$(cat "/sys/class/net/${iface}/statistics/rx_errors" 2>/dev/null || echo "0")
    _tx_e=$(cat "/sys/class/net/${iface}/statistics/tx_errors" 2>/dev/null || echo "0")
    _rx_h=$(bytes_to_human $_rx)
    _tx_h=$(bytes_to_human $_tx)
    NET_STATS+="| \`${iface}\` | ${_rx_h} | ${_tx_h} | ${_rx_e} | ${_tx_e} |\n"
done

# ============================================================
# 8. USB 裝置
# ============================================================
log "收集 USB 資訊..."

USB_LIST="N/A"
if has lsusb; then
    USB_LIST=$(lsusb 2>/dev/null || echo "N/A")
fi

USB_TREE="N/A"
if has lsusb; then
    USB_TREE=$(lsusb -t 2>/dev/null || echo "N/A")
fi

# ============================================================
# 9. PCI 裝置
# ============================================================
log "收集 PCI 裝置資訊..."

PCI_LIST="N/A"
if has lspci; then
    PCI_LIST=$(lspci 2>/dev/null || echo "N/A")
fi

# ============================================================
# 10. 感測器 & 溫度
# ============================================================
log "收集溫度 & 感測器資訊..."

SENSOR_DATA="N/A"
if has sensors; then
    SENSOR_DATA=$(sensors 2>/dev/null || echo "N/A")
fi

# Thermal zones
THERMAL_TABLE=""
for zone in /sys/class/thermal/thermal_zone*/; do
    _idx=$(basename "$zone" | tr -d 'thermal_zone')
    _type=$(cat "${zone}type" 2>/dev/null || echo "unknown")
    _temp=$(cat "${zone}temp" 2>/dev/null || echo "")
    if [[ -n "$_temp" && "$_temp" != "0" ]]; then
        _temp_c=$(echo "scale=1; $_temp/1000" | bc 2>/dev/null || echo "N/A")
        THERMAL_TABLE+="| ${_idx} | ${_type} | ${_temp_c}°C |\n"
    fi
done
[[ -z "$THERMAL_TABLE" ]] && THERMAL_TABLE="| — | N/A | N/A |\n"

# Raspberry Pi 溫度
if [[ "$PLATFORM" == "rpi" ]] && has vcgencmd; then
    RPI_TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "N/A")
    RPI_VOLT=$(vcgencmd measure_volts core 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "N/A")
    RPI_THROTTLE=$(vcgencmd get_throttled 2>/dev/null || echo "N/A")
    RPI_MEM=$(vcgencmd get_mem gpu 2>/dev/null || echo "N/A")
fi

# ============================================================
# 11. 平台特有資訊
# ============================================================
log "收集平台特有資訊..."

PLATFORM_SECTION=""

# --- Jetson ---
if [[ "$PLATFORM" == "jetson" ]]; then
    NV_TEGRA=$(cat /etc/nv_tegra_release 2>/dev/null || echo "N/A")
    L4T_FULL=$(echo "$NV_TEGRA" | grep -oP 'R\d+' | head -1 | tr -d 'R')
    L4T_REV=$(echo "$NV_TEGRA" | grep -oP 'REVISION: [\d.]+' | awk '{print $2}')
    JETPACK_VER=$(dpkg -l nvidia-jetpack 2>/dev/null | awk '/^ii/{print $3}' | head -1 || echo "N/A")
    POWER_MODE=$(nvpmodel -q 2>/dev/null | grep "NV Power Mode" | sed 's/NV Power Mode: //' | xargs || echo "N/A")
    TEGRA_SNAP=$(timeout 4 tegrastats 2>/dev/null | head -1 || echo "N/A")
    DLA_VER=$(dpkg -l nvidia-l4t-dla-compiler 2>/dev/null | awk '/^ii/{print $3}' | head -1 || echo "N/A")

    PLATFORM_SECTION=$(cat <<JSEC
## 12. Jetson 平台詳情

| 項目 | 數值 |
|------|------|
| JetPack 版本 | \`${JETPACK_VER}\` |
| L4T 版本 | \`R${L4T_FULL}.${L4T_REV}\` |
| 電源模式 | \`${POWER_MODE}\` |
| GPU 架構 | ${GPU_ARCH} |
| Compute Capability | **${GPU_CC}** |
| CUDA 核心 | ${GPU_CUDA_CORES} |
| DLA 數量 | ${GPU_DLA} |
| DLA Compiler | \`${DLA_VER}\` |

### tegrastats 即時快照

\`\`\`
${TEGRA_SNAP}
\`\`\`

### AI 函式庫

| 函式庫 | 版本 | 狀態 |
|--------|------|------|
| CUDA | \`${CUDA_VERSION}\` | $(ckmark "$CUDA_VERSION") |
| NVCC | \`${NVCC_PATH}\` | $(ckmark "$NVCC_PATH") |
| cuDNN | \`${CUDNN_VER}\` | $(ckmark "$CUDNN_VER") |
| TensorRT | \`${TRT_VER}\` | $(ckmark "$TRT_VER") |
| VPI | \`${VPI_VER}\` | $(ckmark "$VPI_VER") |
| OpenCV | \`${OPENCV_VER}\` (CUDA: ${OPENCV_CUDA}) | $(ckmark "$OPENCV_VER") |
| PyTorch | \`${PYTORCH_VER}\` | $(ckmark "$PYTORCH_VER") |
| ONNX Runtime | \`${ONNXRT_VER}\` | $(ckmark "$ONNXRT_VER") |
| TensorFlow | \`${TF_VER}\` | $(ckmark "$TF_VER") |

JSEC
)
fi

# --- Raspberry Pi ---
if [[ "$PLATFORM" == "rpi" ]]; then
    RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "N/A")
    RPI_REVISION=$(cat /proc/cpuinfo 2>/dev/null | grep "Revision" | awk '{print $3}' || echo "N/A")
    RPI_SERIAL=$(cat /proc/cpuinfo 2>/dev/null | grep "Serial" | awk '{print $3}' || echo "N/A")
    PLATFORM_SECTION=$(cat <<RSEC
## 12. Raspberry Pi 詳情

| 項目 | 數值 |
|------|------|
| 型號 | ${RPI_MODEL} |
| 硬體版本 | \`${RPI_REVISION}\` |
| 序號 | \`${RPI_SERIAL}\` |
| SoC 溫度 | ${RPI_TEMP:-N/A}°C |
| Core 電壓 | ${RPI_VOLT:-N/A}V |
| 節流狀態 | \`${RPI_THROTTLE:-N/A}\` |
| GPU 記憶體 | ${RPI_MEM:-N/A} |

RSEC
)
fi

# ============================================================
# 12. 系統服務 & 容器
# ============================================================
log "收集系統服務資訊..."

DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "N/A")
DOCKER_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
SYSTEMD_FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l || echo "N/A")

# ============================================================
# 13. Python 環境
# ============================================================
log "收集 Python 環境..."

PY3_VER=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "N/A")
PY3_PATH=$(which python3 2>/dev/null || echo "N/A")
PIP3_VER=$(pip3 --version 2>/dev/null | awk '{print $2}' || echo "N/A")
VENV_ACTIVE="${VIRTUAL_ENV:-(無)}"

# ============================================================
# 產生 Markdown 報告
# ============================================================
log "產生 Markdown 報告 → ${OUTPUT_FILE}"

cat > "$OUTPUT_FILE" << MDEOF
# Linux 系統硬體報告 (CPU-Z 類型)

> **主機名稱：** \`${HOSTNAME_FULL}\`
> **產生時間：** ${DATE_READABLE}
> **平台類型：** ${PLATFORM} | **架構：** ${ARCH}

---

## 0. 裝置唯一識別碼

| 識別項目 | 數值 |
|----------|------|
| 主機名稱 | \`${HOSTNAME_STR}\` |
| 序號 (Serial Number) | \`${SERIAL_NUMBER}\` |
| 序號來源 | $(if [[ -n "$SN_DT" ]] && is_valid_sn "$SN_DT"; then echo "device-tree"; elif [[ -n "$SN_DMI" ]] && is_valid_sn "$SN_DMI"; then echo "DMI/SMBIOS product_serial"; elif [[ -n "$SN_BOARD" ]] && is_valid_sn "$SN_BOARD"; then echo "DMI/SMBIOS board_serial"; elif [[ -n "$SN_RPI" ]] && is_valid_sn "$SN_RPI"; then echo "Raspberry Pi cpuinfo"; elif [[ -n "$SN_NVME" ]] && is_valid_sn "$SN_NVME"; then echo "NVMe 磁碟序號"; else echo "machine-id (備援)"; fi) |
| NVMe 磁碟序號 | \`${SN_NVME:-N/A}\` |
| MAC 位址 (eth0) | \`$(echo "$SN_MAC" | sed 's/../&:/g' | sed 's/:$//')\` |
| Machine ID | \`$(cat /etc/machine-id 2>/dev/null || echo "N/A")\` |
| 報告檔名識別碼 | \`${HOSTNAME_STR}_${SN_SHORT}_${DATE_STR}\` |

---

## 1. 作業系統 & 核心

| 項目 | 數值 |
|------|------|
| 作業系統 | **${OS_NAME}** |
| 核心版本 | \`${KERNEL_VER}\` |
| 系統架構 | \`${ARCH}\` |
| 主機名稱 | \`${HOSTNAME_FULL}\` |
| 主要 IP | \`${HOSTNAME_IP}\` |
| 上線時間 | ${UPTIME_STR} |
| 開機時間 | ${BOOT_TIME} |
| 時區 | ${TIMEZONE} |
| 語系 | ${LOCALE} |

---

## 2. CPU

### 2.1 基本資訊

| 項目 | 數值 |
|------|------|
| 型號 | **${CPU_MODEL}** |
| 廠商 | ${CPU_VENDOR} |
| 架構 | ${ARCH} |
| 邏輯核心數 | **${CPU_CORES_LOGICAL}** |
| 實體核心數 | ${CPU_CORES_PHYSICAL} |
| Socket 數 | ${CPU_SOCKETS} |
| 每核執行緒 | ${CPU_THREADS_PER_CORE} |
| 虛擬化 | ${CPU_VIRT} |
| CPU Family | ${CPU_FAMILY} |
| Stepping | ${CPU_STEPPING} |
| BogoMIPS | ${CPU_BOGOMIPS} |

### 2.2 頻率

| 項目 | 數值 |
|------|------|
| 最高頻率 | **${CPU_MAX_MHZ} MHz** |
| 最低頻率 | ${CPU_MIN_MHZ} MHz |
| 當前頻率 (cpu0) | ${CPU_CUR_MHZ} MHz |
| 調速器 | \`${CPU_GOVERNOR}\` |
| 溫度 | ${CPU_TEMP} |

各核心頻率：
\`\`\`
${CPU_ALL_FREQS}
\`\`\`

### 2.3 快取

| 層級 | 大小 |
|------|------|
| L1 Data | ${CPU_L1D} |
| L1 Instruction | ${CPU_L1I} |
| L2 | ${CPU_L2} |
| L3 | ${CPU_L3} |

### 2.4 指令集擴充

\`\`\`
${CPU_FLAGS}
\`\`\`

---

## 3. 記憶體

### 3.1 使用狀況

| 項目 | 數值 |
|------|------|
| 總記憶體 | **${MEM_TOTAL_H}** |
| 已使用 | ${MEM_USED_H} (${MEM_USED_PCT}%) |
| 可用 | ${MEM_AVAIL_H} |
| Buffers | ${MEM_BUFFERS_H} |
| Cached | ${MEM_CACHED_H} |
| Swap 總量 | ${SWAP_TOTAL_H} |
| Dirty Pages | $(kb_to_human $MEM_DIRTY_KB) |

### 3.2 實體記憶體規格

| 項目 | 數值 |
|------|------|
| 類型 | ${MEM_TYPE} |
| 速度 | ${MEM_SPEED} |
| 外形規格 | ${MEM_FORM} |
| DIMM 槽數 | ${MEM_SLOTS} |
| HugePage 大小 | ${HUGEPAGE_SIZE} |
| HugePage 總數 | ${HUGEPAGE_TOTAL} |

---

## 4. 磁碟 & 分區

### 4.1 實體磁碟裝置

\`\`\`
${DISK_LIST}
\`\`\`

### 4.2 分區使用率（掛載點）

\`\`\`
$(df -h 2>/dev/null | grep -v "^tmpfs\|^devtmpfs\|^udev" | column -t || echo "N/A")
\`\`\`

完整分區列表（含 fstype）：

\`\`\`
$(df -hT 2>/dev/null | grep -v "^tmpfs\|^devtmpfs\|^udev\|^none" | column -t || echo "N/A")
\`\`\`

### 4.3 分區樹狀結構

\`\`\`
${LSBLK_TREE}
\`\`\`

### 4.4 inode 使用率

\`\`\`
$(df -ih 2>/dev/null | grep -v "^tmpfs\|^devtmpfs\|^udev" | column -t || echo "N/A")
\`\`\`

### 4.5 磁碟 SMART 健康狀態

\`\`\`
${SMART_INFO}
\`\`\`

---

## 5. GPU

### 5.1 GPU 概覽

| 項目 | 數值 |
|------|------|
| 廠商 | **${GPU_VENDOR}** |
| 型號 | **${GPU_NAME}** |
| 驅動版本 | \`${GPU_DRIVER}\` |
| 顯示記憶體 | ${GPU_MEM} |
| GPU 使用率 | ${GPU_UTIL} |
| GPU 溫度 | ${GPU_TEMP} |
| GPU 功耗 | ${GPU_PWR} |
| 最高頻率 | ${GPU_MAX_MHZ} MHz |
| 當前頻率 | ${GPU_CUR_MHZ} MHz |
| 可用頻率 (MHz) | ${GPU_AVAIL_MHZ} |

### 5.2 PCI 顯示裝置列表

\`\`\`
${GPU_LSPCI}
\`\`\`

---

## 6. 網路

### 6.1 網路介面

| 介面 | 類型 | MAC 位址 | IPv4 | IPv6 | 狀態 | 速度 | MTU |
|------|------|----------|------|------|------|------|-----|
$(echo -e "$NET_TABLE")

### 6.2 路由 & DNS

| 項目 | 數值 |
|------|------|
| 預設閘道 | \`${DEFAULT_GW}\` |
| 預設介面 | \`${DEFAULT_IF}\` |
| DNS 伺服器 | \`${DNS_SERVERS}\` |
| 網域 | \`${DOMAIN}\` |

### 6.3 WiFi 資訊

| 項目 | 數值 |
|------|------|
| 介面 | \`${WIFI_IF:-N/A}\` |
| SSID | \`${WIFI_SSID}\` |
| 訊號強度 | ${WIFI_SIGNAL} |
| 頻道 | ${WIFI_CHANNEL} |
| 驅動 | \`${WIFI_DRIVER}\` |

### 6.4 網路卡硬體 (PCI)

\`\`\`
${NIC_LSPCI}
\`\`\`

### 6.5 網路流量統計

| 介面 | RX 總量 | TX 總量 | RX 錯誤 | TX 錯誤 |
|------|---------|---------|---------|---------|
$(echo -e "$NET_STATS")

---

## 7. USB 裝置

### 7.1 USB 裝置列表

\`\`\`
${USB_LIST}
\`\`\`

### 7.2 USB 拓撲樹

\`\`\`
${USB_TREE}
\`\`\`

---

## 8. PCI 裝置

\`\`\`
${PCI_LIST}
\`\`\`

---

## 9. 溫度 & 感測器

### 9.1 Thermal Zones

| Zone | 類型 | 溫度 |
|------|------|------|
$(echo -e "$THERMAL_TABLE")

### 9.2 sensors 輸出

\`\`\`
${SENSOR_DATA}
\`\`\`

---

## 10. 系統服務 & 容器

| 項目 | 數值 |
|------|------|
| Docker 版本 | $(ckmark "$DOCKER_VER") |
| 運行中容器數 | ${DOCKER_RUNNING} |
| Systemd 失敗服務 | ${SYSTEMD_FAILED} 個 |

---

## 11. Python 環境

| 項目 | 數值 |
|------|------|
| Python 3 | \`${PY3_VER}\` (\`${PY3_PATH}\`) |
| pip3 | \`${PIP3_VER}\` |
| 虛擬環境 | ${VENV_ACTIVE} |
| PyTorch | $(ckmark "$PYTORCH_VER") |
| PyTorch CUDA | \`${PYTORCH_CUDA}\` |
| PyTorch GPU | ${PYTORCH_GPU} (${PYTORCH_GPU_NAME}) |
| OpenCV | $(ckmark "$OPENCV_VER") |
| ONNX Runtime | $(ckmark "$ONNXRT_VER") |
| TensorFlow | $(ckmark "$TF_VER") |

---

${PLATFORM_SECTION}

---

*由 \`sysreport.sh\` 自動產生 — ${DATE_READABLE} — 主機：${HOSTNAME_FULL}*
MDEOF

ok "報告產生完成：${OUTPUT_FILE}"
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  系統摘要${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "  主機：    ${HOSTNAME_FULL} (${HOSTNAME_IP})"
echo -e "  OS：      ${OS_NAME}"
echo -e "  CPU：     ${CPU_MODEL} × ${CPU_CORES_LOGICAL} 核 @ ${CPU_MAX_MHZ}MHz"
echo -e "  記憶體：  ${MEM_TOTAL_H} (已用 ${MEM_USED_PCT}%)"
echo -e "  GPU：     ${GPU_VENDOR} ${GPU_NAME}"
if [[ "$PLATFORM" == "jetson" ]]; then
    echo -e "  CUDA：    ${CUDA_VERSION}  |  TensorRT：${TRT_VER}  |  cuDNN：${CUDNN_VER}"
fi
echo -e "  報告：    ${OUTPUT_FILE}"
echo -e "${BOLD}========================================${NC}"
