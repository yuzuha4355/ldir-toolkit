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
    # 出力先が満杯でも、ログが書けないことで本体（set -e）を止めない（v0.4.0 の検証で、
    # 満杯のときに終了コード 1 で止まり、ハッシュ一覧が作られなかった）
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[${level}] ${ts} - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log" 2>/dev/null || true
    fi

    # per-module log (set by ldir-collect.sh)
    if [[ -n "${LDIR_MODULE_LOG:-}" ]]; then
        echo "[${level}] ${ts} - ${msg}" >> "${LDIR_MODULE_LOG}" 2>/dev/null || true
    fi
    return 0
}

# WARN 等の先頭に付けるモジュール名（ldir-collect.sh が LDIR_MODULE を渡す）
LDIR_TAG=""
[[ -n "${LDIR_MODULE:-}" ]] && LDIR_TAG="[${LDIR_MODULE%.sh}] "

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

    if [[ ! -e "$src" && ! -L "${src%/}" ]]; then
        log_debug "Not present: $src"
        return 1
    fi

    # シンボリックリンク（/etc/resolv.conf -> ../run/... 等）は、root しか変えられない場所に
    # ある場合だけ、指す先の内容を取る（_ldir_copy_symlink）。cp -a はリンクのまま写すため、
    # 収集物の中では宙に浮いたリンクになり、ハッシュ一覧にも載らない。
    # ユーザーが書ける場所のリンクはたどらない（ユーザーのホームは ldir_copy_user_files を使う）。
    # 末尾 / 付き（中身のコピー）でも、src 自体がリンクなら同じ扱い（cp -a "src/." はたどるため）。
    if [[ -L "${src%/}" ]]; then
        _ldir_copy_symlink "$src" "$dst"
        return $?
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
    if [[ ${rc} -eq 124 && "$1" = "run_limited" ]]; then
        log_warn "Command timed out after ${2}s: ${*:3} -> ${out##*/}"
    elif [[ ${rc} -ne 0 ]]; then
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

# 時間制限付きでコマンドを実行する（応答しないデーモンへの問い合わせ対策）
# 使い方: run_limited 20 docker ps -a
# 秒数に 0 を渡した場合は時間制限なし（full モードの既定値に使う）
# 打ち切った場合の終了コードは 124 に揃える。BusyBox の timeout は 143（SIGTERM）を
# 返すため、124 を見て「打ち切り」を判定する箇所（70_filesystem の部分結果の注記等）が
# Alpine では働かず、途中で切れた結果が完全な結果に見えていた（v0.3.2 まで）。
run_limited() {
    local secs="$1"; shift
    local rc=0 start
    if [[ "${secs}" != "0" ]] && have_cmd timeout; then
        start=${SECONDS}
        timeout "$secs" "$@" || rc=$?
        if [[ ${rc} -eq 143 || ${rc} -eq 137 ]] && (( SECONDS - start >= secs )); then
            rc=124
        fi
        return ${rc}
    fi
    "$@"
}

# ---------------------------------------------------------------------------
# 「root しか変えられない場所か」の判定（パスの見た目ではなく、実際の所有者と権限で見る）

# 秘密鍵の中身の判定: PEM の各種（RSA / EC / OPENSSH / ENCRYPTED ...）、PGP の秘密鍵ブロック、PuTTY
LDIR_PRIVATE_KEY_RE='-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----|PuTTY-User-Key-File'
LDIR_NL=$'\n'

# _ldir_kind_into <パス>: リンクをたどった先の種別を LDIR_KIND に入れる（fork しない）
_ldir_kind_into() {
    if [[ ! -e "$1" ]]; then LDIR_KIND="missing"
    elif [[ -f "$1" ]]; then LDIR_KIND="regular file"
    elif [[ -d "$1" ]]; then LDIR_KIND="directory"
    elif [[ -c "$1" ]]; then LDIR_KIND="character device"
    elif [[ -b "$1" ]]; then LDIR_KIND="block device"
    elif [[ -p "$1" ]]; then LDIR_KIND="fifo"
    elif [[ -S "$1" ]]; then LDIR_KIND="socket"
    else LDIR_KIND="other"
    fi
}

# _ldir_prefixes_into <絶対パス>: "/" から順に、途中のディレクトリとそのパス自身を LDIR_PREFIXES に入れる
_ldir_prefixes_into() {
    local rest="${1#/}" acc="" c
    LDIR_PREFIXES=(/)
    while [[ -n "$rest" ]]; do
        c="${rest%%/*}"
        if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
        [[ -n "$c" && "$c" != "." ]] || continue
        acc="${acc}/${c}"
        LDIR_PREFIXES+=("$acc")
    done
}

# _ldir_dirs_root_only <ディレクトリ>...: すべてが root の持ち物で、group と other に
# 書き込み権が無ければ 0。違うものがあれば、その 1 つを LDIR_UNTRUSTED に入れて 1。
_ldir_dirs_root_only() {
    local out bad
    LDIR_UNTRUSTED=""
    [[ $# -gt 0 ]] || return 0
    out="$(stat -L -c '%u %a %n' -- "$@" 2>/dev/null)"
    bad="$(printf '%s\n' "$out" | awk -v want="$#" '
        NF >= 3 {
            c++; m = $2; o = substr(m, length(m), 1) + 0; g = substr(m, length(m) - 1, 1) + 0
            if ($1 != 0 || int(o / 2) % 2 || int(g / 2) % 2) { p = $0; sub(/^[^ ]+ [^ ]+ /, "", p); print p; exit }
        }
        END { if (c < want) print "(a directory that could not be examined)" }')"
    [[ -z "$bad" ]] && return 0
    LDIR_UNTRUSTED="${bad%%"${LDIR_NL}"*}"
    return 1
}

# _ldir_link_trusted <リンク> <たどった先（readlink -f）> <file|dir>
# リンクが root にしか変えられないものなら 0。次のディレクトリをすべて確かめる:
#   - リンクのあるディレクトリと、その上のすべて（書かれたパスどおりと、実際の場所の両方）
#   - リンク先の上のディレクトリ。リンク先がファイルなら、それを直接含むディレクトリは除く
#     （/etc/resolv.conf の先の /run/systemd/resolve はサービスの持ち物。そこでの差し替えは、
#     たどらないコピー（cp -a）と時間の上限、写した後の確認で防ぐ）
_ldir_link_trusted() {
    local link="$1" target="$2" kind="${3:-file}" d
    local -a dirs=()
    LDIR_UNTRUSTED=""
    if [[ "$link" != /* || "$target" != /* ]]; then
        LDIR_UNTRUSTED="(not an absolute path)"
        return 1
    fi
    d="${link%/*}"; [[ -n "$d" ]] || d=/
    _ldir_prefixes_into "$d"; dirs+=("${LDIR_PREFIXES[@]}")
    if d="$(cd -P -- "$d" 2>/dev/null && pwd -P)"; then
        _ldir_prefixes_into "$d"; dirs+=("${LDIR_PREFIXES[@]}")
    fi
    if [[ "$kind" = dir ]]; then
        _ldir_prefixes_into "$target"
    else
        d="${target%/*}"; d="${d%/*}"; [[ -n "$d" ]] || d=/
        _ldir_prefixes_into "$d"
    fi
    dirs+=("${LDIR_PREFIXES[@]}")
    _ldir_dirs_root_only "${dirs[@]}"
}

# safe_copy から呼ぶ: シンボリックリンクを扱う。root しか変えられないリンクだけをたどり、
# 指す先が通常ファイル（秘密鍵でないもの）かディレクトリなら、その内容をコピーする。
# 結果はコピー先の _symlinks.txt に 1 行で残す。/dev/null へのリンクは所見として WARN。
_ldir_copy_symlink() {
    local src="$1" dst="$2" link="${1%/}" target resolved kind dst_path note_dir note line rc=0
    target="$(readlink -- "$link" 2>/dev/null)" || target="?"
    resolved="$(run_limited 10 readlink -f -- "$link" 2>/dev/null)" || resolved=""
    _ldir_kind_into "$link"; kind="${LDIR_KIND}"
    if [[ "$src" == */ ]]; then
        dst_path="${dst%/}"
    elif [[ -d "$dst" || "$dst" == */ ]]; then
        dst_path="${dst%/}/${link##*/}"
    else
        dst_path="$dst"
    fi
    note_dir="$(dirname -- "$dst_path")"
    ensure_dir "$note_dir" || { log_warn "Failed to create dir: $note_dir"; return 1; }
    note="${note_dir}/_symlinks.txt"
    line="${link} -> ${target}"
    if [[ "$resolved" == /dev/null || "$target" == /dev/null ]]; then
        echo "${line}: points to /dev/null (what is written there is discarded); nothing copied" >> "$note"
        log_warn "${LDIR_TAG}${link} is a symbolic link to /dev/null: what is written there is discarded (see $(_ldir_shown "$note"))"
        return 1
    fi
    if [[ "$kind" = missing ]]; then
        echo "${line}: dangling link (target missing); nothing copied" >> "$note"
        log_debug "Dangling symlink: ${line}"
        return 1
    fi
    if [[ -z "$resolved" ]] || ! _ldir_link_trusted "$link" "$resolved" "$([[ "$kind" = directory ]] && echo dir || echo file)"; then
        echo "${line}: not followed (${LDIR_UNTRUSTED:-the path} can be changed by a user other than root); target: ${kind}; nothing copied" >> "$note"
        log_debug "Symlink not followed (location not root-only): ${line}"
        return 1
    fi
    case "$kind" in
        directory)
            { ensure_dir "$dst_path" && cp -a "${resolved}/." "${dst_path}/" 2>/dev/null; } || rc=1
            ;;
        "regular file")
            if run_limited 30 grep -qE -- "${LDIR_PRIVATE_KEY_RE}" "$resolved" 2>/dev/null; then
                echo "${line}: the target holds a private key; not copied (SPECIFICATION 8.2)" >> "$note"
                return 1
            fi
            # cp -a: 確かめた後にリンクへ差し替えられても、たどらずにリンクとして写す（下で消す）
            run_limited 30 cp -a -- "$resolved" "$dst_path" 2>/dev/null || rc=1
            if [[ -L "$dst_path" || ( -e "$dst_path" && ! -f "$dst_path" ) ]]; then
                rm -rf -- "$dst_path"
                rc=1
            fi
            ;;
        *)
            echo "${line}: the target is a ${kind}; not read" >> "$note"
            log_warn "${LDIR_TAG}${link} is a symbolic link to a ${kind} (${resolved}); not read (see $(_ldir_shown "$note"))"
            return 1
            ;;
    esac
    if [[ ${rc} -ne 0 ]]; then
        log_warn "Failed to copy: ${link} (symlink to ${target})"
        return 1
    fi
    echo "${line}: copied the target's content as ${dst_path##*/}" >> "$note"
    return 0
}

