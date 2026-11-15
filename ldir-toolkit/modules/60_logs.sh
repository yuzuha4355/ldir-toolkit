#!/bin/bash
#
# Module: Log Files Collection
# ログファイル収集モジュール
#
# 期間（--log-days、既定 30 日）と容量の上限（--log-max-mb、ログ群ごと既定 100 MB。
# バイナリの journal は --journal-max-mb、既定 256 MB）を、すべてのログに一貫して適用する。
#   - journal: テキスト出力に --since を付ける。バイナリの journal ファイルも同じ規則で取る
#   - ログファイル: 更新日時が期間内のものを、ローテーション済み（.1, .2.gz, -YYYYMMDD）も
#     含めて取る。圧縮されたものは展開せずにそのままコピーする
#   - 上限を超えたら新しいファイルから取り、残りは取らない（WARN と log_inventory.tsv）
# ログ群ごとの結果は logs/log_summary.txt、ファイルごとの判定は logs/log_inventory.tsv。
# 「該当ファイルなし（none_in_period）」と「ログ自体が無い（not_present）」を区別して残す。
#
# LDIR_LOG_ROOT を付けると /var/log /run/log /var/lib/pgsql をその下から読む（テスト用）。
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [60_logs] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

LOG_DIR="${OUTPUT_DIR}/logs"
ensure_dir "${LOG_DIR}" || { log_error "[60_logs] Failed to create ${LOG_DIR}"; exit 1; }
LR="${LDIR_LOG_ROOT:-}"

# 単体で実行された場合（ldir-collect.sh を経由しない）は、モードの既定値で決める
if [[ -z "${LDIR_LOG_DAYS:-}" ]] || [[ -z "${LDIR_LOG_SINCE_EPOCH:-}" ]] || [[ -z "${LDIR_JOURNAL_MAX_MB:-}" ]]; then
    ldir_resolve_log_settings || { log_error "[60_logs] ${LDIR_SETTINGS_ERROR}"; exit 1; }
fi

log_info "[60_logs] Starting log collection: period $(ldir_log_period_text), size cap $(ldir_log_cap_text), binary journal $(ldir_journal_cap_text)"
ldir_log_report_init "${LOG_DIR}" || { log_error "[60_logs] Cannot write ${LOG_DIR}/log_summary.txt"; exit 1; }

