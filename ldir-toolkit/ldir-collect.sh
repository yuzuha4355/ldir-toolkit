#!/bin/bash
#######################################################################
# LDIR-Collector
# Linux Digital Incident Response - Collector
#
# カスタマイズ環境・特殊ディストリビューション対応版
#######################################################################

set -euo pipefail

# predictable PATH (cron/sudo/non-interactive safety)
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

# バージョン
# NOTE: 変数名を VERSION にしないこと。/etc/os-release も VERSION を定義しており、
#       source されると上書きされる（v0.2.1 でマニフェストに OS のバージョンが
#       記録されていた原因）。
LDIR_VERSION="0.3.2"
export LDIR_VERSION

# スクリプトディレクトリ取得（先に確定）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通ライブラリ読み込み（ログ関数のため早めに）
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    # OUTPUT_DIR が未設定でも標準出力ログは出る
    OUTPUT_DIR=""
    export OUTPUT_DIR
    # shellcheck source=lib/common.sh
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "[ERROR] common.sh not found" >&2
    exit 1
fi

# 使い方表示
usage() {
    cat << EOF
Usage: $0 [options] [output_directory]

LDIR-Collector v${LDIR_VERSION}
Linux forensic artifact collector for incident response.

Arguments:
  output_directory    Base directory for collected data
                      (default: /tmp/ldir_output)

Options:
  -m, --mode MODE     fast (default) or full. Same as LDIR_MODE.
  -a, --archive       Pack the result into <host>_<timestamp>.tar.gz
                      and write a .sha256 next to it. Same as LDIR_ARCHIVE=1.
      --no-redact     Keep secret-looking environment variable values as-is.
                      Same as LDIR_REDACT_SECRETS=0. Default is to mask them.
  -l, --list-modules  List collection modules and exit
  -V, --version       Print version and exit
  -h, --help          Show this help and exit

Environment:
  LDIR_MODE                    fast | full
  LDIR_ENABLE_WEB              1/0  browser artifacts   (default: 0 fast, 1 full)
  LDIR_ENABLE_CLOUD_METADATA   1/0  cloud metadata API  (default: 0 fast, 1 full)
  LDIR_ARCHIVE                 1/0  create tar.gz       (default: 0)
  LDIR_REDACT_SECRETS          1/0  mask token/password values in collected
                                    environment variables (default: 1)
  LDIR_FAST_SCAN_BUDGET        seconds allowed for the permission search in
                                    fast mode (default: 60)
  LDIR_VERBOSE                 1/0  also print "not present" notices

Examples:
  sudo $0 /mnt/usb/evidence
  sudo $0 --mode full --archive /mnt/usb/evidence

Verify a collection afterwards:
  cd <output>/<host>_<timestamp> && sha256sum -c metadata/file_hashes.txt

Exit status:
  0  all modules completed
  1  usage or setup error (nothing collected)
  2  collection finished, but at least one module failed
EOF
}

list_modules() {
    local m
    for m in "${SCRIPT_DIR}/modules"/[0-9][0-9]_*.sh; do
        [[ -f "$m" ]] && basename "$m"
    done
}

# Mode control (fast forensic vs full)
# - fast: keep runtime/payload small for first response
# - full: exhaustive scans (may be slow & large)
LDIR_MODE="${LDIR_MODE:-fast}"
LDIR_ARCHIVE="${LDIR_ARCHIVE:-0}"
LDIR_REDACT_SECRETS="${LDIR_REDACT_SECRETS:-1}"
OUTPUT_BASE=""

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -V|--version)
            echo "LDIR-Collector ${LDIR_VERSION}"
            exit 0
            ;;
        -l|--list-modules)
            list_modules
            exit 0
            ;;
        -m|--mode)
            [[ $# -ge 2 ]] || { log_error "$1 requires an argument (fast|full)"; exit 1; }
            LDIR_MODE="$2"
            shift 2
            ;;
        --mode=*)
            LDIR_MODE="${1#*=}"
            shift
            ;;
        -a|--archive)
            LDIR_ARCHIVE=1
            shift
            ;;
        --no-redact)
            LDIR_REDACT_SECRETS=0
            shift
            ;;
        --)
            shift
            [[ $# -eq 0 ]] || { OUTPUT_BASE="$1"; shift; }
            ;;
        -*)
            log_error "Unknown option: $1"
            usage >&2
            exit 1
            ;;
        *)
            if [[ -n "${OUTPUT_BASE}" ]]; then
                log_error "Unexpected extra argument: $1"
                exit 1
            fi
            OUTPUT_BASE="$1"
            shift
            ;;
    esac
done