# 収集ディレクトリからの相対パス（WARN の文言用）
_ldir_shown() {
    local p="$1"
    [[ -n "${OUTPUT_DIR:-}" ]] && p="${p#"${OUTPUT_DIR%/}"/}"
    printf '%s' "$p"
}

# _ldir_excluded <記録ファイル> <理由> <パス> [詳細]
# コピーしなかったものを excluded_files.txt に 1 行で残す（理由<TAB>パス<TAB>詳細）。
# パスの改行とタブは \n \t と書く（1 件 1 行を保つ）。
_ldir_excluded() {
    local report="$1" reason="$2" path="$3" detail="${4:-}"
    [[ -n "$report" ]] || return 0
    if [[ ! -e "$report" ]]; then
        ensure_dir "$(dirname -- "$report")" || return 0
        printf '# Not copied (SPECIFICATION 8.2). Columns: reason, path, detail (tab-separated). Newlines in names are written as \\n.\n' > "$report" 2>/dev/null
    fi
    path="${path//${LDIR_NL}/\\n}"; path="${path//${LDIR_TAB}/\\t}"
    detail="${detail//${LDIR_NL}/\\n}"; detail="${detail//${LDIR_TAB}/\\t}"
    printf '%s\t%s\t%s\n' "$reason" "$path" "$detail" >> "$report" 2>/dev/null
    return 0
}

# capture_host <出力ファイル> <コマンド> [引数...]
# カーネルやネットワークの設定を読むコマンド（dmesg, iptables, bpftool 等）用。
# ホストでは capture と同じ（失敗は WARN）。コンテナ内では権限が無いのが普通なので、
# 失敗は DEBUG に留め、理由をファイルに書き足す（WARN を雑音で埋めないため）。
capture_host() {
    local out="$1"; shift
    local rc=0
    if [[ "${CONTAINER_TYPE:-none}" = "none" ]]; then
        capture "$out" "$@"
        return $?
    fi
    capture_try "$out" "$@" || rc=$?
    if [[ ${rc} -ne 0 && ${rc} -ne 127 ]]; then
        echo "# exit ${rc} inside a container (${CONTAINER_TYPE}); kernel/network state is usually not readable here" >> "$out"
        log_debug "Command failed inside container (exit ${rc}): $*"
    elif [[ ${rc} -eq 127 ]]; then
        echo "$1: command not available on this host" > "$out"
    fi
    return ${rc}
}

# capture_partial <出力ファイル> <コマンド> [引数...]
# 一部が読めなくても出力を続けるコマンド（sysctl -a, ls -R 等）用。
#   非 0 で終了しても出力があれば「部分的に取れた」: DEBUG
#   非 0 で終了して出力が空なら「取れなかった」: WARN
capture_partial() {
    local out="$1"; shift
    local rc=0
    capture_try "$out" "$@" || rc=$?
    if [[ ${rc} -eq 127 ]]; then
        echo "$1: command not available on this host" > "$out"
        log_debug "Command not available: $1"
    elif [[ ${rc} -ne 0 ]]; then
        if [[ -s "$out" ]]; then
            log_debug "Command exited ${rc} with partial output: $* -> ${out##*/}"
        else
            log_warn "Command failed (exit ${rc}) with no output: $* -> ${out##*/}"
        fi
    fi
    return ${rc}
}

# mark_partial <ファイル> <説明>...
# 打ち切られた出力の先頭に注記を入れる。空や短いファイルを「該当なし」と
# 読み違えないため（70_filesystem の # PARTIAL RESULT と同じ流儀）。
mark_partial() {
    local f="$1"; shift
    local line
    {
        for line in "$@"; do echo "# PARTIAL RESULT: ${line}"; done
        cat "$f" 2>/dev/null
    } > "${f}.partial.tmp" && mv -f "${f}.partial.tmp" "$f"
}

# ---------------------------------------------------------------------------
# ユーザーのホームディレクトリ
#
# 出力: "ラベル<TAB>ホーム<TAB>由来(passwd|orphan)<TAB>そのホームを持つアカウント（, 区切り）" を 1 行ずつ。
# v0.3.2 までは /root と /home/* に固定で、/var/lib/... や /srv/... にホームを持つ
# サービスアカウントの履歴・SSH 鍵・crontab を取りこぼしていた。
#   - passwd（getent があれば NSS 経由。LDAP 等のユーザーも含む）のホームのうち、実在するもの
#   - /root と /home/* のうち、どの passwd 項目からも参照されていないもの
#     （アカウントを消してもホームが残っている。ラベルは orphan-home_<名前>）
# 同じホームを共有するユーザーは 1 度だけ調べる。ラベルは、そのホームを持つアカウントのうち
# ホームのディレクトリの持ち主。持ち主がどのアカウントでもない場合（/ や /bin のように
# root の持ち物を複数のアカウントがホームにしている等）は "@<ホームのパス>"（例: @_ は /）とし、
# 収集物の名前にはファイルの持ち主を前に付ける（ldir_item_label。例: bash_history_root@_）。
# v0.4.0 では passwd で先に出てくる名前をラベルにしていたため、root が HOME=/ で残した
# /.bash_history が bash_history_systemd-network として収集された（検証レポートの指摘 10）。
# ldir-collect.sh が 1 度だけ計算して LDIR_USER_HOMES に入れ、各モジュールはそれを読む。
ldir_user_homes() {
    if [[ -n "${LDIR_USER_HOMES:-}" ]]; then
        printf '%s\n' "${LDIR_USER_HOMES}"
    else
        ldir_compute_user_homes
    fi
}

