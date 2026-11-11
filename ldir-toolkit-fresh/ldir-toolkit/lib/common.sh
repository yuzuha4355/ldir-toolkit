#!/bin/bash
#
# LDIR-Toolkit - Common Functions Library
# 共通関数ライブラリ
#

# カラー定義（端末出力のときだけ着色。NO_COLOR で無効化可能）
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# ログ関数
_ldir_log_write() {
    local level="$1"; shift
    local msg="$1"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    # stdout (color)
    case "$level" in
        INFO)    echo -e "${GREEN}[INFO]${NC} ${ts} - ${msg}" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} ${ts} - ${msg}" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} ${ts} - ${msg}" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} ${ts} - ${msg}" ;;
        MODULE)  echo -e "${BLUE}[MODULE]${NC} ${ts} - ${msg}" ;;
        DEBUG)   [[ "${LDIR_VERBOSE:-0}" = "1" ]] && echo "[DEBUG] ${ts} - ${msg}" ;;
        *)       echo -e "${GREEN}[INFO]${NC} ${ts} - ${msg}" ;;
    esac

    # main collection log
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[${level}] ${ts} - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log"
    fi

    # per-module log (set by ldir-collect.sh)
    if [[ -n "${LDIR_MODULE_LOG:-}" ]]; then
        echo "[${level}] ${ts} - ${msg}" >> "${LDIR_MODULE_LOG}"
    fi
}

log_info() {
    _ldir_log_write "INFO" "$1"
}

log_error() {
    _ldir_log_write "ERROR" "$1"
}

log_success() {
    _ldir_log_write "SUCCESS" "$1"
}

log_warn() {
    _ldir_log_write "WARN" "$1"
}

log_module() {
    _ldir_log_write "MODULE" "$1"
}

# 想定内の事象（対象ファイルが存在しない等）。ログファイルには残すが、
# 画面には LDIR_VERBOSE=1 のときだけ出し、WARN 件数には数えない。
log_debug() {
    _ldir_log_write "DEBUG" "$1"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ディレクトリ作成（存在していてもOK）
ensure_dir() {
    local dir="$1"
    [[ -z "$dir" ]] && return 1
    mkdir -p "$dir" 2>/dev/null || return 1
}

# 安全なファイルコピー（エラーがあっても継続）
# - 宛先ディレクトリを自動作成
# - 属性/タイムスタンプを可能な限り保持（cp -a）
# - コピー元が存在しないのは想定内（DEBUG）。コピー失敗のみ WARN。
#
# 宛先の解釈（rsync と同じ規則）:
#   safe_copy /etc/passwd  DST/        -> DST/passwd
#   safe_copy /etc/passwd  DST/pw      -> DST/pw
#   safe_copy /etc/pam.d/  DST/pam.d/  -> DST/pam.d/<中身>   （src 末尾 / = 中身をコピー）
#   safe_copy /etc/s6      DST/        -> DST/s6/<中身>
#   safe_copy /etc/s6      DST/s6_cfg  -> DST/s6_cfg/<中身>  （DST/s6_cfg が無い場合）
safe_copy() {
    local src="$1"
    local dst="$2"

    if [[ -z "$src" || -z "$dst" ]]; then
        log_warn "safe_copy called with empty src/dst"
        return 1
    fi

    if [[ ! -e "$src" ]]; then
        log_debug "Not present: $src"
        return 1
    fi

    # src がディレクトリで末尾 / 付き: 中身を dst 直下へ
    if [[ -d "$src" && "$src" == */ ]]; then
        ensure_dir "$dst" || { log_warn "Failed to create dir: $dst"; return 1; }
        cp -a "${src%/}/." "${dst%/}/" 2>/dev/null && return 0
        log_warn "Failed to copy: $src"
        return 1
    fi

    # dst がディレクトリ指定なら作ってそこへコピー
    if [[ -d "$dst" || "$dst" == */ ]]; then
        ensure_dir "$dst" || { log_warn "Failed to create dir: $dst"; return 1; }
        cp -a "$src" "$dst" 2>/dev/null && return 0
        log_warn "Failed to copy: $src"
        return 1
    fi

    # dst がファイルパス指定なら親ディレクトリを作ってコピー
    ensure_dir "$(dirname "$dst")" || { log_warn "Failed to create dir for: $dst"; return 1; }
    cp -a "$src" "$dst" 2>/dev/null && return 0

    log_warn "Failed to copy: $src"
    return 1
}

# find 用: 収集先ディレクトリ自身を走査対象から外す（自己混入の防止）
# 使い方: find / "${LDIR_FIND_PRUNE[@]}" -type f ... -print
# shellcheck disable=SC2034  # モジュール側で使用
if [[ -n "${OUTPUT_DIR:-}" ]]; then
    LDIR_FIND_PRUNE=( -path "${OUTPUT_DIR%/}" -prune -o )
else
    LDIR_FIND_PRUNE=()
fi

# コマンド出力を保存（出力ファイルの親ディレクトリを自動作成）
save_command_output() {
    local cmd="$1"
    local output_file="$2"
    local description="${3:-$cmd}"

    if [[ -z "$cmd" || -z "$output_file" ]]; then
        log_warn "save_command_output called with empty cmd/output_file"
        return 1
    fi

    ensure_dir "$(dirname "$output_file")" || {
        log_warn "Failed to create dir for output: $output_file"
        return 1
    }

    if eval "$cmd" > "$output_file" 2>&1; then
        return 0
    else
        log_warn "Command failed: $description"
        return 1
    fi
}

# ファイルが存在するかチェックして処理
process_if_exists() {
    local file="$1"
    local action="$2"
    
    if [[ -e "$file" ]]; then
        eval "$action"
        return 0
    else
        return 1
    fi
}
