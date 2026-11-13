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

    if [[ ! -e "$src" && ! -L "$src" ]]; then
        log_debug "Not present: $src"
        return 1
    fi

    # 単体のシンボリックリンク（/etc/resolv.conf -> ../run/... 等）は、リンクではなく
    # 指す先の内容を取る。cp -a はリンクのまま写すため、収集物の中では宙に浮いた
    # リンクになり、ハッシュ一覧にも載らない（「取れたように見えて取れていない」）。
    # リンクであったこと自体も所見になり得るので、宛先の _symlinks.txt に記録する。
    if [[ -L "$src" && "$src" != */ ]]; then
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

# safe_copy から呼ぶ: 単体のシンボリックリンクを、指す先の内容でコピーする。
_ldir_copy_symlink() {
    local src="$1" dst="$2" target dst_path note_dir
    target="$(readlink "$src" 2>/dev/null)" || target="?"
    if [[ -d "$dst" || "$dst" == */ ]]; then
        dst_path="${dst%/}/${src##*/}"
    else
        dst_path="$dst"
    fi
    note_dir="$(dirname "$dst_path")"
    ensure_dir "$note_dir" || { log_warn "Failed to create dir: $note_dir"; return 1; }
    if [[ ! -e "$src" ]]; then
        echo "${src} -> ${target}: dangling link (target missing); nothing copied" >> "${note_dir}/_symlinks.txt"
        log_debug "Dangling symlink: ${src} -> ${target}"
        return 1
    fi
    if [[ -d "$src" ]]; then
        ensure_dir "$dst_path" && cp -a "${src}/." "${dst_path}/" 2>/dev/null
    else
        cp -pL "$src" "$dst_path" 2>/dev/null
    fi || { log_warn "Failed to copy: $src (symlink to ${target})"; return 1; }
    echo "${src} -> ${target}: copied the target's content as ${dst_path##*/}" >> "${note_dir}/_symlinks.txt"
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
# 出力: "ラベル<TAB>ホーム<TAB>由来(passwd|orphan)" を 1 行ずつ。
# v0.3.2 までは /root と /home/* に固定で、/var/lib/... や /srv/... にホームを持つ
# サービスアカウントの履歴・SSH 鍵・crontab を取りこぼしていた。
#   - passwd（getent があれば NSS 経由。LDAP 等のユーザーも含む）のホームのうち、実在するもの
#   - /root と /home/* のうち、どの passwd 項目からも参照されていないもの
#     （アカウントを消してもホームが残っている。ラベルは orphan-home_<名前>）
# 同じホームを共有するユーザーは 1 度だけ（先に現れたユーザー名をラベルにする）。
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
    local passwd_src="${1:-}" label home src
    local -a extra=(/root /home/*)
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
            if (!(h in seen)) { seen[h] = 1; print $1 "\t" h "\tpasswd" }
            next
        }
        extra && $0 ~ /^\// {
            h = norm($0)
            if (h in seen) next
            seen[h] = 1
            n = h; sub(/.*\//, "", n)
            print "orphan-home_" n "\t" h "\torphan"
        }' | while IFS=$'\t' read -r label home src; do
            [[ -d "$home" ]] || continue
            printf '%s\t%s\t%s\n' "${label//[^A-Za-z0-9._@-]/_}" "$home" "$src"
        done
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
LDIR_CONFIG_EXTRA_RE='(USER_DATA|VENDOR_DATA|^ENVIRONMENT_)'
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
        */secrets/*|*/priv/*|*.key|*.pw|*.keyring|*.p12|*.pfx|*.jks|*.base64|*/authkey|*/auth.json|*/ssh_host_*_key|*/master-key.aes)
            return 0 ;;
    esac
    return 1
}