# ldir_compute_user_homes [passwd ファイル [追加で調べるディレクトリ...]]
# 引数なし: getent passwd（あれば）と /etc/passwd。追加は /root と /home/*。
# shellcheck disable=SC2120  # 引数はテストから渡す
ldir_compute_user_homes() {
    local passwd_src="${1:-}" label home src accounts uids owner a u flat
    local -a extra=(/root /home/*) an au
    [[ $# -gt 1 ]] && extra=("${@:2}")
    {
        if [[ -n "$passwd_src" ]]; then
            cat "$passwd_src" 2>/dev/null
        else
            have_cmd getent && run_limited 15 getent passwd 2>/dev/null
            cat /etc/passwd 2>/dev/null
        fi
        echo "#LDIR_EXTRA#"
        printf '%s\n' "${extra[@]}"
    } | awk -F: '
        function norm(p) { while (p ~ /.\/$/) sub(/\/$/, "", p); return p }
        $0 == "#LDIR_EXTRA#" { extra = 1; next }
        !extra && NF >= 6 && $6 ~ /^\// {
            h = norm($6)
            if (!(h in idx)) { idx[h] = ++n; home[n] = h; first[n] = $1; src[n] = "passwd" }
            i = idx[h]
            if (("," acc[i] ",") !~ ("," $1 ",")) { acc[i] = acc[i] (acc[i] == "" ? "" : ",") $1; uid[i] = uid[i] (uid[i] == "" ? "" : ",") $3 }
            next
        }
        extra && $0 ~ /^\// {
            h = norm($0)
            if (h in idx) next
            idx[h] = ++n; home[n] = h; src[n] = "orphan"
            b = h; sub(/.*\//, "", b); first[n] = "orphan-home_" b
        }
        END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\t%s\t%s\n", first[i], home[i], src[i], acc[i], uid[i] }' \
    | while IFS=$'\t' read -r label home src accounts uids; do
        [[ -d "$home" ]] || continue
        if [[ "$src" = passwd ]]; then
            owner="$(stat -L -c %u -- "$home" 2>/dev/null)" || owner=""
            IFS=, read -r -a an <<< "${accounts}"
            IFS=, read -r -a au <<< "${uids}"
            label=""
            for a in "${!au[@]}"; do
                u="${au[$a]}"
                if [[ -n "$owner" && "$u" == "$owner" ]]; then label="${an[$a]}"; break; fi
            done
            if [[ -z "$label" ]]; then
                flat="${home//\//_}"
                label="@${flat}"
            fi
        fi
        printf '%s\t%s\t%s\t%s\n' "${label//[^A-Za-z0-9._@-]/_}" "$home" "$src" "${accounts}"
    done
}

# ldir_item_label <ホームのラベル> <パス>
# 収集物の名前に使うラベル。ホームのラベルが "@..."（持ち主がどのアカウントでもないホーム）なら、
# そのファイル・ディレクトリの持ち主の名前を前に付ける（例: root@_）。それ以外はホームのラベル。
ldir_item_label() {
    local label="$1" p="$2" owner
    if [[ "$label" != @* ]]; then
        printf '%s' "$label"
        return 0
    fi
    owner="$(stat -c '%U' -- "$p" 2>/dev/null)" || owner=""
    if [[ -z "$owner" || "$owner" == UNKNOWN || "$owner" =~ ^[0-9]+$ ]]; then
        owner="uid$(stat -c '%u' -- "$p" 2>/dev/null)"
    fi
    owner="${owner//[^A-Za-z0-9._-]/_}"
    printf '%s%s' "$owner" "$label"
}

# ---------------------------------------------------------------------------
# 設定ファイルの秘匿値マスク（stdin -> stdout のフィルタ）
#
# VM 定義やハイパーバイザの設定ファイル向け。次の形の値を伏せる（名前の判定は
# redact_env と同じ LDIR_SECRET_NAME_RE に、cloud-init の user-data 等を足したもの）:
#   key = value / key=value / key: value / export KEY=value（行頭の # ; も含む）
#   YAML のブロック（key: | の後の字下げされた行）は丸ごと伏せる
#   JSON の "key": "value"（1 行 1 項目に分けてから渡すこと: ldir_json_split）
#   XML の属性 passwd='...' と要素 <password>...</password>
#   値に含まれる URL の ユーザー:パスワード@、QEMU の secret,...,data=...
# LDIR_REDACT_SECRETS=0 で無効。
# PSK / PRIVATEKEY / PRESHAREDKEY / WEP_KEYn: NetworkManager の psk=、systemd-networkd・WireGuard の
# PrivateKey= / PresharedKey=（名前に区切りが無く、LDIR_SECRET_NAME_RE の PRIVATE_KEY に当たらない）
LDIR_CONFIG_EXTRA_RE='(USER_DATA|VENDOR_DATA|^ENVIRONMENT_|PSK|PRIVATEKEY|PRESHAREDKEY|WEP_KEY[0-9])'
# shellcheck disable=SC2016  # awk のプログラム
LDIR_REDACT_CONFIG_AWK='
function is_secret(n,   u) {
    u = toupper(n); gsub(/[-.]/, "_", u)
    return (u ~ re || u ~ re2) && u !~ /^LDIR_/
}
function mask_urls(v,   cred, user, guard) {
    guard = 0
    while (match(v, /:\/\/[^:\/@ ]+:[^@\/ <]+@/)) {
        cred = substr(v, RSTART, RLENGTH)
        user = cred; sub(/^:\/\//, "", user); sub(/:.*$/, "", user)
        v = substr(v, 1, RSTART - 1) "://" user ":<redacted>@" substr(v, RSTART + RLENGTH)
        if (++guard > 20) break
    }
    guard = 0
    while (match(v, /secret,[^\047" ]*data=[^,\047" <]+/)) {
        seg = substr(v, RSTART, RLENGTH); sub(/data=.*$/, "data=", seg)
        v = substr(v, 1, RSTART - 1) seg "<redacted>" substr(v, RSTART + RLENGTH)
        if (++guard > 20) break
    }
    return v
}
function indent_of(s) { match(s, /^[ \t]*/); return RLENGTH }
{
    line = $0
    if (skip) {
        if (line ~ /^[ \t]*$/ || indent_of(line) > skip_indent) next
        skip = 0
    }
    # JSON: "key": "value"  （1 行に 1 項目）
    if (match(line, /^[ \t]*"[^"]+"[ \t]*:[ \t]*"/)) {
        head = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH + 1)
        name = head; sub(/^[ \t]*"/, "", name); sub(/".*$/, "", name)
        # 値の終わり = 行の最後の "
        last = 0; tmp = rest; off = 0
        while ((p = index(tmp, "\"")) > 0) { off += p; last = off; tmp = substr(tmp, p + 1) }
        if (last > 0 && is_secret(name)) {
            val = substr(rest, 1, last - 1)
            if (val != "") { print head "<redacted:" length(val) " chars>" substr(rest, last); next }
        }
        print mask_urls(line); next
    }
    # XML: 名前と値が別の属性・要素の中にある形（libvirt の <qemu:env name="X" value="Y"/>、
    # LXC ドライバの <initenv name="X">Y</initenv>）。name の値で判定し、value か中身を伏せる
    if (index(line, "<") > 0 && line ~ /[ \t]name=/) {
        out = ""; rest = line; guard = 0
        while (match(rest, /<[^>]*>/) && ++guard < 100) {
            tag = substr(rest, RSTART, RLENGTH); pre = substr(rest, 1, RSTART - 1); rest = substr(rest, RSTART + RLENGTH)
            if (match(tag, /[ \t]name=("[^"]*"|\047[^\047]*\047)/)) {
                nv = substr(tag, RSTART + 7, RLENGTH - 8)
                if (is_secret(nv)) {
                    if (match(tag, /[ \t]value=("[^"]*"|\047[^\047]*\047)/)) {
                        vv = substr(tag, RSTART, RLENGTH); q = substr(vv, 8, 1); v = substr(vv, 9, length(vv) - 9)
                        if (v != "") tag = substr(tag, 1, RSTART - 1) substr(vv, 1, 8) "<redacted:" length(v) " chars>" q substr(tag, RSTART + RLENGTH)
                    }
                    if (tag !~ /\/>$/ && match(rest, /^[^<]+<\//)) {
                        v = substr(rest, 1, RLENGTH - 2)
                        rest = "<redacted:" length(v) " chars>" substr(rest, RLENGTH - 1)
                    }
                }
            }
            out = out pre tag
        }
        line = out rest
    }
    # XML: 属性と単純な要素
    if (index(line, "<") > 0) {
        out = ""; rest = line; guard = 0
        while (match(rest, /[A-Za-z_][-A-Za-z0-9_.:]*=(\047[^\047]*\047|"[^"]*")/) && ++guard < 100) {
            tok = substr(rest, RSTART, RLENGTH)
            name = tok; sub(/=.*$/, "", name)
            q = substr(tok, length(name) + 2, 1)
            val = substr(tok, length(name) + 3); val = substr(val, 1, length(val) - 1)
            if (is_secret(name) && val != "") tok = name "=" q "<redacted:" length(val) " chars>" q
            out = out substr(rest, 1, RSTART - 1) tok
            rest = substr(rest, RSTART + RLENGTH)
        }
        line = out rest
        if (match(line, /<[A-Za-z_][-A-Za-z0-9_.:]*>[^<]+<\//)) {
            tok = substr(line, RSTART, RLENGTH)
            name = tok; sub(/^</, "", name); sub(/>.*$/, "", name)
            if (is_secret(name)) {
                val = tok; sub(/^<[^>]*>/, "", val); sub(/<\/$/, "", val)
                line = substr(line, 1, RSTART - 1) "<" name "><redacted:" length(val) " chars></" substr(line, RSTART + RLENGTH)
            }
        }
        print mask_urls(line); next
    }
    # key = value / key: value
    if (match(line, /^[ \t]*[#;]*[ \t]*(- )?(export[ \t]+)?["\047]?[A-Za-z_][-A-Za-z0-9_.@]*["\047]?[ \t]*[=:]/)) {
        head = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH + 1)
        delim = substr(head, length(head), 1)
        if (delim == ":" && rest != "" && rest !~ /^[ \t]/) { print mask_urls(line); next }
        name = head
        sub(/[ \t]*[=:]$/, "", name); sub(/["\047]$/, "", name)
        sub(/^[ \t]*[#;]*[ \t]*(- )?(export[ \t]+)?["\047]?/, "", name)
        if (is_secret(name)) {
            if (delim == ":" && rest ~ /^[ \t]*([|>][-+]?)?[ \t]*$/) {
                print head " <redacted>"
                skip = 1; skip_indent = indent_of(line)
                next
            }
            match(rest, /^[ \t]*/); sp = substr(rest, 1, RLENGTH); val = substr(rest, RLENGTH + 1)
            if (val != "") { print head sp "<redacted:" length(val) " chars>"; next }
        }
        # 値の先頭が NAME= の形（LXC の lxc.environment = DB_PASSWORD=...）。NAME で判定する
        if (match(rest, /^[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*=/)) {
            ih = substr(rest, 1, RLENGTH); iv = substr(rest, RLENGTH + 1)
            iname = ih; sub(/^[ \t]*["\047]?/, "", iname); sub(/=$/, "", iname)
            if (is_secret(iname) && iv != "") { print head ih "<redacted:" length(iv) " chars>"; next }
        }
        print head mask_urls(rest); next
    }
    print mask_urls(line)
}'

redact_config() {
    if [[ "${LDIR_REDACT_SECRETS:-1}" != "1" ]]; then
        cat
        return 0
    fi
    awk -v re="${LDIR_SECRET_NAME_RE}" -v re2="${LDIR_CONFIG_EXTRA_RE}" "${LDIR_REDACT_CONFIG_AWK}"
}

# 1 行にまとまった JSON を、項目ごとの行に分ける（redact_config の前段）。
# 文字列の中の " はエスケープされているので、,"  {"  の位置で切っても値は壊れない。
# 改行は JSON の空白として有効なので、出力も JSON として読める。
ldir_json_split() {
    sed -e 's/,"/,\
"/g' -e 's/{"/{\
"/g'
}

# ---------------------------------------------------------------------------
# 秘密鍵・認証情報を除いたディレクトリのコピー
#
# copy_config_tree <コピー元> <コピー先> <除外の記録ファイル> [redact(0|1)]
#   - 名前で除外: secrets/ priv/ 配下、*.key *.pw *.keyring *.p12 *.pfx *.jks *.base64
#     authkey auth.json ssh_host_*_key master-key.aes
#   - 中身で除外: "PRIVATE KEY-----" または PuTTY の鍵形式を含むファイル
#     （名前に頼ると、HostKey で別名を付けた鍵を取りこぼす。v0.3.2 の既知の制約）
#   - シンボリックリンクはたどらず、記録だけ残す
#   - redact=1 のときは redact_config を通して書く（更新日時は元に合わせる）
# 除外したものはコピー先に一度も書かない。先にコピーしてから消すと、
# 出力先の媒体に削除済みの鍵が残るため（v0.3.2 までの ssh_host_*_key の扱い）。
ldir_is_secret_path() {
    case "/$1" in
        */secrets/*|*/priv/*|*.key|*.pw|*.keyring|*.p12|*.pfx|*.jks|*.base64|*/authkey|*/auth.json|*/ssh_host_*_key|*/master-key.aes|*/passwd.db|*sasldb*)
            return 0 ;;
    esac
    return 1
}

copy_config_tree() {
    local src="${1%/}" dst="${2%/}" report="$3" redact="${4:-0}"
    local keyfiles f rel resolved n_copied=0 n_excluded=0
    if [[ ! -d "$src" ]]; then
        log_debug "Not present: $src"
        return 1
    fi
    # コピー元そのものがリンクなら、root しか変えられないリンクのときだけたどる
    if [[ -L "$src" ]]; then
        resolved="$(run_limited 10 readlink -f -- "$src" 2>/dev/null)" || resolved=""
        if [[ -z "$resolved" ]] || ! _ldir_link_trusted "$src" "$resolved" dir; then
            _ldir_excluded "$report" symlink "${src} -> $(readlink -- "$src" 2>/dev/null)" "target: directory; not followed (${LDIR_UNTRUSTED:-the path} can be changed by a user other than root)"
            return 1
        fi
    fi
    ensure_dir "$dst" || { log_warn "Failed to create dir: $dst"; return 1; }
    ensure_dir "$(dirname "$report")"
    keyfiles="$(grep -rlE -- "${LDIR_PRIVATE_KEY_RE}" "$src" 2>/dev/null)"
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        rel="${f#"$src"/}"
        if [[ -L "$f" ]]; then
            _ldir_kind_into "$f"
            _ldir_excluded "$report" symlink "${f} -> $(readlink -- "$f" 2>/dev/null)" "target: ${LDIR_KIND}; not followed"
            continue
        fi
        [[ -f "$f" ]] || continue
        if ldir_is_secret_path "$rel" || [[ "${LDIR_NL}${keyfiles}${LDIR_NL}" == *"${LDIR_NL}${f}${LDIR_NL}"* ]]; then
            _ldir_excluded "$report" secret "$f" "private key or credential store"
            n_excluded=$((n_excluded + 1))
            continue
        fi
        ensure_dir "${dst}/$(dirname "$rel")" || continue
        if [[ "$redact" = "1" ]]; then
            # redact_config を通すと、末尾に改行の無いファイルには改行が 1 つ付く（写しは原本と
            # バイト単位では一致しない。仕様書 8.1 節）
            if redact_config < "$f" > "${dst}/${rel}" 2>/dev/null; then
                touch -r "$f" "${dst}/${rel}" 2>/dev/null
            else
                log_warn "Failed to copy: $f"; continue
            fi
        else
            # cp -a: 最後の要素をたどらない（-p だけだとリンクに差し替えられたときにたどる）
            cp -a -- "$f" "${dst}/${rel}" 2>/dev/null || { log_warn "Failed to copy: $f"; continue; }
        fi
        n_copied=$((n_copied + 1))
    done < <(find "${src}/" "${LDIR_FIND_PRUNE[@]}" \( -type f -o -type l \) -print 2>/dev/null)
    log_debug "copy_config_tree ${src}: ${n_copied} copied, ${n_excluded} secret file(s) excluded"
    return 0
}

# ---------------------------------------------------------------------------
# ログの収集期間と容量の上限
#
# ldir-collect.sh が ldir_resolve_log_settings で決め、環境変数でモジュールへ渡す。
#   LDIR_LOG_DAYS         30 | 60 | 90 | unlimited（full モードで未指定のとき）
#   LDIR_LOG_SINCE_EPOCH  これより前に更新されたログは取らない（0 = 無制限）
#   LDIR_LOG_SINCE        journalctl --since に渡す時刻（無制限なら空）
#   LDIR_LOG_MAX_MB       ログ群（認証ログ、Web サーバー等の種類）ごとの上限（0 = 無制限）
#   LDIR_LOG_CMD_TIMEOUT  journalctl / ausearch 1 回あたり、ログのコピー 1 回あたりの時間上限（秒、0 = 無制限）
#   LDIR_JOURNAL_MAX_MB   バイナリの journal（journal / journal_runtime の群）の上限。journald は既定で
#                         1 ファイル 128 MB まで育つので、ログ群の既定 100 MB では最新のファイルが必ず超える
LDIR_TAB=$'\t'
LDIR_LOG_DEFAULT_DAYS=30
LDIR_LOG_DEFAULT_MAX_MB=100
LDIR_LOG_DEFAULT_CMD_TIMEOUT=120
LDIR_JOURNAL_DEFAULT_MAX_MB=256

# ldir_resolve_log_settings [現在時刻の epoch 秒]
# 入力は LDIR_MODE と、利用者の指定（LDIR_LOG_DAYS / LDIR_LOG_MAX_MB。空 = 指定なし）。
# 不正な値なら LDIR_SETTINGS_ERROR に理由を入れて 1 を返す。
# shellcheck disable=SC2034  # LDIR_SETTINGS_ERROR は呼び出し側で使う
ldir_resolve_log_settings() {
    local now="${1:-}" epoch since
    [[ -n "$now" ]] || now="$(date +%s)"
    LDIR_SETTINGS_ERROR=""
    case "${LDIR_LOG_DAYS:-}" in
        30|60|90) ;;
        "")
            if [[ "${LDIR_MODE:-fast}" = "full" ]]; then LDIR_LOG_DAYS=unlimited; else LDIR_LOG_DAYS=${LDIR_LOG_DEFAULT_DAYS}; fi ;;
        *)
            LDIR_SETTINGS_ERROR="Invalid log period: '${LDIR_LOG_DAYS}' (--log-days / LDIR_LOG_DAYS accepts 30, 60 or 90)"
            return 1 ;;
    esac
    case "${LDIR_LOG_MAX_MB:-}" in
        "")
            if [[ "${LDIR_MODE:-fast}" = "full" ]]; then LDIR_LOG_MAX_MB=0; else LDIR_LOG_MAX_MB=${LDIR_LOG_DEFAULT_MAX_MB}; fi ;;
        *[!0-9]*|????????*)
            LDIR_SETTINGS_ERROR="Invalid log size cap: '${LDIR_LOG_MAX_MB}' (--log-max-mb / LDIR_LOG_MAX_MB accepts a whole number of MB; 0 = no cap)"
            return 1 ;;
        *)
            LDIR_LOG_MAX_MB=$((10#${LDIR_LOG_MAX_MB})) ;;
    esac
    case "${LDIR_JOURNAL_MAX_MB:-}" in
        "")
            if [[ "${LDIR_MODE:-fast}" = "full" ]]; then LDIR_JOURNAL_MAX_MB=0; else LDIR_JOURNAL_MAX_MB=${LDIR_JOURNAL_DEFAULT_MAX_MB}; fi ;;
        *[!0-9]*|????????*)
            LDIR_SETTINGS_ERROR="Invalid binary journal size cap: '${LDIR_JOURNAL_MAX_MB}' (--journal-max-mb / LDIR_JOURNAL_MAX_MB accepts a whole number of MB; 0 = no cap)"
            return 1 ;;
        *)
            LDIR_JOURNAL_MAX_MB=$((10#${LDIR_JOURNAL_MAX_MB})) ;;
    esac
    case "${LDIR_LOG_CMD_TIMEOUT:-}" in
        "")
            if [[ "${LDIR_MODE:-fast}" = "full" ]]; then LDIR_LOG_CMD_TIMEOUT=0; else LDIR_LOG_CMD_TIMEOUT=${LDIR_LOG_DEFAULT_CMD_TIMEOUT}; fi ;;
        *[!0-9]*)
            LDIR_SETTINGS_ERROR="Invalid LDIR_LOG_CMD_TIMEOUT: '${LDIR_LOG_CMD_TIMEOUT}' (seconds; 0 = no limit)"
            return 1 ;;
    esac
    if [[ "${LDIR_LOG_DAYS}" = "unlimited" ]]; then
        LDIR_LOG_SINCE_EPOCH=0
        LDIR_LOG_SINCE=""
    else
        epoch=$(( now - LDIR_LOG_DAYS * 86400 ))
        since="$(date -d "@${epoch}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" || since=""
        [[ -n "$since" ]] || since="${LDIR_LOG_DAYS} days ago"
        LDIR_LOG_SINCE_EPOCH=${epoch}
        LDIR_LOG_SINCE="${since}"
    fi
    export LDIR_LOG_DAYS LDIR_LOG_SINCE_EPOCH LDIR_LOG_SINCE LDIR_LOG_MAX_MB LDIR_LOG_CMD_TIMEOUT LDIR_JOURNAL_MAX_MB
    return 0
}

ldir_log_period_text() {
    if [[ "${LDIR_LOG_SINCE_EPOCH:-0}" = "0" ]]; then
        echo "unlimited"
    else
        echo "last ${LDIR_LOG_DAYS} days (modified since ${LDIR_LOG_SINCE} $(date '+%z'))"
    fi
}

ldir_log_cap_text() {
    if [[ "${LDIR_LOG_MAX_MB:-0}" = "0" ]]; then
        echo "unlimited"
    else
        echo "${LDIR_LOG_MAX_MB} MB per log group"
    fi
}

ldir_journal_cap_text() {
    if [[ "${LDIR_JOURNAL_MAX_MB:-0}" = "0" ]]; then
        echo "unlimited"
    else
        echo "${LDIR_JOURNAL_MAX_MB} MB per journal group"
    fi
}

ldir_human_size() {
    awk -v b="${1:-0}" 'BEGIN {
        if (b >= 1048576) printf "%.1f MB", b / 1048576
        else if (b >= 1024) printf "%.1f KB", b / 1024
        else printf "%d B", b }'
}

# ldir_log_report_init <レポートの置き場所>
# log_summary.txt（ログ群ごとの結果）と log_inventory.tsv（ファイルごとの判定）を用意する。
ldir_log_report_init() {
    local dir="$1"
    ensure_dir "$dir" || return 1
    if [[ ! -e "${dir}/log_inventory.tsv" ]]; then
        printf '# group\tdecision\tsize_bytes\tmtime\tpath (a newline or tab in a name is written as \\n or \\t)\n' > "${dir}/log_inventory.tsv"
    fi
    if [[ ! -e "${dir}/log_summary.txt" ]]; then
        cat > "${dir}/log_summary.txt" << EOF2
Log period : $(ldir_log_period_text)
Size cap   : $(ldir_log_cap_text); binary journal: $(ldir_journal_cap_text)
Selection  : files modified within the period are taken newest first until the cap is reached.
             Once a file does not fit, older files are not taken either, so what was kept
             is one contiguous, most recent range. Compressed files are copied as they are.
Per file   : log_inventory.tsv (decision: collected / over_cap / older_than_period /
             symlink_not_followed / copy_failed / not_present)

STATUS
  collected        files from the period were copied
  capped           the size cap was reached: the newest files were copied, older ones were NOT
  newest_over_cap  the newest file alone is larger than the cap: NOTHING of this group was copied
  none_in_period   log files of this kind exist, but none was modified within the period
  not_present      no log file of this kind exists on this host
  symlink_only     only symbolic links were found; they were not followed (e.g. -> /dev/stdout)
  copy_failed      some selected files could not be copied

EOF2
        printf '%-18s %-15s %s\n' "GROUP" "STATUS" "DETAIL" >> "${dir}/log_summary.txt"
    fi
}

_ldir_join_patterns() {
    local base="$1" p out=""
    shift
    for p in "$@"; do out="${out}${out:+ }${base}/${p}"; done
    echo "$out"
}

# 改行とタブを \n \t に置き換えた形を LDIR_ESC に入れる（一覧の 1 件 1 行を保つ）
_ldir_escape_into() {
    LDIR_ESC="${1//${LDIR_NL}/\\n}"
    LDIR_ESC="${LDIR_ESC//${LDIR_TAB}/\\t}"
}

# _ldir_log_copy_batch <ディレクトリ> <その実際の場所> <コピー先> <名前>...
# 1 つのディレクトリのログを cp 1 回でコピーする。cwd をそのディレクトリに固定し（cd -P と
# pwd -P で、調べたときと同じ場所かを確かめる）、相対名で cp -a する。途中のディレクトリを
# リンクに差し替えられても外を読まず、ファイルがリンクに差し替えられてもたどらない
# （サービスのユーザーが書けるログのディレクトリ: /var/log/mysql、/var/lib/pgsql 等）。
# 写した後、通常ファイルでないもの（差し替えられたリンク・FIFO 等）と、時間切れで途中までの
# ものは消す（呼び出し側が copy_failed と記録する）。
_ldir_log_copy_batch() (
    ldir="$1"; pdir="$2"; dest="$3"; rc=0; t="${LDIR_LOG_CMD_TIMEOUT:-0}"
    shift 3
    cd -P -- "$ldir" 2>/dev/null || exit 1
    if [[ "$(pwd -P)" != "$pdir" ]]; then
        log_warn "${LDIR_TAG}${ldir} was replaced while its logs were being copied (now $(pwd -P)); its files were not copied"
        exit 1
    fi
    ensure_dir "$dest" || exit 1
    printf './%s\0' "$@" | run_limited "$t" xargs -0 sh -c 'cp -a -- "$@" "$0"' "$dest" 2>/dev/null || rc=$?
    [[ ${rc} -eq 124 ]] && log_warn "${LDIR_TAG}copying the logs of ${ldir} stopped after ${t}s (LDIR_LOG_CMD_TIMEOUT); unfinished files are copy_failed"
    for n in "$@"; do
        if [[ -L "${dest}/${n}" || ( -e "${dest}/${n}" && ! -f "${dest}/${n}" ) ]]; then
            rm -rf -- "${dest:?}/${n}"
        elif [[ ${rc} -ne 0 && -e "${dest}/${n}" ]]; then
            # 時間切れ・出力先の満杯等で途中までのものは、取れたように見えるので残さない
            ss="$(stat -c %s -- "./${n}" 2>/dev/null)" || ss=0
            ds="$(stat -c %s -- "${dest}/${n}" 2>/dev/null)" || ds=0
            [[ "${ds}" -ge "${ss}" ]] || rm -f -- "${dest:?}/${n}"
        fi
    done
    exit 0
)

# collect_log_group <群の名前> <コピー元の基点> <コピー先の基点> <レポートの置き場所> <パターン>...
# パターンは基点からの相対の glob。ディレクトリに一致したら中を再帰的にたどる。
# コピー先には基点からの相対パスのまま置く。
#   例: collect_log_group auth /var/log "$LOG_DIR" "$LOG_DIR" 'auth.log*' 'secure*'
# 期間（LDIR_LOG_SINCE_EPOCH）より古いファイルは取らず、上限（LDIR_LOG_MAX_MB。呼び出し側が
# LDIR_LOG_GROUP_CAP_MB を付けて呼べばそれ）を超える分は新しい順に取ったところで打ち切る。
# 打ち切りは WARN。判定は全ファイル分を log_inventory.tsv に、群ごとの結果を log_summary.txt に残す。
# シンボリックリンクは記録だけ残し、たどらない。パターンに一致したディレクトリがリンクの場合は、
# root しか変えられないリンクのときだけたどる（/var/log は Ubuntu では syslog グループが書ける）。
# /dev/null へのリンクは、ログを捨てている所見として WARN。
# 結果は LDIR_LOG_GROUP_STATUS と LDIR_LOG_GROUP_COLLECTED（取ったファイル数）にも入れる。
collect_log_group() {
    local group="$1" src_base="${2%/}" dest_base="${3%/}" report="$4"; shift 4
    local cutoff="${LDIR_LOG_SINCE_EPOCH:-0}" cap_mb="${LDIR_LOG_GROUP_CAP_MB:-${LDIR_LOG_MAX_MB:-0}}"
    local cap tmp="${report}/.${group}.loggroup.tmp"
    local fmt="%Y${LDIR_TAB}%s${LDIR_TAB}%y${LDIR_TAB}%n" nofmt="%Y${LDIR_TAB}%s${LDIR_TAB}%y"
    local p m start lstart pstart g d size hm path real rel dir prev="" where t w i best ldir pdir
    local -a batch=() map_l=() map_p=()
    local -A odd=() seen_link=()
    cap=$(( cap_mb * 1048576 ))
    LDIR_LOG_GROUP_STATUS=""; LDIR_LOG_GROUP_COLLECTED=0

    ldir_log_report_init "$report" || { log_warn "Cannot write the log report in ${report}"; return 1; }
    where="${report#"${OUTPUT_DIR%/}"/}"
    : > "${tmp}.cand"; : > "${tmp}.links"; : > "${tmp}.odd"; : > "${tmp}.null"
    for p in "$@"; do
        # shellcheck disable=SC2086  # パターンの glob 展開が目的
        for m in "${src_base}"/${p}; do
            [[ -e "$m" || -L "$m" ]] || continue
            if [[ -L "$m" ]]; then
                t="$(run_limited 10 readlink -f -- "$m" 2>/dev/null)" || t=""
                if [[ -d "$m" && -n "$t" ]] && _ldir_link_trusted "$m" "$t" dir; then
                    start="${m%/}/"; lstart="$m"
                else
                    printf '%s\0' "$m" >> "${tmp}.links"
                    continue
                fi
            elif [[ -d "$m" ]]; then
                start="${m%/}/"; lstart="$m"
            else
                start="$m"; lstart="${m%/*}"
            fi
            pstart="$(cd -P -- "$lstart" 2>/dev/null && pwd -P)" || continue
            map_l+=("$lstart"); map_p+=("$pstart")
            # 改行・タブを含むパスは別に扱う（stat の出力を行で読むため。検証レポートの指摘 11）
            find "$start" "${LDIR_FIND_PRUNE[@]}" -type f ! -path "*${LDIR_NL}*" ! -path "*${LDIR_TAB}*" \
                -exec stat -c "$fmt" {} + >> "${tmp}.cand" 2>/dev/null
            find "$start" "${LDIR_FIND_PRUNE[@]}" \( -type l -o \( -type f \( -path "*${LDIR_NL}*" -o -path "*${LDIR_TAB}*" \) \) \) \
                -print0 >> "${tmp}.odd" 2>/dev/null
        done
    done
    while IFS= read -r -d '' w; do
        if [[ -L "$w" ]]; then
            printf '%s\0' "$w" >> "${tmp}.links"
            continue
        fi
        _ldir_escape_into "$w"
        odd["${LDIR_ESC}"]="$w"
        t="$(stat -c "$nofmt" -- "$w" 2>/dev/null)" || continue
        printf '%s\t%s\n' "$t" "${LDIR_ESC}" >> "${tmp}.cand"
    done < "${tmp}.odd"

    # 判定: 期間外 -> older_than_period、新しい順に積んで上限を超えたら以降すべて over_cap
    awk -F'\t' -v OFS='\t' '{ gsub(/\/\/+/, "/", $4); sub(/\.[0-9]+/, "", $3); print }' "${tmp}.cand" \
        | LC_ALL=C sort -t "${LDIR_TAB}" -k4,4 -u \
        | LC_ALL=C sort -t "${LDIR_TAB}" -k1,1nr -k4,4 \
        | awk -F'\t' -v OFS='\t' -v g="$group" -v cutoff="$cutoff" -v cap="$cap" '
            cutoff > 0 && $1 < cutoff { print g, "older_than_period", $2, $3, $4; next }
            full || (cap > 0 && used + $2 > cap) { full = 1; print g, "over_cap", $2, $3, $4; next }
            { used += $2; print g, "collect", $2, $3, $4 }' > "${tmp}.decided"

    # コピー: ディレクトリごとに cp を 1 回（ファイル数が多いタスクログ等で fork を抑える）
    while IFS="${LDIR_TAB}" read -r g d size hm path; do
        [[ "$d" = "collect" ]] || continue
        real="${odd[$path]:-$path}"
        rel="${real#"${src_base}"/}"
        if [[ "$rel" == */* ]]; then dir="${rel%/*}"; else dir="."; fi
        if [[ "$dir" != "$prev" && ${#batch[@]} -gt 0 ]]; then
            _ldir_log_flush
        fi
        prev="$dir"
        batch+=("${real##*/}")
    done < <(LC_ALL=C sort -t "${LDIR_TAB}" -k5,5 "${tmp}.decided")
    _ldir_log_flush

    # 確認: 「取った」と書く前に、実際にコピー先に通常ファイルとしてあることを見る
    {
        while IFS="${LDIR_TAB}" read -r g d size hm path; do
            if [[ "$d" = "collect" ]]; then
                real="${odd[$path]:-$path}"
                rel="${real#"${src_base}"/}"
                if [[ -f "${dest_base}/${rel}" && ! -L "${dest_base}/${rel}" ]]; then d="collected"; else d="copy_failed"; fi
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$g" "$d" "$size" "$hm" "$path"
        done < "${tmp}.decided"
        while IFS= read -r -d '' path; do
            [[ -n "$path" && -z "${seen_link[$path]:-}" ]] || continue
            seen_link["$path"]=1
            t="$(readlink -- "$path" 2>/dev/null)" || t="?"
            _ldir_escape_into "$path"; w="${LDIR_ESC}"
            _ldir_escape_into "$t"
            printf '%s\tsymlink_not_followed\t-\t-\t%s -> %s\n' "$group" "$w" "${LDIR_ESC}"
            if [[ "$t" == /dev/null || "$(run_limited 10 readlink -f -- "$path" 2>/dev/null)" == /dev/null ]]; then
                printf '%s\0' "$w" >> "${tmp}.null"
            fi
        done < "${tmp}.links"
    } > "${tmp}.final"
    if [[ -s "${tmp}.null" ]]; then
        while IFS= read -r -d '' w; do
            log_warn "[${group}] ${w} is a symbolic link to /dev/null: this log is being discarded (see ${where}/log_inventory.tsv)"
        done < "${tmp}.null"
    fi
    if [[ ! -s "${tmp}.final" ]]; then
        printf '%s\tnot_present\t-\t-\t%s\n' "$group" "$(_ldir_join_patterns "$src_base" "$@")" > "${tmp}.final"
    fi
    cat "${tmp}.final" >> "${report}/log_inventory.tsv"

    # 群ごとの集計（fo: 何も取れなかったときの、上限を超えた最新のファイルのサイズ）
    local stats n_col b_col n_cap b_cap n_old n_fail n_link fo status detail
    stats="$(awk -F'\t' '
        $2 == "collected"            { nc++; bc += $3 }
        $2 == "over_cap"             { if (!no) fo = $3; no++; bo += $3 }
        $2 == "older_than_period"    { np++ }
        $2 == "copy_failed"          { nf++ }
        $2 == "symlink_not_followed" { nl++ }
        END { printf "%d %d %d %d %d %d %d %d", nc, bc, no, bo, np, nf, nl, fo }' "${tmp}.final")"
    read -r n_col b_col n_cap b_cap n_old n_fail n_link fo <<< "$stats"
    rm -f "${tmp}.cand" "${tmp}.links" "${tmp}.odd" "${tmp}.null" "${tmp}.decided" "${tmp}.final"

    detail="${n_col} file(s) collected ($(ldir_human_size "${b_col}"))"
    [[ ${n_cap} -gt 0 ]] && detail="${detail}; ${n_cap} file(s) over the cap NOT collected ($(ldir_human_size "${b_cap}"))"
    [[ ${n_old} -gt 0 ]] && detail="${detail}; ${n_old} older file(s) outside the period"
    [[ ${n_fail} -gt 0 ]] && detail="${detail}; ${n_fail} file(s) failed to copy"
    [[ ${n_link} -gt 0 ]] && detail="${detail}; ${n_link} symlink(s) not followed"
    if [[ ${n_fail} -gt 0 ]]; then
        status="copy_failed"
        log_warn "[${group}] ${n_fail} log file(s) could not be copied (see ${where}/log_inventory.tsv, decision copy_failed)"
    elif [[ ${n_cap} -gt 0 && ${n_col} -eq 0 ]]; then
        status="newest_over_cap"
        log_warn "[${group}] the newest file ($(ldir_human_size "${fo}")) is larger than the log size cap of ${cap_mb} MB: nothing of this group was collected; ${n_cap} file(s) ($(ldir_human_size "${b_cap}")) NOT collected (see ${where}/log_inventory.tsv, decision over_cap; raise the cap or use 0 for no cap)"
    elif [[ ${n_cap} -gt 0 ]]; then
        status="capped"
        log_warn "[${group}] log size cap of ${cap_mb} MB reached: ${n_cap} older file(s) ($(ldir_human_size "${b_cap}")) NOT collected (see ${where}/log_inventory.tsv, decision over_cap; raise the cap or use 0 for no cap)"
    elif [[ ${n_col} -gt 0 ]]; then
        status="collected"
    elif [[ ${n_old} -gt 0 ]]; then
        status="none_in_period"
        log_info "[${group}] log files exist but none was modified in the period ($(ldir_log_period_text)); see ${where}/log_inventory.tsv"
    elif [[ ${n_link} -gt 0 ]]; then
        status="symlink_only"
        log_debug "[${group}] only symlinks found (not followed)"
    else
        status="not_present"
        detail="no file matching: $(_ldir_join_patterns "$src_base" "$@")"
        log_debug "[${group}] no log files present"
    fi
    printf '%-18s %-15s %s\n' "$group" "$status" "$detail" >> "${report}/log_summary.txt"
    # shellcheck disable=SC2034  # 呼び出し側（60_logs）が使う
    LDIR_LOG_GROUP_STATUS="$status"
    # shellcheck disable=SC2034
    LDIR_LOG_GROUP_COLLECTED=${n_col}
    return 0
}

# collect_log_group の中から呼ぶ: 溜めた 1 ディレクトリ分（batch）をコピーする
# （呼び出し元の local 変数 batch prev src_base dest_base map_l map_p を使う）
_ldir_log_flush() {
    local ldir pdir="" best=-1 i
    [[ ${#batch[@]} -gt 0 ]] || return 0
    if [[ "$prev" = "." ]]; then ldir="${src_base}"; else ldir="${src_base}/${prev}"; fi
    # 調べたときの実際の場所（一番長く一致する起点から求める）
    for i in "${!map_l[@]}"; do
        if [[ "$ldir" == "${map_l[$i]}" || "$ldir" == "${map_l[$i]}/"* ]] && [[ ${#map_l[$i]} -gt ${best} ]]; then
            best=${#map_l[$i]}
            pdir="${map_p[$i]}${ldir#"${map_l[$i]}"}"
        fi
    done
    [[ -n "$pdir" ]] && _ldir_log_copy_batch "$ldir" "$pdir" "${dest_base}/${prev}" "${batch[@]}"
    batch=()
}

# copy_config_file <コピー元> <コピー先> <除外の記録ファイル>
# 1 ファイルを redact_config を通して写す（更新日時は元に合わせる）。root しか書けない場所の
# 設定ファイル用。ユーザーが書ける場所のファイルには ldir_copy_user_files を使う。
# 秘密鍵を含むファイルは書かずに、除外の記録だけ残す。リンクは root しか変えられないものだけたどる。
copy_config_file() {
    local src="$1" dst="$2" report="$3" resolved
    if [[ ! -e "$src" ]]; then
        log_debug "Not present: $src"
        return 1
    fi
    if [[ -L "$src" ]]; then
        resolved="$(run_limited 10 readlink -f -- "$src" 2>/dev/null)" || resolved=""
        if [[ -z "$resolved" ]] || ! _ldir_link_trusted "$src" "$resolved" file; then
            _ldir_kind_into "$src"
            _ldir_excluded "$report" symlink "${src} -> $(readlink -- "$src" 2>/dev/null)" "target: ${LDIR_KIND}; not followed (${LDIR_UNTRUSTED:-the path} can be changed by a user other than root)"
            return 1
        fi
    fi
    [[ -f "$src" ]] || return 1
    if ldir_is_secret_path "${src#/}" || run_limited 30 grep -qE -- "${LDIR_PRIVATE_KEY_RE}" "$src" 2>/dev/null; then
        _ldir_excluded "$report" secret "$src" "private key or credential store"
        return 1
    fi
    ensure_dir "$(dirname "$dst")" || { log_warn "Failed to create dir for: $dst"; return 1; }
    if redact_config < "$src" > "$dst" 2>/dev/null; then
        touch -r "$src" "$dst" 2>/dev/null
        return 0
    fi
    log_warn "Failed to copy: $src"
    return 1
}

# ---------------------------------------------------------------------------
# ユーザーが書ける場所（ホーム等）からのコピー: シンボリックリンクをたどらない
#
# 対象ホストの一般ユーザーは、自分のホームにリンク・FIFO・デバイス・ハードリンクを置ける。
# root で動く収集がそれをたどると、読めないはずのファイル（root やホストの秘密鍵）が収集物に
# 入り、FIFO で止まり、/dev/zero で出力先が埋まる。逆に、痕跡消しの .bash_history -> /dev/null は
# 所見として残らなかった（v0.4.0 の第三者検証の指摘 1・2・7）。ここでは:
#   - 基点（ホーム）より下では、途中のディレクトリを含めてリンクをたどらない。リンク・リンク先・
#     リンク先の種別（通常ファイル / ディレクトリ / デバイス / FIFO / 存在しない）を記録するだけ
#   - 通常ファイルだけをコピーする。FIFO・デバイス・ソケットは開かない（判定は -L を先に見る）
#   - cwd をそのディレクトリに固定し（cd -P のあと pwd -P が調べた場所と同じかを確かめる）、
#     相対名だけで扱う。途中のディレクトリをリンクに差し替えられても、固定した場所の外は読まない
#   - コピーは cp -a（最後の要素がリンクに差し替えられても、たどらずリンクとして写す）。
#     写した後に通常ファイルかを確かめ、違えば消して記録する
#   - 二重の守り: 中身が秘密鍵のもの・名前が鍵の置き場のもの（ldir_is_secret_path）は書かない。
#     リンクをたどらない対策が将来壊れても、これで止まる
#   - 別の持ち主のファイルへのハードリンク（fs.protected_hardlinks が無効なら作れる）は書かない
#   - 1 ファイルのサイズの上限（LDIR_USER_FILE_MAX_MB）と、1 回の呼び出しの時間の上限
#     （LDIR_USER_COPY_TIMEOUT）。中の各コマンドには残り時間を run_limited で付ける
#   - 書かなかったものは report（各モジュールの excluded_files.txt）に理由とともに残す
#   - 所見の WARN: /dev/null へのリンク（書いたものが捨てられる）、FIFO・デバイス・ソケットへの
#     リンク、ホームの持ち主が読めないファイルへのリンク（root で動くツールへの罠）、
#     別の持ち主のファイルへのハードリンク。1 ファイルずつのコピーでは、上限超え・秘密鍵・
#     通常ファイルでないもの・コピーの失敗も WARN（ディレクトリのコピーでは記録のみ・件数を WARN）
LDIR_USER_DEFAULT_FILE_MAX_MB=100
declare -A _LDIR_NOTED=()

# ldir_resolve_user_copy_settings: LDIR_USER_FILE_MAX_MB と LDIR_USER_COPY_TIMEOUT を検証して決める。
# 不正な値なら LDIR_SETTINGS_ERROR に理由を入れて 1。
# shellcheck disable=SC2034  # LDIR_SETTINGS_ERROR は呼び出し側で使う
ldir_resolve_user_copy_settings() {
    LDIR_SETTINGS_ERROR=""
    case "${LDIR_USER_FILE_MAX_MB:-}" in
        "") LDIR_USER_FILE_MAX_MB=${LDIR_USER_DEFAULT_FILE_MAX_MB} ;;
        *[!0-9]*|????????*)
            LDIR_SETTINGS_ERROR="Invalid LDIR_USER_FILE_MAX_MB: '${LDIR_USER_FILE_MAX_MB}' (a whole number of MB; 0 = no cap)"
            return 1 ;;
        *) LDIR_USER_FILE_MAX_MB=$((10#${LDIR_USER_FILE_MAX_MB})) ;;
    esac
    case "${LDIR_USER_COPY_TIMEOUT:-}" in
        "") if [[ "${LDIR_MODE:-fast}" = "full" ]]; then LDIR_USER_COPY_TIMEOUT=600; else LDIR_USER_COPY_TIMEOUT=60; fi ;;
        *[!0-9]*|??????*)
            LDIR_SETTINGS_ERROR="Invalid LDIR_USER_COPY_TIMEOUT: '${LDIR_USER_COPY_TIMEOUT}' (seconds; 0 = no limit)"
            return 1 ;;
        *) LDIR_USER_COPY_TIMEOUT=$((10#${LDIR_USER_COPY_TIMEOUT})) ;;
    esac
    export LDIR_USER_FILE_MAX_MB LDIR_USER_COPY_TIMEOUT
    return 0
}

# 単体で実行されたモジュール向け: 値が無い・不正なら既定値にする
_ldir_user_limits() {
    ldir_resolve_user_copy_settings 2>/dev/null && return 0
    LDIR_USER_FILE_MAX_MB=${LDIR_USER_DEFAULT_FILE_MAX_MB}
    LDIR_USER_COPY_TIMEOUT=60
}

# 時間の上限: 期限（SECONDS の値、0 = 無し）と、残り秒数（LDIR_REM。0 = 無制限、-1 = 期限切れ）
_ldir_deadline_into() {
    if [[ "${LDIR_USER_COPY_TIMEOUT:-0}" = 0 ]]; then LDIR_DEADLINE=0; else LDIR_DEADLINE=$(( SECONDS + LDIR_USER_COPY_TIMEOUT )); fi
}
_ldir_remaining_into() {
    if [[ "$1" = 0 ]]; then LDIR_REM=0
    elif (( $1 - SECONDS > 0 )); then LDIR_REM=$(( $1 - SECONDS ))
    else LDIR_REM=-1
    fi
}

# _ldir_readable_by <パス> <uid> <種別>: その uid のユーザーが読めそうなら 0（所有者と other の
# 権限だけで見る。グループは見ない）。root は常に 0
_ldir_readable_by() {
    local s u m d need=4
    [[ "$2" = 0 || -z "$2" ]] && return 0
    s="$(stat -L -c '%u %a' -- "$1" 2>/dev/null)" || return 0
    u="${s%% *}"; m="${s#* }"
    [[ "$3" == directory ]] && need=5
    if [[ "$u" == "$2" ]]; then d="${m: -3:1}"; else d="${m: -1}"; fi
    (( (d & need) == need ))
}

# _ldir_note_link <記録> <表示するパス> <調べるパス> <基点> <基点の持ち主の uid>
# たどらなかったリンクを、リンク先とリンク先の種別とともに記録する。所見なら WARN。
_ldir_note_link() {
    local report="$1" shown="$2" acc="$3" base="$4" buid="$5" target resolved kind detail warn=""
    target="$(readlink -- "$acc" 2>/dev/null)" || target="?"
    resolved="$(run_limited 10 readlink -f -- "$acc" 2>/dev/null)" || resolved=""
    _ldir_kind_into "$acc"; kind="${LDIR_KIND}"
    detail="target: ${kind}"
    [[ -n "$resolved" && "$resolved" != "$target" ]] && detail="${detail} (${resolved})"
    if [[ "$resolved" == /dev/null || "$target" == /dev/null ]]; then
        warn="is a symbolic link to /dev/null: what is written to it is discarded"
    elif [[ "$kind" == fifo || "$kind" == socket || "$kind" == *device ]]; then
        warn="is a symbolic link to a ${kind} (${resolved:-${target}}); reading it could block or never end"
    elif [[ "$kind" != missing && -n "$resolved" ]] && ! _ldir_readable_by "$resolved" "$buid" "$kind"; then
        warn="is a symbolic link to ${resolved}, which the owner of ${base} cannot read (a trap for tools running as root)"
    fi
    _ldir_excluded "$report" symlink "${shown} -> ${target}" "${detail}; not followed"
    [[ -n "$warn" ]] && log_warn "${LDIR_TAG}${shown} ${warn}; not followed (see $(_ldir_shown "$report"))"
    return 0
}

# _ldir_nf_check_dir <基点（実際の場所）> <基点からの相対のディレクトリ> <記録> <uid>
# 途中のどの段もリンクでない実ディレクトリなら 0。リンクがあれば記録して 1（同じリンクは 1 度だけ）
_ldir_nf_check_dir() {
    local bp="$1" rest="$2" report="$3" buid="$4" p c
    p="${bp%/}"
    while [[ -n "$rest" ]]; do
        c="${rest%%/*}"
        if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
        [[ -n "$c" && "$c" != "." ]] || continue
        p="${p}/${c}"
        if [[ -L "$p" ]]; then
            if [[ -z "${_LDIR_NOTED[$p]:-}" ]]; then
                _LDIR_NOTED["$p"]=1
                _ldir_note_link "$report" "$p" "$p" "$bp" "$buid"
            fi
            return 1
        fi
        [[ -d "$p" ]] || return 1
    done
    return 0
}

# _ldir_nf_copy_here <dir> <記録> <基点> <uid> <期限> <ホームのラベル> <single|tree> <コピー先のディレクトリ（tree）> <名前> <コピー先>...
# cwd が dir に固定された状態（サブシェルの中）で呼ぶ。名前は dir からの相対
_ldir_nf_copy_here() {
    local dir="$1" report="$2" base="$3" buid="$4" deadline="$5" hl="$6" mode="$7" dstd="$8"
    shift 8
    local n i shown st sz nl uid found rc key dst lab capb=$(( ${LDIR_USER_FILE_MAX_MB:-0} * 1048576 ))
    local n_cap=0 n_fail=0 single=0
    local -a names=() dsts=() cn=() cdst=() ok=() okd=() oks=() sl=() batchn=() batchs=()
    [[ "$mode" = single ]] && single=1
    while [[ $# -ge 2 ]]; do names+=("$1"); dsts+=("$2"); shift 2; done
    for i in "${!names[@]}"; do
        n="${names[$i]}"; shown="${dir%/}/${n}"
        if [[ -L "./${n}" ]]; then
            _ldir_note_link "$report" "$shown" "./${n}" "$base" "$buid"
            continue
        fi
        [[ -e "./${n}" ]] || continue
        if [[ ! -f "./${n}" ]]; then
            _ldir_kind_into "./${n}"
            [[ "${LDIR_KIND}" = directory && ${single} -eq 0 ]] && continue
            _ldir_excluded "$report" not_regular "$shown" "${LDIR_KIND}; not opened"
            [[ ${single} -eq 1 ]] && log_warn "${LDIR_TAG}${shown} is a ${LDIR_KIND}, not a regular file; not opened (see $(_ldir_shown "$report"))"
            continue
        fi
        if ldir_is_secret_path "${shown#/}"; then
            _ldir_excluded "$report" secret "$shown" "name of a key or credential store"
            continue
        fi
        cn+=("$n"); cdst+=("${dsts[$i]}")
    done
    [[ ${#cn[@]} -gt 0 ]] || return 0
    # サイズ・リンク数・持ち主（stat 1 回。数が合わなければ 1 件ずつ）
    st="$(stat -c '%s %h %u' -- "${cn[@]/#/./}" 2>/dev/null)"
    mapfile -t sl <<< "$st"
    for i in "${!cn[@]}"; do
        n="${cn[$i]}"; shown="${dir%/}/${n}"
        if [[ ${#sl[@]} -eq ${#cn[@]} ]]; then
            read -r sz nl uid <<< "${sl[$i]}"
        else
            read -r sz nl uid <<< "$(stat -c '%s %h %u' -- "./${n}" 2>/dev/null)"
        fi
        [[ -n "${sz:-}" ]] || continue
        if (( capb > 0 && sz > capb )); then
            _ldir_excluded "$report" over_size_cap "$shown" "${sz} bytes; the cap is ${LDIR_USER_FILE_MAX_MB} MB (LDIR_USER_FILE_MAX_MB)"
            n_cap=$((n_cap + 1))
            [[ ${single} -eq 1 ]] && log_warn "${LDIR_TAG}${shown} ($(ldir_human_size "${sz}")) is larger than the cap of ${LDIR_USER_FILE_MAX_MB} MB for files from home directories; not copied (see $(_ldir_shown "$report"))"
            continue
        fi
        if (( nl > 1 )) && [[ -n "$buid" && "$uid" != "$buid" ]]; then
            _ldir_excluded "$report" hardlink_other_owner "$shown" "owner uid ${uid}, ${nl} links; ${base} belongs to uid ${buid}"
            log_warn "${LDIR_TAG}${shown} is a hard link to a file owned by uid ${uid} (${nl} links), not by the owner of ${base}; not copied (see $(_ldir_shown "$report"))"
            continue
        fi
        ok+=("$n"); okd+=("${cdst[$i]}"); oks+=("$sz")
    done
    [[ ${#ok[@]} -gt 0 ]] || return 0
    # 秘密鍵の中身（改行を含む名前は 1 件ずつ、それ以外はまとめて grep -l）
    _ldir_remaining_into "$deadline"
    if [[ "${LDIR_REM}" = -1 ]]; then
        for n in "${ok[@]}"; do _ldir_excluded "$report" timeout "${dir%/}/${n}" "time limit reached before the copy (LDIR_USER_COPY_TIMEOUT=${LDIR_USER_COPY_TIMEOUT}s)"; done
        log_warn "${LDIR_TAG}time limit of ${LDIR_USER_COPY_TIMEOUT}s reached in ${dir}; ${#ok[@]} file(s) not copied (see $(_ldir_shown "$report"))"
        return 0
    fi
    rc=0
    found="$(for n in "${ok[@]}"; do [[ "$n" == *"${LDIR_NL}"* ]] || printf './%s\0' "$n"; done \
        | run_limited "${LDIR_REM}" xargs -0 grep -lE -- "${LDIR_PRIVATE_KEY_RE}" 2>/dev/null)" || rc=$?
    if [[ ${rc} -eq 124 ]]; then
        for n in "${ok[@]}"; do _ldir_excluded "$report" timeout "${dir%/}/${n}" "the private-key check did not finish within the time limit; not copied"; done
        log_warn "${LDIR_TAG}the private-key check in ${dir} hit the time limit; ${#ok[@]} file(s) not copied (see $(_ldir_shown "$report"))"
        return 0
    fi
    for i in "${!ok[@]}"; do
        n="${ok[$i]}"; shown="${dir%/}/${n}"; key=0
        if [[ "$n" == *"${LDIR_NL}"* ]]; then
            run_limited "${LDIR_REM}" grep -qE -- "${LDIR_PRIVATE_KEY_RE}" "./${n}" 2>/dev/null && key=1
        elif [[ "${LDIR_NL}${found}${LDIR_NL}" == *"${LDIR_NL}./${n}${LDIR_NL}"* ]]; then
            key=1
        fi
        if [[ ${key} -eq 1 ]]; then
            _ldir_excluded "$report" secret "$shown" "private key content (SPECIFICATION 8.2)"
            [[ ${single} -eq 1 ]] && log_warn "${LDIR_TAG}${shown} contains a private key; not copied (see $(_ldir_shown "$report"))"
            continue
        fi
        dst="${okd[$i]}"
        if [[ "$dst" == *"{label}"* ]]; then
            lab="$(ldir_item_label "$hl" "./${n}")"
            dst="${dst//\{label\}/${lab}}"
        fi
        if [[ ${single} -eq 1 ]]; then
            ensure_dir "$(dirname -- "$dst")" || continue
            _ldir_remaining_into "$deadline"
            rc=0
            if [[ "${LDIR_REM}" = -1 ]]; then rc=124; else run_limited "${LDIR_REM}" cp -a -- "./${n}" "$dst" 2>/dev/null || rc=$?; fi
            _ldir_nf_verify "$shown" "$dst" "${oks[$i]}" "$rc" "$report" 1 || n_fail=$((n_fail + 1))
        else
            batchn+=("$n"); batchs+=("${oks[$i]}")
        fi
    done
    if [[ ${#batchn[@]} -gt 0 ]]; then
        ensure_dir "$dstd" || return 0
        _ldir_remaining_into "$deadline"
        rc=0
        if [[ "${LDIR_REM}" = -1 ]]; then
            rc=124
        else
            printf './%s\0' "${batchn[@]}" | run_limited "${LDIR_REM}" xargs -0 sh -c 'cp -a -- "$@" "$0"' "$dstd" 2>/dev/null || rc=$?
        fi
        for i in "${!batchn[@]}"; do
            n="${batchn[$i]}"
            _ldir_nf_verify "${dir%/}/${n}" "${dstd}/${n}" "${batchs[$i]}" "$rc" "$report" 0 || n_fail=$((n_fail + 1))
        done
    fi
    if [[ ${single} -eq 0 && $((n_cap + n_fail)) -gt 0 ]]; then
        log_warn "${LDIR_TAG}${dir}: ${n_cap} file(s) over the size cap and ${n_fail} file(s) not copied (see $(_ldir_shown "$report"))"
    fi
    return 0
}

# _ldir_nf_verify <表示するパス> <コピー先> <元のサイズ> <cp の終了コード> <記録> <WARN(1|0)>
# 写したものが通常ファイルかを確かめる。差し替えられて写ったリンク等や、時間切れで途中までの
# ものは消して記録する。
_ldir_nf_verify() {
    local shown="$1" dst="$2" size="$3" rc="$4" report="$5" warn="$6" ds
    if [[ -L "$dst" || ( -e "$dst" && ! -f "$dst" ) ]]; then
        _ldir_kind_into "$dst"
        rm -rf -- "$dst"
        _ldir_excluded "$report" changed_during_copy "$shown" "was replaced while being copied; the copy was removed"
        log_warn "${LDIR_TAG}${shown} was replaced while being copied; the copy was removed (see $(_ldir_shown "$report"))"
        return 1
    fi
    if [[ "$rc" != 0 && -f "$dst" ]]; then
        # まとめてコピーした中の 1 件の失敗・出力先の満杯: 途中までのものは残さない
        ds="$(stat -c %s -- "$dst" 2>/dev/null)" || ds=0
        [[ "$ds" -ge "$size" ]] && return 0
        rm -f -- "$dst"
    fi
    if [[ "$rc" = 124 ]]; then
        _ldir_excluded "$report" timeout "$shown" "copy stopped at the time limit (LDIR_USER_COPY_TIMEOUT=${LDIR_USER_COPY_TIMEOUT}s); nothing kept"
        [[ "$warn" = 1 ]] && log_warn "${LDIR_TAG}copying ${shown} stopped at the time limit of ${LDIR_USER_COPY_TIMEOUT}s; not copied (see $(_ldir_shown "$report"))"
        return 1
    fi
    if [[ ! -f "$dst" ]]; then
        _ldir_excluded "$report" copy_failed "$shown" "cp exit ${rc}"
        [[ "$warn" = 1 ]] && log_warn "Failed to copy: ${shown}"
        return 1
    fi
    return 0
}

# _ldir_nf_files_in <基点> <相対のディレクトリ> <記録> <uid> <期限> <ラベル> <名前> <コピー先>...
_ldir_nf_files_in() {
    local bp="$1" rd="$2" report="$3" buid="$4" deadline="$5" hl="$6" dir
    shift 6
    local -a present=()
    if [[ -n "$rd" ]]; then dir="${bp%/}/${rd}"; else dir="$bp"; fi
    _ldir_nf_check_dir "$bp" "$rd" "$report" "$buid" || return 0
    while [[ $# -ge 2 ]]; do
        [[ -e "${dir%/}/$1" || -L "${dir%/}/$1" ]] && present+=("$1" "$2")
        shift 2
    done
    [[ ${#present[@]} -gt 0 ]] || return 0
    (
        cd -P -- "$dir" 2>/dev/null || exit 0
        if [[ "$(pwd -P)" != "$dir" ]]; then
            _ldir_excluded "$report" changed_during_copy "$dir" "the directory was replaced while being read (now $(pwd -P)); nothing copied from it"
            log_warn "${LDIR_TAG}${dir} was replaced while being read; nothing copied from it (see $(_ldir_shown "$report"))"
            exit 0
        fi
        _ldir_nf_copy_here "$dir" "$report" "$bp" "$buid" "$deadline" "$hl" single "" "${present[@]}"
    )
    return 0
}

# ldir_copy_user_files <基点> <ラベル> <記録> <相対パス> <コピー先> [<相対パス> <コピー先>]...
# 基点（ホーム等）の下のファイルを、リンクをたどらずにコピーする（上の説明を参照）。
# コピー先の {label} は ldir_item_label で置き換える。無いものは何もしない（記録もしない）。
ldir_copy_user_files() {
    local base="$1" hl="$2" report="$3" bp buid rel dst rd prev=""
    shift 3
    local -a group=()
    _ldir_user_limits
    bp="$(cd -P -- "$base" 2>/dev/null && pwd -P)" || return 0
    buid="$(stat -c %u -- "$bp" 2>/dev/null)" || buid=""
    _ldir_deadline_into
    while [[ $# -ge 2 ]]; do
        rel="${1#/}"; dst="$2"; shift 2
        case "/${rel}/" in */../*|*/./*) continue ;; esac
        rd=""; [[ "$rel" == */* ]] && rd="${rel%/*}"
        if [[ ${#group[@]} -gt 0 && "$rd" != "$prev" ]]; then
            _ldir_nf_files_in "$bp" "$prev" "$report" "$buid" "${LDIR_DEADLINE}" "$hl" "${group[@]}"
            group=()
        fi
        prev="$rd"
        group+=("${rel##*/}" "$dst")
    done
    [[ ${#group[@]} -gt 0 ]] && _ldir_nf_files_in "$bp" "$prev" "$report" "$buid" "${LDIR_DEADLINE}" "$hl" "${group[@]}"
    return 0
}

# _ldir_nf_tree_step <ディレクトリ> <コピー先> <記録> <基点> <uid> <期限> <ラベル>
# 1 つのディレクトリの通常ファイルをコピーし、サブディレクトリの名前を fd 3 に NUL 区切りで出す
_ldir_nf_tree_step() (
    dir="$1"; dstd="$2"; report="$3"; base="$4"; buid="$5"; deadline="$6"; hl="$7"
    pairs=()
    cd -P -- "$dir" 2>/dev/null || exit 0
    if [[ "$(pwd -P)" != "$dir" ]]; then
        _ldir_excluded "$report" changed_during_copy "$dir" "the directory was replaced while being read (now $(pwd -P)); nothing copied from it"
        log_warn "${LDIR_TAG}${dir} was replaced while being read; nothing copied from it (see $(_ldir_shown "$report"))"
        exit 0
    fi
    shopt -s nullglob dotglob
    for n in *; do
        if [[ ! -L "./${n}" && -d "./${n}" ]]; then
            printf '%s\0' "$n" >&3
            continue
        fi
        pairs+=("$n" "${dstd}/${n}")
    done
    ensure_dir "$dstd"
    [[ ${#pairs[@]} -gt 0 ]] && _ldir_nf_copy_here "$dir" "$report" "$base" "$buid" "$deadline" "$hl" tree "$dstd" "${pairs[@]}"
    exit 0
)

# ldir_copy_user_tree <基点> <ラベル> <記録> <相対のディレクトリ> <コピー先のディレクトリ>
# 基点の下のディレクトリを、リンクをたどらずに丸ごとコピーする（通常ファイルとディレクトリだけ）。
# コピー先の {label} は、そのディレクトリの持ち主で ldir_item_label を使って置き換える。
ldir_copy_user_tree() {
    local base="$1" hl="$2" report="$3" rel="${4#/}" dst="${5%/}" bp buid root sub s qi=0
    local -a q=("")
    rel="${rel%/}"
    _ldir_user_limits
    bp="$(cd -P -- "$base" 2>/dev/null && pwd -P)" || return 0
    buid="$(stat -c %u -- "$bp" 2>/dev/null)" || buid=""
    _ldir_deadline_into
    _ldir_nf_check_dir "$bp" "$rel" "$report" "$buid" || return 0
    root="${bp%/}/${rel}"
    [[ -d "$root" ]] || return 0
    [[ "$dst" == *"{label}"* ]] && dst="${dst//\{label\}/$(ldir_item_label "$hl" "$root")}"
    {
        while (( qi < ${#q[@]} )); do
            sub="${q[qi]}"; qi=$((qi + 1))
            _ldir_remaining_into "${LDIR_DEADLINE}"
            if [[ "${LDIR_REM}" = -1 ]]; then
                _ldir_excluded "$report" timeout "${root}${sub:+/${sub}}" "time limit reached (LDIR_USER_COPY_TIMEOUT=${LDIR_USER_COPY_TIMEOUT}s): this directory and the $(( ${#q[@]} - qi )) not yet examined were not copied"
                log_warn "${LDIR_TAG}copying ${root} stopped at the time limit of ${LDIR_USER_COPY_TIMEOUT}s; the rest is not copied (see $(_ldir_shown "$report"))"
                break
            fi
            while IFS= read -r -d '' s; do
                q+=("${sub:+${sub}/}${s}")
            done < <(_ldir_nf_tree_step "${root}${sub:+/${sub}}" "${dst}${sub:+/${sub}}" "$report" "$bp" "$buid" "${LDIR_DEADLINE}" "$hl" 3>&1 >&4)
        done
    } 4>&1
    return 0
}
