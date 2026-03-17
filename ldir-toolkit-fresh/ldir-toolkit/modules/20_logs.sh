#!/bin/bash
#
# Module: Log Files Collection
# ログファイル収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [20_logs] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

LOG_DIR="${OUTPUT_DIR}/logs"
ensure_dir "${LOG_DIR}" || { log_error "[20_logs] Failed to create ${LOG_DIR}"; exit 1; }

log_info "[20_logs] Starting log collection"

# systemd journal（存在する場合）
if command -v journalctl &> /dev/null; then
    log_info "Collecting systemd journal logs"
    journalctl -xe --no-pager > "${LOG_DIR}/journal_full.txt" 2>&1 || log_warn "Failed to collect full journal"
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
safe_copy "${AUTH_LOG}" "${LOG_DIR}/auth.log"
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
last -F > "${LOG_DIR}/last_logins.txt" 2>&1 || last > "${LOG_DIR}/last_logins.txt" 2>&1
lastb > "${LOG_DIR}/failed_logins.txt" 2>&1 || true
lastlog > "${LOG_DIR}/lastlog.txt" 2>&1 || true
who > "${LOG_DIR}/current_users.txt" 2>&1
w > "${LOG_DIR}/current_users_detailed.txt" 2>&1

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

log_success "[20_logs] Log collection completed"
exit 0
