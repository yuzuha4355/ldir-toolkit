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
ps auxwwf > "${EXEC_DIR}/running_processes_tree.txt" 2>&1
ps auxww > "${EXEC_DIR}/running_processes.txt" 2>&1
ps -eo pid,ppid,user,cmd,lstart,etime > "${EXEC_DIR}/process_start_times.txt" 2>&1
ps -eo pid,tid,class,rtprio,ni,pri,psr,pcpu,stat,wchan:14,comm > "${EXEC_DIR}/process_scheduling.txt" 2>&1

# プロセスツリー
if command -v pstree &> /dev/null; then
    pstree -a > "${EXEC_DIR}/process_tree.txt" 2>&1
    pstree -p > "${EXEC_DIR}/process_tree_pids.txt" 2>&1
fi

# top のスナップショット
top -b -n 1 > "${EXEC_DIR}/top_snapshot.txt" 2>&1

# /proc からのプロセス情報
log_info "Collecting detailed process information from /proc"
mkdir -p "${EXEC_DIR}/proc_details"
for pid_dir in /proc/[0-9]*; do
    if [[ -d "$pid_dir" ]]; then
        pid=$(basename "$pid_dir")
        mkdir -p "${EXEC_DIR}/proc_details/${pid}"

        # コマンドライン
        { tr '\0' ' ' < "${pid_dir}/cmdline" > "${EXEC_DIR}/proc_details/${pid}/cmdline.txt"; } 2>/dev/null || true

        # 実行ファイルパス
        readlink "${pid_dir}/exe" > "${EXEC_DIR}/proc_details/${pid}/exe.txt" 2>&1 || true

        # カレントディレクトリ
        readlink "${pid_dir}/cwd" > "${EXEC_DIR}/proc_details/${pid}/cwd.txt" 2>&1 || true

        # プロセス状態
        cat "${pid_dir}/status" > "${EXEC_DIR}/proc_details/${pid}/status.txt" 2>&1 || true

        if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
            # 環境変数（情報量が多く、PII/secret が混入しやすい）
            { tr '\0' '\n' < "${pid_dir}/environ" | redact_env > "${EXEC_DIR}/proc_details/${pid}/environ.txt"; } 2>/dev/null || true

            # オープンファイル（重い）
            ls -l "${pid_dir}/fd/" > "${EXEC_DIR}/proc_details/${pid}/open_files.txt" 2>&1 || true
        fi
    fi
done

# コマンド履歴
log_info "Collecting command history"
for user_home in /root /home/*; do
    if [[ -d "$user_home" ]]; then
        username="$(basename "$user_home")"
        
        # bash
        if [[ -f "${user_home}/.bash_history" ]]; then
            cp "${user_home}/.bash_history" "${EXEC_DIR}/bash_history_${username}" 2>/dev/null || log_warn "Cannot copy bash_history for ${username}"
        fi
        
        # zsh
        if [[ -f "${user_home}/.zsh_history" ]]; then
            cp "${user_home}/.zsh_history" "${EXEC_DIR}/zsh_history_${username}" 2>/dev/null || log_warn "Cannot copy zsh_history for ${username}"
        fi
        
        # 最近使ったファイル
        safe_copy "${user_home}/.local/share/recently-used.xbel" "${EXEC_DIR}/recently_used_${username}.xbel"
    fi
done

# auditd ログ（存在する場合）
log_info "Collecting audit logs"
if [[ -d /var/log/audit/ ]]; then
    safe_copy "/var/log/audit/" "${EXEC_DIR}/audit/"
    
    # 実行コマンドの抽出
    if command -v ausearch &> /dev/null; then
        ausearch -i -m EXECVE > "${EXEC_DIR}/audit_execve.txt" 2>&1 || true
        ausearch -i -m USER_CMD > "${EXEC_DIR}/audit_user_cmd.txt" 2>&1 || true
        ausearch -i --start recent > "${EXEC_DIR}/audit_recent.txt" 2>&1 || true
    fi
fi

# 実行中のサービス
if command -v systemctl &> /dev/null; then
    systemctl list-units --type=service --state=running > "${EXEC_DIR}/running_services.txt" 2>&1
fi

# 開いているファイル
log_info "Collecting open files information"
if command -v lsof &> /dev/null; then
    lsof > "${EXEC_DIR}/lsof_all.txt" 2>&1 || true
    lsof -i > "${EXEC_DIR}/lsof_network.txt" 2>&1 || true
fi

log_success "[15_execution] Execution history collection completed"
exit 0
