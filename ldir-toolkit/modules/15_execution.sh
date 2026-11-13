#!/bin/bash
#
# Module: Execution History
# 実行履歴収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [15_execution] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

EXEC_DIR="${OUTPUT_DIR}/execution"
ensure_dir "${EXEC_DIR}" || { log_error "[15_execution] Failed to create ${EXEC_DIR}"; exit 1; }

log_info "[15_execution] Starting execution history collection"

# 現在実行中のプロセス
log_info "Collecting running processes information"
if ps --version 2>/dev/null | grep -qi procps; then
    capture "${EXEC_DIR}/running_processes_tree.txt" ps auxwwf
    capture "${EXEC_DIR}/running_processes.txt" ps auxww
    capture "${EXEC_DIR}/process_start_times.txt" ps -eo pid,ppid,user,cmd,lstart,etime
    capture "${EXEC_DIR}/process_scheduling.txt" ps -eo pid,tid,class,rtprio,ni,pri,psr,pcpu,stat,wchan:14,comm
else
    # BusyBox 等の ps。BSD 形式のオプション（aux, f）は黙って無視され、
    # lstart / pcpu などの列も無い。取れる列を明示的に指定し、制約を記録する。
    # （黙って劣化した出力を「完全に取れた」ように見せない）
    log_warn "[15_execution] ps is not procps (BusyBox?): no start time, CPU/memory % or tree view; see execution/ps_limited.txt"
    cat > "${EXEC_DIR}/ps_limited.txt" << 'NOTE'
The ps on this host is not procps (typically BusyBox).
- running_processes.txt uses a reduced column set.
- No absolute start time (lstart): process_start_times.txt has elapsed time (etime) only.
  Start time = collection time (system/collection_time.txt) minus etime.
- No tree view and no scheduling columns: running_processes_tree.txt and
  process_scheduling.txt are not produced. Parent/child links are in the ppid column
  and in proc_details/<PID>/status.
NOTE
    capture_try "${EXEC_DIR}/running_processes.txt" ps -o pid,ppid,user,group,stat,vsz,rss,tty,nice,time,etime,args \
        || capture "${EXEC_DIR}/running_processes.txt" ps
    capture_try "${EXEC_DIR}/process_start_times.txt" ps -o pid,ppid,user,etime,args \
        || echo "etime column not supported by this ps" > "${EXEC_DIR}/process_start_times.txt"
fi

# プロセスツリー
if command -v pstree &> /dev/null; then
    capture "${EXEC_DIR}/process_tree.txt" pstree -a
    capture "${EXEC_DIR}/process_tree_pids.txt" pstree -p
fi

# top のスナップショット
capture "${EXEC_DIR}/top_snapshot.txt" top -b -n 1

# /proc からのプロセス情報
# プロセスは収集中に終了し得るし、カーネルスレッドには exe も cmdline も無い。
# 1 件ごとの失敗は想定内なので記録しない（ldir:allow は単体テストの検査の除外指定）。
log_info "Collecting detailed process information from /proc"
mkdir -p "${EXEC_DIR}/proc_details"
for pid_dir in /proc/[0-9]*; do
    if [[ -d "$pid_dir" ]]; then
        pid=$(basename "$pid_dir")
        mkdir -p "${EXEC_DIR}/proc_details/${pid}"

        # コマンドライン
        { tr '\0' ' ' < "${pid_dir}/cmdline" > "${EXEC_DIR}/proc_details/${pid}/cmdline.txt"; } 2>/dev/null || true

        # 実行ファイルパス
        readlink "${pid_dir}/exe" > "${EXEC_DIR}/proc_details/${pid}/exe.txt" 2>&1 || true  # ldir:allow

        # カレントディレクトリ
        readlink "${pid_dir}/cwd" > "${EXEC_DIR}/proc_details/${pid}/cwd.txt" 2>&1 || true  # ldir:allow

        # プロセス状態
        cat "${pid_dir}/status" > "${EXEC_DIR}/proc_details/${pid}/status.txt" 2>&1 || true  # ldir:allow

        if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
            # 環境変数（情報量が多く、PII/secret が混入しやすい）
            { tr '\0' '\n' < "${pid_dir}/environ" | redact_env > "${EXEC_DIR}/proc_details/${pid}/environ.txt"; } 2>/dev/null || true

            # オープンファイル（重い）
            ls -l "${pid_dir}/fd/" > "${EXEC_DIR}/proc_details/${pid}/open_files.txt" 2>&1 || true  # ldir:allow
        fi
    fi
done

# コマンド履歴
# ホームは passwd から引く（/root と /home/* 以外にホームを持つサービスアカウントも対象）。
# cp -a で更新日時を保つ（履歴ファイルの更新日時は最後の操作の時刻の手がかりになる）。
# bash / zsh は v0.3.2 までと同じ名前で残し、それ以外は user_history/<ユーザー>/ に置く。
log_info "Collecting command history"
HISTORY_FILES=(
    .ash_history .sh_history .history .ksh_history .zhistory
    .local/share/fish/fish_history .config/fish/fish_history
    .python_history .mysql_history .psql_history .sqlite_history .rediscli_history
    .node_repl_history .irb_history .Rhistory .dbshell .mongo_dbshell
    .lesshst .viminfo .wget-hsts
)
while IFS=$'\t' read -r username user_home _; do
    [[ -n "${user_home}" ]] || continue
    if [[ -f "${user_home}/.bash_history" ]]; then
        safe_copy "${user_home}/.bash_history" "${EXEC_DIR}/bash_history_${username}"
    fi
    if [[ -f "${user_home}/.zsh_history" ]]; then
        safe_copy "${user_home}/.zsh_history" "${EXEC_DIR}/zsh_history_${username}"
    fi
    for h in "${HISTORY_FILES[@]}"; do
        [[ -e "${user_home}/${h}" ]] || continue
        safe_copy "${user_home}/${h}" "${EXEC_DIR}/user_history/${username}/${h#.local/share/}"
    done
    # 最近使ったファイル（デスクトップ環境）
    if [[ -f "${user_home}/.local/share/recently-used.xbel" ]]; then
        safe_copy "${user_home}/.local/share/recently-used.xbel" "${EXEC_DIR}/recently_used_${username}.xbel"
    fi
done < <(ldir_user_homes)

# auditd のログと ausearch の抽出は 60_logs に移した（期間と容量の上限を揃えるため。
# 揮発性の高い情報を先に取るこのモジュールで、大きなログのコピーに時間を使わない）

# 実行中のサービス
if command -v systemctl &> /dev/null && [[ -d /run/systemd/system ]]; then
    capture "${EXEC_DIR}/running_services.txt" systemctl list-units --type=service --state=running
fi

# 開いているファイル
# lsof は警告（読めない FUSE マウント等）があっても一覧を出して 1 で終わることがあり、
# 該当が無いときも 1 で終わる。出力があれば部分的にでも取れたとみなす。
log_info "Collecting open files information"
if have_cmd lsof; then
    capture_partial "${EXEC_DIR}/lsof_all.txt" lsof
    capture_try "${EXEC_DIR}/lsof_network.txt" lsof -i \
        || [[ -s "${EXEC_DIR}/lsof_network.txt" ]] \
        || echo "lsof -i: no network files (exit 1 with no output)" > "${EXEC_DIR}/lsof_network.txt"
fi

log_success "[15_execution] Execution history collection completed"
exit 0
