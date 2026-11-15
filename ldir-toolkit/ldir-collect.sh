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
LDIR_VERSION="0.4.1"
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
      --log-days N    Collect logs from the last N days: 30 (default), 60 or 90.
                      Applies to the journal and to log files, rotated ones included.
                      Same as LDIR_LOG_DAYS. full mode without this option: no limit.
      --log-max-mb N  Size cap per log group in MB (default 100; 0 = no cap). Newest
                      files are kept; what does not fit is listed, not collected.
                      Same as LDIR_LOG_MAX_MB. full mode without this option: no cap.
      --journal-max-mb N
                      Size cap for the binary journal files in MB (default 256;
                      0 = no cap). Same as LDIR_JOURNAL_MAX_MB. full mode: no cap.
      --no-redact     Keep secret-looking values (environment variables, VM and
                      hypervisor configuration) as-is.
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
  LDIR_LOG_DAYS                30 | 60 | 90   log period (default: 30 fast, all full)
  LDIR_LOG_MAX_MB              MB per log group, 0 = no cap
                                    (default: 100 fast, no cap full)
  LDIR_JOURNAL_MAX_MB          MB for the binary journal, 0 = no cap
                                    (default: 256 fast, no cap full)
  LDIR_JOURNAL_TEXT_MAX_LINES  entries per journal text export
                                    (default: 5000 x LDIR_LOG_MAX_MB)
  LDIR_USER_FILE_MAX_MB        size cap for one file from a home directory
                                    (default: 100; 0 = no cap)
  LDIR_USER_COPY_TIMEOUT       seconds for one copy from a home directory
                                    (default: 60 fast, 600 full; 0 = none)
  LDIR_VIRT_TIMEOUT            seconds per hypervisor query (default: 20)
  LDIR_VERBOSE                 1/0  also print "not present" notices

Examples:
  sudo $0 /mnt/usb/evidence
  sudo $0 --mode full --archive /mnt/usb/evidence
  sudo $0 --log-days 90 --archive /mnt/usb/evidence

Verify a collection afterwards:
  cd <output>/<host>_<timestamp> && sha256sum -c metadata/file_hashes.txt

Exit status:
  0  all modules completed
  1  usage or setup error (nothing collected)
  2  collection finished, but at least one module failed or was not run
     (e.g. the output device filled up), or the hash list or archive failed
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
# 空 = 利用者の指定なし（モードの既定値を使う）。値の検証は引数解析の後でまとめて行う
LDIR_LOG_DAYS="${LDIR_LOG_DAYS:-}"
LDIR_LOG_MAX_MB="${LDIR_LOG_MAX_MB:-}"
LDIR_JOURNAL_MAX_MB="${LDIR_JOURNAL_MAX_MB:-}"
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
        --log-days|--log-max-mb|--journal-max-mb)
            [[ $# -ge 2 ]] || { log_error "$1 requires an argument"; exit 1; }
            case "$1" in
                --log-days) LDIR_LOG_DAYS="$2" ;;
                --log-max-mb) LDIR_LOG_MAX_MB="$2" ;;
                *) LDIR_JOURNAL_MAX_MB="$2" ;;
            esac
            # 空の値は「指定なし」と区別できないので、ここで弾く
            [[ -n "$2" ]] || { log_error "$1 requires a non-empty argument"; exit 1; }
            shift 2
            ;;
        --log-days=*)
            LDIR_LOG_DAYS="${1#*=}"
            [[ -n "${LDIR_LOG_DAYS}" ]] || { log_error "--log-days requires a non-empty argument"; exit 1; }
            shift
            ;;
        --log-max-mb=*)
            LDIR_LOG_MAX_MB="${1#*=}"
            [[ -n "${LDIR_LOG_MAX_MB}" ]] || { log_error "--log-max-mb requires a non-empty argument"; exit 1; }
            shift
            ;;
        --journal-max-mb=*)
            LDIR_JOURNAL_MAX_MB="${1#*=}"
            [[ -n "${LDIR_JOURNAL_MAX_MB}" ]] || { log_error "--journal-max-mb requires a non-empty argument"; exit 1; }
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

# ログの期間と容量の上限（30/60/90 日以外は受け付けない）
if ! ldir_resolve_log_settings; then
    log_error "${LDIR_SETTINGS_ERROR}"
    exit 1
fi
# ホーム配下のコピーの上限（1 ファイルのサイズと、1 回の時間）
if ! ldir_resolve_user_copy_settings; then
    log_error "${LDIR_SETTINGS_ERROR}"
    exit 1
fi

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
log_info "Logs: period $(ldir_log_period_text), size cap $(ldir_log_cap_text), binary journal $(ldir_journal_cap_text)"
log_info "Output directory: ${COLLECTION_DIR}"

# 環境検出ライブラリ読み込み
if [[ -f "${SCRIPT_DIR}/lib/detect_distro_advanced.sh" ]]; then
    # shellcheck source=lib/detect_distro_advanced.sh
    source "${SCRIPT_DIR}/lib/detect_distro_advanced.sh"
    detect_all
    detect_virtualization
    log_info "Virtualization: ${VIRT_TYPE} (${VIRT_SOURCE})"