copy_config_tree() {
    local src="${1%/}" dst="${2%/}" report="$3" redact="${4:-0}"
    local keyfiles f rel n_copied=0 n_excluded=0
    if [[ ! -d "$src" ]]; then
        log_debug "Not present: $src"
        return 1
    fi
    ensure_dir "$dst" || { log_warn "Failed to create dir: $dst"; return 1; }
    ensure_dir "$(dirname "$report")"
    keyfiles="$(grep -rlE -- '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----|PuTTY-User-Key-File' "$src" 2>/dev/null)"
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        rel="${f#"$src"/}"
        if [[ -L "$f" ]]; then
            printf 'symlink\t%s -> %s\n' "$f" "$(readlink "$f" 2>/dev/null)" >> "$report"
            continue
        fi
        [[ -f "$f" ]] || continue
        if ldir_is_secret_path "$rel" || [[ $'\n'"${keyfiles}"$'\n' == *$'\n'"${f}"$'\n'* ]]; then
            printf 'secret\t%s\n' "$f" >> "$report"
            n_excluded=$((n_excluded + 1))
            continue
        fi
        ensure_dir "${dst}/$(dirname "$rel")" || continue
        if [[ "$redact" = "1" ]]; then
            if redact_config < "$f" > "${dst}/${rel}" 2>/dev/null; then
                touch -r "$f" "${dst}/${rel}" 2>/dev/null
            else
                log_warn "Failed to copy: $f"; continue
            fi
        else
            cp -p "$f" "${dst}/${rel}" 2>/dev/null || { log_warn "Failed to copy: $f"; continue; }
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
#   LDIR_LOG_CMD_TIMEOUT  journalctl / ausearch 1 回あたりの時間上限（秒、0 = 無制限）
LDIR_TAB=$'\t'
LDIR_LOG_DEFAULT_DAYS=30
LDIR_LOG_DEFAULT_MAX_MB=100
LDIR_LOG_DEFAULT_CMD_TIMEOUT=120

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
    export LDIR_LOG_DAYS LDIR_LOG_SINCE_EPOCH LDIR_LOG_SINCE LDIR_LOG_MAX_MB LDIR_LOG_CMD_TIMEOUT
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
        printf '# group\tdecision\tsize_bytes\tmtime\tpath\n' > "${dir}/log_inventory.tsv"
    fi
    if [[ ! -e "${dir}/log_summary.txt" ]]; then
        cat > "${dir}/log_summary.txt" << EOF
Log period : $(ldir_log_period_text)
Size cap   : $(ldir_log_cap_text)
Selection  : files modified within the period are taken newest first until the cap is reached.
             Once a file does not fit, older files are not taken either, so what was kept
             is one contiguous, most recent range. Compressed files are copied as they are.
Per file   : log_inventory.tsv (decision: collected / over_cap / older_than_period /
             symlink_not_followed / copy_failed / not_present)

STATUS
  collected       files from the period were copied
  capped          the size cap was reached: the newest files were copied, the rest were NOT
  none_in_period  log files of this kind exist, but none was modified within the period
  not_present     no log file of this kind exists on this host
  symlink_only    only symbolic links were found; they were not followed (e.g. -> /dev/stdout)
  copy_failed     some selected files could not be copied

EOF
        printf '%-16s %-15s %s\n' "GROUP" "STATUS" "DETAIL" >> "${dir}/log_summary.txt"
    fi
}

_ldir_join_patterns() {
    local base="$1" p out=""
    shift
    for p in "$@"; do out="${out}${out:+ }${base}/${p}"; done
    echo "$out"
}

