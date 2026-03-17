#!/bin/bash
#######################################################################
# LDIR-Collector v0.2.1 - Enhanced Version
# Linux Digital Incident Response - Collector
# 
# カスタマイズ環境・特殊ディストリビューション対応版
#######################################################################

set -euo pipefail

# predictable PATH (cron/sudo/non-interactive safety)
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

# バージョン
VERSION="0.2.1"

# NOTE:
# ログ関数や safe_copy 等は lib/common.sh を使用

# スクリプトディレクトリ取得（先に確定）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通ライブラリ読み込み（ログ関数のため早めに）
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    # OUTPUT_DIR が未設定でも標準出力ログは出る
    OUTPUT_DIR=""
    export OUTPUT_DIR
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "[ERROR] common.sh not found" >&2
    exit 1
fi

# 使い方表示
usage() {
    cat << EOF
Usage: $0 <output_directory>

LDIR-Collector v${VERSION} - Enhanced Version
カスタマイズ環境・特殊ディストリビューション対応版

Arguments:
  output_directory    Output directory for collected data

Example:
  sudo $0 /tmp/ldir_output

Supported Environments:
  - Standard distributions (Ubuntu, Debian, RHEL, CentOS, Rocky, Alma, Fedora)
  - Special purpose (Arch, Gentoo, Alpine, openSUSE)
  - Embedded/IoT (Raspberry Pi OS, Armbian)
  - Cloud optimized (Amazon Linux, Oracle Linux, Google Cloud)
  - Custom configurations (non-systemd, minimal systems, SELinux/AppArmor)
  - Container environments (Docker, LXC, systemd-nspawn)

New Features in v0.2.0:
  - Advanced distribution detection
  - Multiple init system support (systemd, OpenRC, runit, s6, SysVinit)
  - Package manager auto-detection (apt, dnf, pacman, zypper, apk, emerge)
  - Cloud metadata collection (AWS, Azure, GCP, Oracle, DigitalOcean, Alibaba)
  - SELinux/AppArmor information gathering
  - Container environment detection
  - ARM/embedded device support
  - Custom path detection

EOF
    exit 1
}