: "${OUTPUT_BASE:=/tmp/ldir_output}"

case "${LDIR_MODE}" in
    fast|full) ;;
    *)
        log_error "Invalid mode: ${LDIR_MODE} (expected: fast or full)"
        exit 1
        ;;
esac
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
export LDIR_ENABLE_WEB LDIR_ENABLE_CLOUD_METADATA LDIR_REDACT_SECRETS

# root権限チェック
if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# ホスト名（最小構成では hostname コマンドが無いことがある）
get_hostname() {
    local h=""
    h="$(hostname 2>/dev/null)" || h=""
    [[ -n "$h" ]] || h="$(cat /proc/sys/kernel/hostname 2>/dev/null)" || h=""
    [[ -n "$h" ]] || h="$(uname -n 2>/dev/null)" || h=""
    # パスに使うので安全な文字だけ残す
    h="${h//[^A-Za-z0-9._-]/_}"
    echo "${h:-unknown-host}"
}

# 出力ディレクトリ作成
umask 077
HOST_NAME="$(get_hostname)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
COLLECTION_NAME="${HOST_NAME}_${TIMESTAMP}"

mkdir -p "${OUTPUT_BASE}"
# 絶対パスに正規化（モジュール側の find 除外指定が確実に一致するように）
OUTPUT_BASE="$(cd "${OUTPUT_BASE}" && pwd -P)"
COLLECTION_DIR="${OUTPUT_BASE}/${COLLECTION_NAME}"

mkdir -p "${COLLECTION_DIR}"
export COLLECTION_DIR

# common.sh のログは OUTPUT_DIR/metadata/collection.log を見に行くので設定
OUTPUT_DIR="${COLLECTION_DIR}"
export OUTPUT_DIR

# メタデータディレクトリ作成
METADATA_DIR="${COLLECTION_DIR}/metadata"
mkdir -p "${METADATA_DIR}/modules"

log_info "LDIR-Collector Version: ${LDIR_VERSION}"
log_info "Mode: ${LDIR_MODE} (web=${LDIR_ENABLE_WEB}, cloud_metadata=${LDIR_ENABLE_CLOUD_METADATA}, redact_secrets=${LDIR_REDACT_SECRETS})"
log_info "Output directory: ${COLLECTION_DIR}"

# 環境検出ライブラリ読み込み
if [[ -f "${SCRIPT_DIR}/lib/detect_distro_advanced.sh" ]]; then
    # shellcheck source=lib/detect_distro_advanced.sh
    source "${SCRIPT_DIR}/lib/detect_distro_advanced.sh"
    detect_all
else
    log_error "lib/detect_distro_advanced.sh not found"
    exit 1
fi

