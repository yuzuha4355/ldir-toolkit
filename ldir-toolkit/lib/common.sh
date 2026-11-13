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

# find 用: 詳細表示アクション。BusyBox の find は -ls を持たないため、
# その場合は ls -ld に切り替える（黙って空の出力になるのを防ぐ）。
# 使い方: find /etc -type f "${LDIR_FIND_LS[@]}"
# shellcheck disable=SC2034  # モジュール側で使用
if find / -maxdepth 0 -ls >/dev/null 2>&1; then
    LDIR_FIND_LS=( -ls )
else
    LDIR_FIND_LS=( -exec ls -ld {} + )
fi

# 環境変数の秘匿値マスク（stdin -> stdout のフィルタ）
# 収集物は調査担当者や外部ベンダへ渡るため、トークン類の値は既定で伏せる。
# 名前は残す（「何が設定されていたか」は調査に必要）。値は文字数だけ残す。
#   AWS_SECRET_ACCESS_KEY=abcd...   -> AWS_SECRET_ACCESS_KEY=<redacted:40 chars>
#   HTTPS_PROXY=http://u:pw@host/   -> HTTPS_PROXY=http://u:<redacted>@host/
#   "DB_PASSWORD=x",  (docker inspect の Env 配列) も同じ規則で処理する。
# LDIR_REDACT_SECRETS=0 で無効化（原本をそのまま残す）。
# 注意: PWD / OLDPWD / SSH_AUTH_SOCK / XDG_SESSION_ID のような無害な変数を巻き込まないこと。
# ただし迷ったら伏せる側に倒す。MAX_TOKENS のような「個数」を避けようとして
# TOKEN の後ろに条件を付けた結果、GITHUB_TOKENS が平文で残った（v0.3.1 の不具合）。
# 伏せすぎは --no-redact で取り戻せるが、漏れは取り戻せない。
LDIR_SECRET_NAME_RE='(TOKEN|SECRET|PASSW|_PWD$|PGPASS|CREDENTIAL|APIKEY|API_KEY|ACCESS_KEY|PRIVATE_KEY|_KEY$|^KEY$|AUTHORIZATION|_AUTH$|COOKIE|BEARER|JWT|SIGNATURE)'

redact_env() {
    if [[ "${LDIR_REDACT_SECRETS:-1}" != "1" ]]; then
        cat
        return 0
    fi
    awk -v re="${LDIR_SECRET_NAME_RE}" '
    {
        line = $0
        # 形式: [空白]["]NAME=VALUE["][,]
        if (match(line, /^[ \t]*"?[A-Za-z_][A-Za-z0-9_]*=/)) {
            head = substr(line, 1, RLENGTH)          # 先頭〜"=" まで
            rest = substr(line, RLENGTH + 1)
            name = head
            sub(/^[ \t]*"?/, "", name); sub(/=$/, "", name)
            tail = ""
            if (head ~ /^[ \t]*"/ && match(rest, /",?[ \t]*$/)) {
                tail = substr(rest, RSTART)
                rest = substr(rest, 1, RSTART - 1)
            }
            # LDIR_* は本ツール自身の設定値（秘匿値ではない）
            if (toupper(name) ~ re && name !~ /^LDIR_/ && rest != "") {
                print head "<redacted:" length(rest) " chars>" tail
                next
            }
            # URL に埋め込まれた認証情報  scheme://user:password@host
            while (match(rest, /:\/\/[^:\/@ ]+:[^@\/ ]+@/)) {
                cred = substr(rest, RSTART, RLENGTH)
                user = cred; sub(/^:\/\//, "", user); sub(/:.*$/, "", user)
                rest = substr(rest, 1, RSTART - 1) "://" user ":<redacted>@" substr(rest, RSTART + RLENGTH)
                if (++guard > 20) break
            }
            print head rest tail
            next
        }
        print line
    }'
}

# 時間制限付きでコマンドを実行する（応答しないデーモンへの問い合わせ対策）
# 使い方: run_limited 20 docker ps -a
run_limited() {
    local secs="$1"; shift
    if have_cmd timeout; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}

# capture <出力ファイル> <コマンド> [引数...]
# コマンドの出力（標準エラー込み）をファイルに保存する。
#   - コマンドが無い     : その旨をファイルに書き、DEBUG（最小構成では想定内）
#   - 非 0 で終了した    : WARN（manifest の warn= に数えられる）
# 「> file 2>&1」の直書きは、失敗してもエラー文がファイルに入るだけで
# manifest に現れない。収集の欠落を見逃さないため、原則こちらを使う。
capture() {
    local out="$1"; shift
    local rc=0
    ensure_dir "$(dirname "$out")" || { log_warn "Failed to create dir for output: $out"; return 1; }
    if ! have_cmd "$1"; then
        echo "$1: command not available on this host" > "$out"
        log_debug "Command not available: $1"
        return 127
    fi
    "$@" > "$out" 2>&1 || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        log_warn "Command failed (exit ${rc}): $* -> ${out##*/}"
    fi
    return ${rc}
}

# capture_try: capture と同じだが、失敗しても WARN を出さない。
# 代替コマンドが後ろに控えている場合に使う:
#   capture_try "$f" ip addr show || capture "$f" ifconfig -a
capture_try() {
    local out="$1"; shift
    ensure_dir "$(dirname "$out")" || return 1
    have_cmd "$1" || return 127
    "$@" > "$out" 2>&1
}

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