# 引数チェック
if [[ ${#} -ge 1 && ( "$1" = "-h" || "$1" = "--help" ) ]]; then
    usage
fi

# output base (default)
if [[ ${#} -eq 0 ]]; then
    OUTPUT_BASE="/tmp/ldir_output"
else
    OUTPUT_BASE="$1"
fi

# Mode control (fast forensic vs full)
# - fast: keep runtime/payload small for first response
# - full: exhaustive scans (may be slow & large)
LDIR_MODE="${LDIR_MODE:-fast}"
export LDIR_MODE

# Feature flags (can be overridden by env)
# - fast mode defaults to safer/smaller collection
if [[ "${LDIR_MODE}" = "fast" ]]; then
    : "${LDIR_ENABLE_WEB:=0}"
    : "${LDIR_ENABLE_CLOUD_METADATA:=0}"
else
    : "${LDIR_ENABLE_WEB:=1}"
    : "${LDIR_ENABLE_CLOUD_METADATA:=1}"
fi
export LDIR_ENABLE_WEB LDIR_ENABLE_CLOUD_METADATA


# root権限チェック
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# 出力ディレクトリ作成
umask 077
HOSTNAME=$(hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
COLLECTION_DIR="${OUTPUT_BASE}/${HOSTNAME}_${TIMESTAMP}"

mkdir -p "${COLLECTION_DIR}"
export COLLECTION_DIR

# common.sh のログは OUTPUT_DIR/metadata/collection.log を見に行くので設定
OUTPUT_DIR="${COLLECTION_DIR}"
export OUTPUT_DIR

# メタデータディレクトリ作成
METADATA_DIR="${COLLECTION_DIR}/metadata"
mkdir -p "${METADATA_DIR}"
mkdir -p "${METADATA_DIR}/modules"

log_info "LDIR-Collector Version: ${VERSION}"
log_info "Output directory: ${COLLECTION_DIR}"

# 高度な検出ライブラリ読み込み
if [ -f "${SCRIPT_DIR}/lib/detect_distro_advanced.sh" ]; then
    source "${SCRIPT_DIR}/lib/detect_distro_advanced.sh"
    detect_all
else
    # フォールバック: 基本検出
    if [ -f "${SCRIPT_DIR}/lib/detect_distro.sh" ]; then
        source "${SCRIPT_DIR}/lib/detect_distro.sh"
    else
        log_error "detect_distro.sh not found"
        exit 1
    fi
fi

# メタデータディレクトリは作成済み

# Manifest作成開始
MANIFEST="${METADATA_DIR}/manifest.txt"
cat > "${MANIFEST}" << EOF
=== LDIR-Collector Collection Manifest ===
Collector Version: ${VERSION}
Collection Time: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: ${HOSTNAME}
Output Directory: ${COLLECTION_DIR}

=== System Information ===
Distribution: ${DISTRO_NAME:-Unknown}
Distribution ID: ${DISTRO_ID:-unknown}
Distribution Version: ${DISTRO_VERSION:-Unknown}
Kernel: $(uname -r)
Architecture: ${ARCH_TYPE:-$(uname -m)} (${ARCH:-$(uname -m)})
Init System: ${INIT_SYSTEM:-unknown}
Package Manager: ${PKG_MANAGER:-unknown}
Container Type: ${CONTAINER_TYPE:-none}
SELinux: ${SELINUX_STATUS:-Unknown}
AppArmor: ${APPARMOR_STATUS:-Unknown}

=== Collection Modules ===
EOF

# モジュール実行
log_info "Starting collection..."
MODULES_DIR="${SCRIPT_DIR}/modules"

# モジュールリスト（優先度順）
MODULES=(
    "10_system_info.sh"
    "20_logs.sh"
    "30_auth.sh"
    "40_persistence.sh"
    "50_execution.sh"
    "60_network.sh"
    "70_filesystem.sh"
    "80_web.sh"
    "90_custom_environment.sh"  # 新規: カスタム環境検出
    "91_cloud_metadata.sh"       # 新規: クラウドメタデータ
)

SUCCESS_COUNT=0
FAIL_COUNT=0

for module in "${MODULES[@]}"; do
    module_path="${MODULES_DIR}/${module}"
    
    if [ -f "${module_path}" ]; then
        log_info "Executing module: ${module}"
        
        # モジュールログを分離（"成功に見える失敗"を潰す）
        export LDIR_MODULE="${module}"
        MODULE_LOG="${METADATA_DIR}/modules/${module}.log"
        export LDIR_MODULE_LOG="${MODULE_LOG}"
        : > "${MODULE_LOG}" 2>/dev/null || true

        if bash "${module_path}" "${COLLECTION_DIR}"; then
            # WARN/ERROR の数も集計（grep はヒット0で exit=1 になるため awk で数える）
            WARN_COUNT=$(awk '/^\[WARN\]/{c++} END{print c+0}' "${MODULE_LOG}" 2>/dev/null || echo 0)
            ERROR_COUNT=$(awk '/^\[ERROR\]/{c++} END{print c+0}' "${MODULE_LOG}" 2>/dev/null || echo 0)
            log_success "Module ${module} completed (warn=${WARN_COUNT}, error=${ERROR_COUNT})"
            echo "✓ ${module} (warn=${WARN_COUNT}, error=${ERROR_COUNT})" >> "${MANIFEST}"
            ((SUCCESS_COUNT++)) || true
        else
            WARN_COUNT=$(awk '/^\[WARN\]/{c++} END{print c+0}' "${MODULE_LOG}" 2>/dev/null || echo 0)
            ERROR_COUNT=$(awk '/^\[ERROR\]/{c++} END{print c+0}' "${MODULE_LOG}" 2>/dev/null || echo 0)
            log_error "Module ${module} failed (warn=${WARN_COUNT}, error=${ERROR_COUNT})"
            echo "✗ ${module} (warn=${WARN_COUNT}, error=${ERROR_COUNT})" >> "${MANIFEST}"
            ((FAIL_COUNT++)) || true
        fi

        unset LDIR_MODULE
        unset LDIR_MODULE_LOG
    else
        log_warn "Module ${module} not found, skipping..."
        echo "- ${module} (not found)" >> "${MANIFEST}"
    fi
done

# 収集統計
TOTAL_FILES=$(find "${COLLECTION_DIR}" -type f | wc -l)
TOTAL_SIZE=$(du -sh "${COLLECTION_DIR}" | awk '{print $1}')

cat >> "${MANIFEST}" << EOF

=== Collection Statistics ===
Total Files: ${TOTAL_FILES}
Total Size: ${TOTAL_SIZE}
Successful Modules: ${SUCCESS_COUNT}
Failed Modules: ${FAIL_COUNT}
Collection End Time: $(date '+%Y-%m-%d %H:%M:%S')
EOF

# SHA256ハッシュ生成
log_info "Generating SHA256 hashes..."
HASH_FILE="${METADATA_DIR}/file_hashes.txt"
HASH_TMP="${HASH_FILE}.tmp"
: > "${HASH_TMP}" 2>/dev/null || true
find "${COLLECTION_DIR}" -type f ! -path "${HASH_FILE}" ! -path "${HASH_TMP}" -exec sha256sum {} \; > "${HASH_TMP}" 2>/dev/null || true
mv -f "${HASH_TMP}" "${HASH_FILE}" 2>/dev/null || true

log_success "Collection complete!"
log_info "Output: ${COLLECTION_DIR}"
log_info "Manifest: ${MANIFEST}"
log_info "Hashes: ${HASH_FILE}"

# サマリー表示
echo ""
echo "=== Collection Summary ==="
echo "Total Files: ${TOTAL_FILES}"
echo "Total Size: ${TOTAL_SIZE}"
echo "Successful Modules: ${SUCCESS_COUNT}/${#MODULES[@]}"
echo "Failed Modules: ${FAIL_COUNT}/${#MODULES[@]}"
echo ""

exit 0