# Manifest作成開始
MANIFEST="${METADATA_DIR}/manifest.txt"
START_EPOCH=$(date +%s)
cat > "${MANIFEST}" << EOF
=== LDIR-Collector Collection Manifest ===
Collector Version: ${LDIR_VERSION}
Collection Mode: ${LDIR_MODE}
Secret Redaction: ${LDIR_REDACT_SECRETS}
Collection Time: $(date '+%Y-%m-%d %H:%M:%S %z')
Collection Time (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Hostname: ${HOST_NAME}
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
# modules/NN_name.sh を番号順に自動検出する（追加時にこのファイルの編集は不要）
log_info "Starting collection..."
MODULES=()
while IFS= read -r module; do
    MODULES+=("$module")
done < <(list_modules)

if [[ ${#MODULES[@]} -eq 0 ]]; then
    log_error "No modules found in ${SCRIPT_DIR}/modules"
    exit 1
fi

count_level() {
    # grep はヒット0で exit=1 になるため awk で数える
    awk -v p="^\\\\[$1\\\\]" '$0 ~ p {c++} END{print c+0}' "$2" 2>/dev/null || echo 0
}

SUCCESS_COUNT=0
FAIL_COUNT=0

for module in "${MODULES[@]}"; do
    module_path="${SCRIPT_DIR}/modules/${module}"
    log_info "Executing module: ${module}"

    # モジュールログを分離（"成功に見える失敗"を潰す）
    MODULE_LOG="${METADATA_DIR}/modules/${module}.log"
    : > "${MODULE_LOG}" 2>/dev/null || true

    module_start=$(date +%s)
    module_rc=0
    LDIR_MODULE="${module}" LDIR_MODULE_LOG="${MODULE_LOG}" \
        bash "${module_path}" "${COLLECTION_DIR}" || module_rc=$?
    module_secs=$(( $(date +%s) - module_start ))

    WARN_COUNT=$(count_level WARN "${MODULE_LOG}")
    ERROR_COUNT=$(count_level ERROR "${MODULE_LOG}")
    detail="warn=${WARN_COUNT}, error=${ERROR_COUNT}, ${module_secs}s"

    if [[ ${module_rc} -eq 0 ]]; then
        log_success "Module ${module} completed (${detail})"
        echo "✓ ${module} (${detail})" >> "${MANIFEST}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "Module ${module} failed (exit=${module_rc}, ${detail})"
        echo "✗ ${module} (exit=${module_rc}, ${detail})" >> "${MANIFEST}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# 収集統計
# 統計が取れないことを理由に、ハッシュ生成の手前で止まらないようにする
TOTAL_FILES=$(find "${COLLECTION_DIR}" -type f 2>/dev/null | wc -l) || TOTAL_FILES="unknown"
TOTAL_SIZE=$(du -sh "${COLLECTION_DIR}" 2>/dev/null | awk '{print $1}') || TOTAL_SIZE="unknown"

cat >> "${MANIFEST}" << EOF

=== Collection Statistics ===
Total Files: ${TOTAL_FILES}
Total Size: ${TOTAL_SIZE}
Successful Modules: ${SUCCESS_COUNT}
Failed Modules: ${FAIL_COUNT}
Elapsed Seconds: $(( $(date +%s) - START_EPOCH ))
Collection End Time: $(date '+%Y-%m-%d %H:%M:%S %z')
EOF

log_info "Collection finished: ${SUCCESS_COUNT} succeeded, ${FAIL_COUNT} failed"
log_info "Generating SHA256 hashes..."

# ---- ここから先は collection.log に書かない ----
# ハッシュ生成後にログへ追記すると、collection.log のハッシュが合わなくなる。
OUTPUT_DIR=""

# SHA256ハッシュ生成
# - 相対パスで記録する（別ホスト・別パスへ移しても検証できる）
# - 検証: cd <collection_dir> && sha256sum -c metadata/file_hashes.txt
HASH_FILE="${METADATA_DIR}/file_hashes.txt"
HASH_OK=1
if have_cmd sha256sum; then
    (
        cd "${COLLECTION_DIR}"
        find . -type f ! -path ./metadata/file_hashes.txt -print0 \
            | sort -z \
            | xargs -0 sha256sum > metadata/file_hashes.txt
    ) || HASH_OK=0
else
    HASH_OK=0
fi
if [[ ${HASH_OK} -ne 1 ]]; then
    log_error "SHA256 hash generation failed or incomplete: ${HASH_FILE}"
fi

# アーカイブ作成（任意）
ARCHIVE_PATH=""
ARCHIVE_OK=1
if [[ "${LDIR_ARCHIVE}" = "1" ]]; then
    ARCHIVE_PATH="${OUTPUT_BASE}/${COLLECTION_NAME}.tar.gz"
    log_info "Creating archive: ${ARCHIVE_PATH}"
    if tar -czf "${ARCHIVE_PATH}" -C "${OUTPUT_BASE}" "${COLLECTION_NAME}"; then
        ( cd "${OUTPUT_BASE}" && sha256sum "${COLLECTION_NAME}.tar.gz" > "${COLLECTION_NAME}.tar.gz.sha256" ) || true
    else
        log_error "Archive creation failed"
        ARCHIVE_PATH=""
        ARCHIVE_OK=0
    fi
fi

log_success "Collection complete!"

# サマリー表示
echo ""
echo "=== Collection Summary ==="
echo "Output:             ${COLLECTION_DIR}"
echo "Manifest:           ${MANIFEST}"
echo "Hashes:             ${HASH_FILE}"
if [[ ${HASH_OK} -eq 1 ]]; then
    # 証拠保全記録（chain of custody）に控える値
    echo "Hash list SHA256:   $(sha256sum "${HASH_FILE}" | awk '{print $1}')"
fi
if [[ -n "${ARCHIVE_PATH}" ]]; then
    echo "Archive:            ${ARCHIVE_PATH}"
    echo "Archive SHA256:     $(awk '{print $1}' "${ARCHIVE_PATH}.sha256" 2>/dev/null || echo unknown)"
fi
echo "Total Files:        ${TOTAL_FILES}"
echo "Total Size:         ${TOTAL_SIZE}"
echo "Successful Modules: ${SUCCESS_COUNT}/${#MODULES[@]}"
echo "Failed Modules:     ${FAIL_COUNT}/${#MODULES[@]}"
echo ""

if [[ ${FAIL_COUNT} -gt 0 || ${HASH_OK} -ne 1 || ${ARCHIVE_OK} -ne 1 ]]; then
    exit 2
fi
exit 0