# collect_log_group <群の名前> <コピー元の基点> <コピー先の基点> <レポートの置き場所> <パターン>...
# パターンは基点からの相対の glob。ディレクトリに一致したら中を再帰的にたどる。
# コピー先には基点からの相対パスのまま置く。
#   例: collect_log_group auth /var/log "$LOG_DIR" "$LOG_DIR" 'auth.log*' 'secure*'
# 期間（LDIR_LOG_SINCE_EPOCH）より古いファイルは取らず、上限（LDIR_LOG_MAX_MB）を
# 超える分は新しい順に取ったところで打ち切る。打ち切りは WARN。判定は全ファイル分を
# log_inventory.tsv に、群ごとの結果を log_summary.txt に残す。
collect_log_group() {
    local group="$1" src_base="${2%/}" dest_base="${3%/}" report="$4"; shift 4
    local cutoff="${LDIR_LOG_SINCE_EPOCH:-0}" cap=$(( ${LDIR_LOG_MAX_MB:-0} * 1048576 ))
    local tmp="${report}/.${group}.loggroup.tmp"
    local fmt="%Y${LDIR_TAB}%s${LDIR_TAB}%y${LDIR_TAB}%n"
    local p m start g d size hm path rel dir prev="" where
    local -a batch=()

    ldir_log_report_init "$report" || { log_warn "Cannot write the log report in ${report}"; return 1; }
    where="${report#"${OUTPUT_DIR%/}"/}"
    : > "${tmp}.cand"; : > "${tmp}.links"
    for p in "$@"; do
        # shellcheck disable=SC2086  # パターンの glob 展開が目的
        for m in "${src_base}"/${p}; do
            [[ -e "$m" || -L "$m" ]] || continue
            if [[ -L "$m" && ! -d "$m" ]]; then
                echo "$m" >> "${tmp}.links"
                continue
            fi
            start="$m"
            [[ -d "$m" ]] && start="${m%/}/"
            find "$start" "${LDIR_FIND_PRUNE[@]}" -type f -exec stat -c "$fmt" {} + >> "${tmp}.cand" 2>/dev/null
            find "$start" "${LDIR_FIND_PRUNE[@]}" -type l -print >> "${tmp}.links" 2>/dev/null
        done
    done

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
        rel="${path#"${src_base}"/}"
        if [[ "$rel" == */* ]]; then dir="${rel%/*}"; else dir="."; fi
        if [[ "$dir" != "$prev" && ${#batch[@]} -gt 0 ]]; then
            ensure_dir "${dest_base}/${prev}" && cp -p "${batch[@]}" "${dest_base}/${prev}/" 2>/dev/null
            batch=()
        fi
        prev="$dir"
        batch+=("$path")
    done < <(LC_ALL=C sort -t "${LDIR_TAB}" -k5,5 "${tmp}.decided")
    if [[ ${#batch[@]} -gt 0 ]]; then
        ensure_dir "${dest_base}/${prev}" && cp -p "${batch[@]}" "${dest_base}/${prev}/" 2>/dev/null
    fi

    # 確認: 「取った」と書く前に、実際にコピー先にあることを見る
    {
        while IFS="${LDIR_TAB}" read -r g d size hm path; do
            if [[ "$d" = "collect" ]]; then
                rel="${path#"${src_base}"/}"
                if [[ -f "${dest_base}/${rel}" ]]; then d="collected"; else d="copy_failed"; fi
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$g" "$d" "$size" "$hm" "$path"
        done < "${tmp}.decided"
        while IFS= read -r path; do
            [[ -n "$path" ]] && printf '%s\tsymlink_not_followed\t-\t-\t%s -> %s\n' "$group" "$path" "$(readlink "$path" 2>/dev/null)"
        done < <(LC_ALL=C sort -u "${tmp}.links")
    } > "${tmp}.final"
    if [[ ! -s "${tmp}.final" ]]; then
        printf '%s\tnot_present\t-\t-\t%s\n' "$group" "$(_ldir_join_patterns "$src_base" "$@")" > "${tmp}.final"
    fi
    cat "${tmp}.final" >> "${report}/log_inventory.tsv"

    # 群ごとの集計
    local stats n_col b_col n_cap b_cap n_old n_fail n_link status detail
    stats="$(awk -F'\t' '
        $2 == "collected"            { nc++; bc += $3 }
        $2 == "over_cap"             { no++; bo += $3 }
        $2 == "older_than_period"    { np++ }
        $2 == "copy_failed"          { nf++ }
        $2 == "symlink_not_followed" { nl++ }
        END { printf "%d %d %d %d %d %d %d", nc, bc, no, bo, np, nf, nl }' "${tmp}.final")"
    read -r n_col b_col n_cap b_cap n_old n_fail n_link <<< "$stats"
    rm -f "${tmp}.cand" "${tmp}.links" "${tmp}.decided" "${tmp}.final"

    detail="${n_col} file(s) collected ($(ldir_human_size "${b_col}"))"
    [[ ${n_cap} -gt 0 ]] && detail="${detail}; ${n_cap} file(s) over the cap NOT collected ($(ldir_human_size "${b_cap}"))"
    [[ ${n_old} -gt 0 ]] && detail="${detail}; ${n_old} older file(s) outside the period"
    [[ ${n_fail} -gt 0 ]] && detail="${detail}; ${n_fail} file(s) failed to copy"
    [[ ${n_link} -gt 0 ]] && detail="${detail}; ${n_link} symlink(s) not followed"
    if [[ ${n_fail} -gt 0 ]]; then
        status="copy_failed"
        log_warn "[${group}] ${n_fail} log file(s) could not be copied (see ${where}/log_inventory.tsv, decision copy_failed)"
    elif [[ ${n_cap} -gt 0 ]]; then
        status="capped"
        log_warn "[${group}] log size cap of ${LDIR_LOG_MAX_MB} MB reached: ${n_cap} older file(s) ($(ldir_human_size "${b_cap}")) NOT collected (see ${where}/log_inventory.tsv, decision over_cap; raise --log-max-mb or use 0 for no cap)"
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
    printf '%-16s %-15s %s\n' "$group" "$status" "$detail" >> "${report}/log_summary.txt"
    return 0
}

# copy_config_file <コピー元> <コピー先> <除外の記録ファイル>
# 1 ファイルを redact_config を通して写す（更新日時は元に合わせる）。
# 秘密鍵を含むファイルは書かずに、除外の記録だけ残す。
copy_config_file() {
    local src="$1" dst="$2" report="$3"
    if [[ -L "$src" && ! -e "$src" ]] || [[ ! -e "$src" ]]; then
        log_debug "Not present: $src"
        return 1
    fi
    [[ -f "$src" ]] || return 1
    if ldir_is_secret_path "${src#/}" || grep -qE -- '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----|PuTTY-User-Key-File' "$src" 2>/dev/null; then
        ensure_dir "$(dirname "$report")"
        printf 'secret\t%s\n' "$src" >> "$report"
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
