#!/bin/bash
#
# Module: Log Files Collection
# ログファイル収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [60_logs] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

LOG_DIR="${OUTPUT_DIR}/logs"
ensure_dir "${LOG_DIR}" || { log_error "[60_logs] Failed to create ${LOG_DIR}"; exit 1; }

log_info "[60_logs] Starting log collection"

# systemd journal（存在する場合）
if command -v journalctl &> /dev/null; then
    log_info "Collecting systemd journal logs"
    # 直近 1000 行（解説付き）。-e は末尾 1000 行に制限されるため "full" ではない。
    journalctl -xe --no-pager > "${LOG_DIR}/journal_tail.txt" 2>&1 || log_warn "Failed to collect journal tail"
    if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
        # 全期間（大きくなり得る）
        journalctl --no-pager -o short-iso > "${LOG_DIR}/journal_full.txt" 2>&1 || log_warn "Failed to collect full journal"
    fi
    journalctl --no-pager --since "7 days ago" > "${LOG_DIR}/journal_7days.txt" 2>&1 || true
    journalctl -u ssh --no-pager > "${LOG_DIR}/journal_ssh.txt" 2>&1 || true
    journalctl -u cron --no-pager > "${LOG_DIR}/journal_cron.txt" 2>&1 || true
    journalctl -u sshd --no-pager > "${LOG_DIR}/journal_sshd.txt" 2>&1 || true
    journalctl -p err --no-pager > "${LOG_DIR}/journal_errors.txt" 2>&1 || true
fi

# 主要なログファイル
log_info "Collecting system log files"
safe_copy "/var/log/syslog" "${LOG_DIR}/"
safe_copy "/var/log/syslog.1" "${LOG_DIR}/"
safe_copy "/var/log/messages" "${LOG_DIR}/"
safe_copy "/var/log/messages.1" "${LOG_DIR}/"
# AUTH_LOG は環境検出の結果（auth.log / secure）。見つからない場合は "none"。
if [[ -n "${AUTH_LOG:-}" && "${AUTH_LOG}" != "none" ]]; then
    safe_copy "${AUTH_LOG}" "${LOG_DIR}/auth.log"
fi
safe_copy "/var/log/kern.log" "${LOG_DIR}/"
safe_copy "/var/log/dmesg" "${LOG_DIR}/"
safe_copy "/var/log/boot.log" "${LOG_DIR}/"

# セキュリティ関連ログ
log_info "Collecting security logs"
safe_copy "/var/log/secure" "${LOG_DIR}/"
safe_copy "/var/log/secure.1" "${LOG_DIR}/"
safe_copy "/var/log/faillog" "${LOG_DIR}/"

# ログイン履歴
log_info "Collecting login history"
safe_copy "/var/log/wtmp" "${LOG_DIR}/"
safe_copy "/var/log/btmp" "${LOG_DIR}/"
safe_copy "/var/log/lastlog" "${LOG_DIR}/"

# テキスト形式でもエクスポート
capture_try "${LOG_DIR}/last_logins.txt" last -F || capture "${LOG_DIR}/last_logins.txt" last
lastb > "${LOG_DIR}/failed_logins.txt" 2>&1 || true
lastlog > "${LOG_DIR}/lastlog.txt" 2>&1 || true
capture "${LOG_DIR}/current_users.txt" who
capture "${LOG_DIR}/current_users_detailed.txt" w

# パッケージマネージャのログ
log_info "Collecting package manager logs"
safe_copy "/var/log/apt/" "${LOG_DIR}/apt/"
safe_copy "/var/log/yum.log" "${LOG_DIR}/"
safe_copy "/var/log/dnf.log" "${LOG_DIR}/"
safe_copy "/var/log/dpkg.log" "${LOG_DIR}/"
safe_copy "/var/log/pacman.log" "${LOG_DIR}/"

# Webサーバログ（存在する場合）
log_info "Collecting web server logs"
safe_copy "/var/log/apache2/" "${LOG_DIR}/apache2/"
safe_copy "/var/log/httpd/" "${LOG_DIR}/httpd/"
safe_copy "/var/log/nginx/" "${LOG_DIR}/nginx/"

# データベースログ
log_info "Collecting database logs"
safe_copy "/var/log/mysql/" "${LOG_DIR}/mysql/"
safe_copy "/var/log/postgresql/" "${LOG_DIR}/postgresql/"

# その他のアプリケーションログ
safe_copy "/var/log/mail.log" "${LOG_DIR}/"
safe_copy "/var/log/mail.err" "${LOG_DIR}/"
safe_copy "/var/log/ufw.log" "${LOG_DIR}/"
safe_copy "/var/log/firewalld" "${LOG_DIR}/"

log_success "[60_logs] Log collection completed"
exit 0
