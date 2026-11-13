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
capture "${SYS_DIR}/uname.txt" uname -a
capture "${SYS_DIR}/hostname.txt" hostname
capture "${SYS_DIR}/collection_time.txt" date
capture "${SYS_DIR}/uptime.txt" uptime

# OS情報
safe_copy "/etc/os-release" "${SYS_DIR}/"
safe_copy "/etc/lsb-release" "${SYS_DIR}/"
safe_copy "/etc/issue" "${SYS_DIR}/"

# カーネル情報
capture "${SYS_DIR}/kernel_version.txt" cat /proc/version
capture "${SYS_DIR}/kernel_cmdline.txt" cat /proc/cmdline

# ハードウェア情報
lscpu > "${SYS_DIR}/cpu_info.txt" 2>&1 || true
capture "${SYS_DIR}/memory_info.txt" free -h
capture "${SYS_DIR}/disk_usage.txt" df -h
lsblk > "${SYS_DIR}/block_devices.txt" 2>&1 || true

# ネットワークインターフェース
capture_try "${SYS_DIR}/ip_addresses.txt" ip addr show || capture "${SYS_DIR}/ip_addresses.txt" ifconfig
capture_try "${SYS_DIR}/routing_table.txt" ip route show || capture "${SYS_DIR}/routing_table.txt" route -n

# タイムゾーン
capture_try "${SYS_DIR}/timezone.txt" timedatectl || capture "${SYS_DIR}/timezone.txt" date

# 環境変数（収集プロセス自身のもの。sudo 元のシェルのトークン類が入り得るため値を伏せる）
env 2>&1 | redact_env > "${SYS_DIR}/environment_variables.txt"

log_success "[10_system_info] System information collection completed"
exit 0
