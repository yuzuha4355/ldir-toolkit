#!/bin/bash
#######################################################################
# LDIR-Collector v0.2.0 - Enhanced Version
# Linux Digital Incident Response - Collector
# 
# カスタマイズ環境・特殊ディストリビューション対応版
#######################################################################

set -euo pipefail

# バージョン
VERSION="0.2.0"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログ関数（基本）
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

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
if [ $# -ne 1 ]; then
    usage
fi

OUTPUT_BASE="$1"

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# 出力ディレクトリ作成
HOSTNAME=$(hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
COLLECTION_DIR="${OUTPUT_BASE}/${HOSTNAME}_${TIMESTAMP}"

mkdir -p "${COLLECTION_DIR}"
export COLLECTION_DIR

log_info "LDIR-Collector Version: ${VERSION}"
log_info "Output directory: ${COLLECTION_DIR}"

# スクリプトディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ライブラリ読み込み
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    log_error "common.sh not found"
    exit 1
fi

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

# メタデータディレクトリ作成
METADATA_DIR="${COLLECTION_DIR}/metadata"
mkdir -p "${METADATA_DIR}"

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
        
        if bash "${module_path}"; then
            log_success "Module ${module} completed"
            echo "✓ ${module}" >> "${MANIFEST}"
            ((SUCCESS_COUNT++))
        else
            log_error "Module ${module} failed"
            echo "✗ ${module}" >> "${MANIFEST}"
            ((FAIL_COUNT++))
        fi
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
find "${COLLECTION_DIR}" -type f ! -path "${HASH_FILE}" -exec sha256sum {} \; > "${HASH_FILE}" 2>/dev/null || true

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