CMD_TIMEOUT="${LDIR_LOG_CMD_TIMEOUT:-0}"
CAP_BYTES=$(( ${LDIR_LOG_MAX_MB:-0} * 1048576 ))
# journal のテキスト出力は件数で抑える（1 件 200 バイトを目安に、上限 MB から換算）。
# LDIR_JOURNAL_TEXT_MAX_LINES で件数を直接指定できる（0 = 上限なし）
JOURNAL_MAX_LINES=$(( ${LDIR_LOG_MAX_MB:-0} * 5000 ))
case "${LDIR_JOURNAL_TEXT_MAX_LINES:-}" in
    "") ;;
    *[!0-9]*) log_warn "[60_logs] LDIR_JOURNAL_TEXT_MAX_LINES='${LDIR_JOURNAL_TEXT_MAX_LINES}' is not a number; using ${JOURNAL_MAX_LINES}" ;;
    *) JOURNAL_MAX_LINES=$((10#${LDIR_JOURNAL_TEXT_MAX_LINES})) ;;
esac

# --- バイナリの journal（テキスト出力で落ちるフィールド _EXE, _CMDLINE, _UID 等も残る）---
# テキスト出力の注記で案内するため、先に取る。上限は --journal-max-mb（journald の既定では
# 1 ファイル 128 MB まで育つため、ログ群の既定 100 MB では最新のファイルが必ず超える）
log_info "Collecting the binary journal"
JOURNAL_BIN=""
LDIR_LOG_GROUP_CAP_MB="${LDIR_JOURNAL_MAX_MB:-0}" \
    collect_log_group journal         "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'journal'
[[ ${LDIR_LOG_GROUP_COLLECTED:-0} -gt 0 ]] && JOURNAL_BIN="logs/journal/"
LDIR_LOG_GROUP_CAP_MB="${LDIR_JOURNAL_MAX_MB:-0}" \
    collect_log_group journal_runtime "${LR}/run/log" "${LOG_DIR}/run_log" "${LOG_DIR}" 'journal'
[[ ${LDIR_LOG_GROUP_COLLECTED:-0} -gt 0 ]] && JOURNAL_BIN="${JOURNAL_BIN}${JOURNAL_BIN:+ and }logs/run_log/journal/"

# 新しい順（journalctl -r）の出力を、項目単位で元の順に戻す。複数行のメッセージは、
# 2 行目以降が字下げされて続く（項目の中の行の順は保つ）
reverse_entries() {
    awk '
        /^[ \t]/ && n > 0 { e[n] = e[n] "\n" $0; next }
        { e[++n] = $0 }
        END { for (i = n; i >= 1; i--) print e[i] }'
}

# journal_export <出力ファイル名> <journalctl の引数...>
# 期間・件数・時間の上限を付けて journalctl を実行する。打ち切った場合は
# ファイルの先頭に注記を入れ、WARN を出す（空や短い出力を「該当なし」と読ませない）。
# 件数で抑えるときは、新しい順（-r）に N 件取り、元の順に戻す。--since と -n を併せたときに
# 残る側は systemd の版で違う（252 は古い側、255・257 は新しい側。v0.4.0 の検証レポートの指摘 3）。
journal_export() {
    local name="$1"; shift
    local f="${LOG_DIR}/${name}" raw="${LOG_DIR}/.${name}.tmp" rc=0 entries
    local -a args=(--no-pager -o short-iso) note=()
    [[ "${LDIR_LOG_SINCE_EPOCH:-0}" != "0" ]] && args+=(--since "${LDIR_LOG_SINCE}")
    [[ -n "${JOURNAL_BIN}" ]] && note=("The binary journal files of the period are in ${JOURNAL_BIN} (read them with journalctl --directory).")
    if [[ ${JOURNAL_MAX_LINES} -gt 0 ]]; then
        run_limited "${CMD_TIMEOUT}" journalctl "${args[@]}" -r -n "${JOURNAL_MAX_LINES}" "$@" > "${raw}" 2> "${raw}.err" || rc=$?
        entries="$(awk '!/^[ \t]/ && !/^-- / { c++ } END { print c + 0 }' "${raw}" 2>/dev/null)" || entries=0
        { cat "${raw}.err"; reverse_entries < "${raw}"; } > "$f" 2>/dev/null
        rm -f "${raw}" "${raw}.err"
    else
        capture_try "$f" run_limited "${CMD_TIMEOUT}" journalctl "${args[@]}" "$@" || rc=$?
        entries=0
    fi
    if [[ ${rc} -eq 124 ]]; then
        mark_partial "$f" "journalctl $* was stopped after ${CMD_TIMEOUT}s; the export is incomplete" \
            "(with an entry limit, the entries here are the newest ones read before the stop)." "${note[@]}"
        log_warn "[60_logs] journal export ${name} hit the ${CMD_TIMEOUT}s limit; output is partial"
        return 0
    elif [[ ${rc} -ne 0 ]]; then
        log_warn "[60_logs] journalctl failed (exit ${rc}) for ${name}"
        return 0
    fi
    if [[ ${JOURNAL_MAX_LINES} -gt 0 && ${entries} -ge ${JOURNAL_MAX_LINES} ]]; then
        mark_partial "$f" "reached the limit of ${JOURNAL_MAX_LINES} entries (--log-max-mb ${LDIR_LOG_MAX_MB}): the newest ${JOURNAL_MAX_LINES} entries were kept;" \
            "the oldest entries of the period are NOT in this file." "${note[@]}"
        log_warn "[60_logs] journal export ${name} reached the ${JOURNAL_MAX_LINES}-entry limit; the oldest entries of the period are not in it"
    fi
    return 0
}

# --- systemd journal（テキスト）---
if have_cmd journalctl; then
    log_info "Collecting systemd journal"
    # 直近 1000 行（解説付き）。-e は末尾 1000 行に制限される
    capture "${LOG_DIR}/journal_tail.txt" run_limited "${CMD_TIMEOUT}" journalctl -xe --no-pager
    if [[ "${LDIR_LOG_SINCE_EPOCH:-0}" = "0" ]]; then
        # 期間の指定なし（full モード）: 全期間
        journal_export journal_full.txt
    else
        # v0.3.2 までの journal_7days.txt。日数が変わるので名前に数字を入れない
        journal_export journal_period.txt
    fi
    # 認証（auth / authpriv）。rsyslog の無いホスト（Fedora、Arch 等）では
    # /var/log/secure や auth.log が無く、認証の記録は journal にしかない
    journal_export journal_auth.txt SYSLOG_FACILITY=4 SYSLOG_FACILITY=10
    journal_export journal_errors.txt -p err
    journal_export journal_ssh.txt -u ssh
    journal_export journal_sshd.txt -u sshd
    # Debian 系は cron、RHEL 系は crond
    journal_export journal_cron.txt -u cron -u crond
else
    log_debug "journalctl not available"
fi

# --- ファイルのログ ---
log_info "Collecting log files"
# 群は製品ごと（Web と DB は、量の多い 1 つが上限を使い切って別の製品のログが取れなくなるのを防ぐ）
# 認証。Debian 系 auth.log、RHEL 系 secure（ローテーションは secure-YYYYMMDD）
collect_log_group auth      "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'auth.log*' 'secure*'
collect_log_group syslog    "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'syslog*' 'messages*'
collect_log_group kern      "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'kern.log*'
# RHEL 系の cron ログ（/var/log/cron）。v0.3.2 までは取っていなかった
collect_log_group cron      "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'cron' 'cron[.-]*'
collect_log_group boot      "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'boot.log*' 'dmesg*'
# auditd（v0.3.2 までは execution/audit/ に期間・容量の制限なしでコピーしていた）
collect_log_group audit     "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'audit/audit.log*'
# ログイン記録（バイナリ）。ローテーション分も含む
collect_log_group login     "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'wtmp*' 'btmp*'
# dnf5（Fedora 41 以降）は dnf5.log
collect_log_group packages  "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" \
    'apt/history.log*' 'apt/term.log*' 'dpkg.log*' 'yum.log*' 'dnf.log*' 'dnf.rpm.log*' 'dnf5.log*' \
    'pacman.log*' 'zypp/history*' 'apk.log*' 'emerge.log*'
collect_log_group web_apache        "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'apache2' 'httpd'
collect_log_group web_nginx         "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'nginx'
collect_log_group web_lighttpd      "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'lighttpd'
collect_log_group db_mysql          "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'mysql' 'mysqld.log*'
collect_log_group db_mariadb        "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'mariadb'
collect_log_group db_postgresql     "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'postgresql'
collect_log_group db_mongodb        "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'mongodb'
collect_log_group db_redis          "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'redis'
# RHEL 系の PostgreSQL はデータディレクトリの下にログを書く
collect_log_group db_pgsql          "${LR}/var/lib/pgsql" "${LOG_DIR}/pgsql" "${LOG_DIR}" \
    'data/log' 'data/pg_log' '*/data/log' '*/data/pg_log'
collect_log_group mail      "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" \
    'mail.log*' 'mail.err*' 'mail.warn*' 'mail.info*' 'maillog*'
collect_log_group firewall_ufw       "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'ufw.log*'
collect_log_group firewall_firewalld "${LR}/var/log" "${LOG_DIR}" "${LOG_DIR}" 'firewalld*'

# 期間・上限の対象外の、単体のデータベース形式のファイル
safe_copy "${LR}/var/log/lastlog" "${LOG_DIR}/"
safe_copy "${LR}/var/log/faillog" "${LOG_DIR}/"

# /var/log の全体像。上の群に入らないアプリケーションのログは取らないが、
# 何が存在したかは残す（「取っていない」ことが収集物から分かるように）
capture "${LOG_DIR}/var_log_listing.txt" run_limited 30 find "${LR}/var/log" -maxdepth 3 "${LDIR_FIND_LS[@]}"

# --- テキスト形式のログイン記録（現行の wtmp / btmp のみ。ローテーション分はバイナリで上に）---
log_info "Collecting login history"
if [[ -e /var/log/wtmp ]]; then
    capture_try "${LOG_DIR}/last_logins.txt" last -F || capture "${LOG_DIR}/last_logins.txt" last
else
    echo "/var/log/wtmp does not exist on this host" > "${LOG_DIR}/last_logins.txt"
fi
if [[ -e /var/log/btmp ]]; then
    capture "${LOG_DIR}/failed_logins.txt" lastb
else
    echo "/var/log/btmp does not exist on this host" > "${LOG_DIR}/failed_logins.txt"
fi
if [[ -e /var/log/lastlog ]] && have_cmd lastlog; then
    capture "${LOG_DIR}/lastlog.txt" lastlog
fi
capture "${LOG_DIR}/current_users.txt" who
capture "${LOG_DIR}/current_users_detailed.txt" w

# --- auditd の抽出（v0.3.2 までは 15_execution）---
# ausearch は期間の指定がないと全ログを読む。--start に期間の始まりを渡す。
# ausearch の日付の書式はロケール依存（%x）なので、date と ausearch の両方を C ロケールに揃える。
# 終了コード 1 は「該当なし」であり失敗ではない。
ausearch_export() {
    local name="$1"; shift
    local f="${LOG_DIR}/${name}" rc
    if [[ ${CAP_BYTES} -gt 0 ]]; then
        run_limited "${CMD_TIMEOUT}" env LC_ALL=C ausearch "$@" 2>&1 | head -c "${CAP_BYTES}" > "$f"
        rc=${PIPESTATUS[0]}
    else
        capture_try "$f" run_limited "${CMD_TIMEOUT}" env LC_ALL=C ausearch "$@"
        rc=$?
    fi
    if [[ ${CAP_BYTES} -gt 0 && $(wc -c < "$f") -ge ${CAP_BYTES} ]]; then
        mark_partial "$f" "output reached the ${LDIR_LOG_MAX_MB} MB cap and was cut; later events are NOT in this file." \
            "The raw audit logs are in logs/audit/."
        log_warn "[60_logs] ausearch ${name} reached the ${LDIR_LOG_MAX_MB} MB cap; output is partial"
    elif [[ ${rc} -eq 124 ]]; then
        mark_partial "$f" "ausearch was stopped after ${CMD_TIMEOUT}s; the result is incomplete." \
            "The raw audit logs are in logs/audit/."
        log_warn "[60_logs] ausearch ${name} hit the ${CMD_TIMEOUT}s limit; output is partial"
    elif [[ ${rc} -ne 0 && ${rc} -ne 1 ]]; then
        log_warn "[60_logs] ausearch failed (exit ${rc}) for ${name}"
    fi
}

if [[ -d /var/log/audit ]] && have_cmd ausearch; then
    log_info "Extracting executed commands from the audit log"
    start=()
    if [[ "${LDIR_LOG_SINCE_EPOCH:-0}" != "0" ]]; then
        start_date="$(LC_ALL=C date -d "@${LDIR_LOG_SINCE_EPOCH}" '+%x' 2>/dev/null)" || start_date=""
        if [[ -n "${start_date}" ]]; then
            start=(--start "${start_date}")
        else
            log_warn "[60_logs] could not compute the start date for ausearch; extracting from all audit logs"
        fi
    fi
    ausearch_export audit_execve.txt -i -m EXECVE "${start[@]}"
    ausearch_export audit_user_cmd.txt -i -m USER_CMD "${start[@]}"
    ausearch_export audit_recent.txt -i --start recent
fi

log_success "[60_logs] Log collection completed (see logs/log_summary.txt)"
exit 0
