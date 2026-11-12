#!/bin/bash
#
# Module: System Information Collection
# システム情報収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [10_system_info] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SYS_DIR="${OUTPUT_DIR}/system"
ensure_dir "${SYS_DIR}" || { log_error "[10_system_info] Failed to create ${SYS_DIR}"; exit 1; }

log_info "[10_system_info] Starting system information collection"

# システム基本情報
uname -a > "${SYS_DIR}/uname.txt" 2>&1
hostname > "${SYS_DIR}/hostname.txt" 2>&1
date > "${SYS_DIR}/collection_time.txt" 2>&1
uptime > "${SYS_DIR}/uptime.txt" 2>&1

# OS情報
safe_copy "/etc/os-release" "${SYS_DIR}/"
safe_copy "/etc/lsb-release" "${SYS_DIR}/"
safe_copy "/etc/issue" "${SYS_DIR}/"

# カーネル情報
cat /proc/version > "${SYS_DIR}/kernel_version.txt" 2>&1
cat /proc/cmdline > "${SYS_DIR}/kernel_cmdline.txt" 2>&1

# ハードウェア情報
lscpu > "${SYS_DIR}/cpu_info.txt" 2>&1 || true
free -h > "${SYS_DIR}/memory_info.txt" 2>&1
df -h > "${SYS_DIR}/disk_usage.txt" 2>&1
lsblk > "${SYS_DIR}/block_devices.txt" 2>&1 || true

# ネットワークインターフェース
ip addr show > "${SYS_DIR}/ip_addresses.txt" 2>&1 || ifconfig > "${SYS_DIR}/ip_addresses.txt" 2>&1
ip route show > "${SYS_DIR}/routing_table.txt" 2>&1 || route -n > "${SYS_DIR}/routing_table.txt" 2>&1

# タイムゾーン
timedatectl > "${SYS_DIR}/timezone.txt" 2>&1 || date > "${SYS_DIR}/timezone.txt" 2>&1

# 環境変数（収集プロセス自身のもの。sudo 元のシェルのトークン類が入り得るため値を伏せる）
env 2>&1 | redact_env > "${SYS_DIR}/environment_variables.txt"

log_success "[10_system_info] System information collection completed"
exit 0