else
    log_error "lib/detect_distro_advanced.sh not found"
    exit 1
fi

# ユーザーのホームディレクトリ（passwd から。モジュールはこの一覧を共有する）
# 失敗しても収集は止めない（空なら各モジュールが自分で計算する）
LDIR_USER_HOMES="$(ldir_compute_user_homes)" || LDIR_USER_HOMES=""
export LDIR_USER_HOMES

# Manifest作成開始
MANIFEST="${METADATA_DIR}/manifest.txt"
START_EPOCH=$(date +%s)
cat > "${MANIFEST}" << EOF
=== LDIR-Collector Collection Manifest ===
Collector Version: ${LDIR_VERSION}
Collection Mode: ${LDIR_MODE}
Secret Redaction: ${LDIR_REDACT_SECRETS}
Log Days: ${LDIR_LOG_DAYS}
Log Since: ${LDIR_LOG_SINCE:-none (no period limit)}
Log Size Cap: $(ldir_log_cap_text)
Journal Size Cap: $(ldir_journal_cap_text)
Home File Cap: $([[ "${LDIR_USER_FILE_MAX_MB}" = 0 ]] && echo unlimited || echo "${LDIR_USER_FILE_MAX_MB} MB per file")
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
Virtualization: ${VIRT_TYPE:-unknown} (${VIRT_SOURCE:-not detected})
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
# 出力先が満杯（または書けない）になったら、以降のモジュールは動かさず、取れた分のハッシュ一覧を
# 作って終了コード 2 で終える（v0.4.0 では manifest への追記の失敗で set -e により終了コード 1 で
# 止まり、ハッシュ一覧が作られなかった。終了コード 1 は「何も収集していない」の意味）。
# ハッシュ一覧を書く余地を残すため、最初に 4 MB の予備のファイルを置き、ハッシュの前に消す。
OUTPUT_FULL=0
FULL_AT=""
NOT_RUN=""
PENDING=()
RESERVE="${METADATA_DIR}/.space_reserve"
head -c 4194304 /dev/zero > "${RESERVE}" 2>/dev/null || true

manifest_add() {
    printf '%s\n' "$@" >> "${MANIFEST}" 2>/dev/null
}

for module in "${MODULES[@]}"; do
    if [[ ${OUTPUT_FULL} -eq 1 ]]; then
        NOT_RUN="${NOT_RUN}${NOT_RUN:+ }${module}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_error "Module ${module} not run: the output device is full"
        continue
    fi
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
        line="✓ ${module} (${detail})"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "Module ${module} failed (exit=${module_rc}, ${detail})"
        line="✗ ${module} (exit=${module_rc}, ${detail})"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    # 満杯の検出: manifest への追記は、最後のブロックに余白があれば満杯でも成功するので、
    # 新しいファイルを 1 つ書いてみる（新しいブロックが要る）
    probe_ok=1
    { printf 'probe\n' > "${METADATA_DIR}/.write_probe"; } 2>/dev/null || probe_ok=0
    rm -f "${METADATA_DIR}/.write_probe"
    if [[ ${probe_ok} -eq 0 ]] || ! manifest_add "${line}"; then
        OUTPUT_FULL=1
        FULL_AT="${module}"
        PENDING+=("${line}")
        log_error "Cannot write to ${COLLECTION_DIR}: the output device is full (or not writable). The remaining modules are not run; hashes of what was collected are written next."
    fi
done

# 予備を消して、ハッシュ一覧と manifest の残りを書く余地を作る
rm -f "${RESERVE}"
if [[ ${OUTPUT_FULL} -eq 1 ]]; then
    manifest_add "${PENDING[@]}" || true
    for module in ${NOT_RUN}; do
        manifest_add "✗ ${module} (not run: output device full)" || true
    done
    manifest_add "" "=== Output Device Full ===" \
        "The output device filled up during ${FULL_AT}. Files written by that module may be incomplete;" \
        "the modules marked 'not run' were not executed. The hash list covers what was written." || true
fi

# 収集統計
# 統計が取れないことを理由に、ハッシュ生成の手前で止まらないようにする
TOTAL_FILES=$(find "${COLLECTION_DIR}" -type f 2>/dev/null | wc -l) || TOTAL_FILES="unknown"
TOTAL_SIZE=$(du -sh "${COLLECTION_DIR}" 2>/dev/null | awk '{print $1}') || TOTAL_SIZE="unknown"

manifest_add "" \
    "=== Collection Statistics ===" \
    "Total Files: ${TOTAL_FILES}" \
    "Total Size: ${TOTAL_SIZE}" \
    "Successful Modules: ${SUCCESS_COUNT}" \
    "Failed Modules: ${FAIL_COUNT}" \
    "Elapsed Seconds: $(( $(date +%s) - START_EPOCH ))" \
    "Collection End Time: $(date '+%Y-%m-%d %H:%M:%S %z')" || true

log_info "Collection finished: ${SUCCESS_COUNT} succeeded, ${FAIL_COUNT} failed"
log_info "Generating SHA256 hashes..."

# ---- ここから先は collection.log に書かない ----
# ハッシュ生成後にログへ追記すると、collection.log のハッシュが合わなくなる。
OUTPUT_DIR=""

# SHA256ハッシュ生成
# - 相対パスで記録する（別ホスト・別パスへ移しても検証できる）
# - 検証: cd <collection_dir> && sha256sum -c metadata/file_hashes.txt
# - 書けなかった場合（出力先が満杯）は、途中までの一覧を消し、一覧を標準出力に出す
#   （作業記録に残すこと。仕様書 3.2 節）
HASH_FILE="${METADATA_DIR}/file_hashes.txt"
HASH_OK=1
HASH_LIST=""
if have_cmd sha256sum; then
    (
        cd "${COLLECTION_DIR}"
        find . -type f ! -path ./metadata/file_hashes.txt -print0 \
            | sort -z \
            | xargs -0 sha256sum > metadata/file_hashes.txt
    ) 2>/dev/null || HASH_OK=0
    if [[ ${HASH_OK} -ne 1 ]]; then
        rm -f "${HASH_FILE}"
        HASH_LIST="$(cd "${COLLECTION_DIR}" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null)" || true
    fi
else
    HASH_OK=0
fi
if [[ ${HASH_OK} -ne 1 ]]; then
    if [[ -n "${HASH_LIST}" ]]; then
        log_error "SHA256 hash list could not be written to ${HASH_FILE} (output device full?); it is printed below instead"
    else
        log_error "SHA256 hash generation failed or incomplete: ${HASH_FILE}"
    fi
fi

# アーカイブ作成（任意）
ARCHIVE_PATH=""
ARCHIVE_OK=1
if [[ "${LDIR_ARCHIVE}" = "1" ]]; then
    ARCHIVE_PATH="${OUTPUT_BASE}/${COLLECTION_NAME}.tar.gz"
    log_info "Creating archive: ${ARCHIVE_PATH}"
    if tar -czf "${ARCHIVE_PATH}" -C "${OUTPUT_BASE}" "${COLLECTION_NAME}" 2>/dev/null; then
        ( cd "${OUTPUT_BASE}" && sha256sum "${COLLECTION_NAME}.tar.gz" > "${COLLECTION_NAME}.tar.gz.sha256" ) || true
    else
        # 途中まで書けたアーカイブは完全なものに見えるので残さない（収集ディレクトリは残る）
        rm -f "${ARCHIVE_PATH}" "${ARCHIVE_PATH}.sha256"
        log_error "Archive creation failed; the incomplete archive was removed (the collection directory is kept)"
        ARCHIVE_PATH=""
        ARCHIVE_OK=0
    fi
fi

if [[ ${OUTPUT_FULL} -eq 1 ]]; then
    log_error "Collection incomplete: the output device is full (modules not run: ${NOT_RUN:-none})"
else
    log_success "Collection complete!"
fi

# サマリー表示
echo ""
echo "=== Collection Summary ==="
echo "Output:             ${COLLECTION_DIR}"
echo "Manifest:           ${MANIFEST}"
if [[ ${HASH_OK} -eq 1 ]]; then
    echo "Hashes:             ${HASH_FILE}"
    # 証拠保全記録（chain of custody）に控える値
    echo "Hash list SHA256:   $(sha256sum "${HASH_FILE}" | awk '{print $1}')"
else
    echo "Hashes:             NOT WRITTEN to ${HASH_FILE}"
fi
if [[ -n "${ARCHIVE_PATH}" ]]; then
    echo "Archive:            ${ARCHIVE_PATH}"
    echo "Archive SHA256:     $(awk '{print $1}' "${ARCHIVE_PATH}.sha256" 2>/dev/null || echo unknown)"
fi
echo "Total Files:        ${TOTAL_FILES}"
echo "Total Size:         ${TOTAL_SIZE}"
echo "Successful Modules: ${SUCCESS_COUNT}/${#MODULES[@]}"
echo "Failed Modules:     ${FAIL_COUNT}/${#MODULES[@]}"
if [[ ${OUTPUT_FULL} -eq 1 ]]; then
    echo "Output device:      FULL during ${FULL_AT}; the output device is full, so these modules were not run: ${NOT_RUN:-none}"
fi
echo ""
if [[ ${HASH_OK} -ne 1 && -n "${HASH_LIST}" ]]; then
    echo "=== Hash list (metadata/file_hashes.txt could not be written; keep this output) ==="
    printf '%s\n' "${HASH_LIST}"
    echo "=== End of hash list (SHA256 of the list above: $(printf '%s\n' "${HASH_LIST}" | sha256sum | awk '{print $1}')) ==="
    echo ""
fi

if [[ ${FAIL_COUNT} -gt 0 || ${HASH_OK} -ne 1 || ${ARCHIVE_OK} -ne 1 || ${OUTPUT_FULL} -eq 1 ]]; then
    exit 2
fi
exit 0
