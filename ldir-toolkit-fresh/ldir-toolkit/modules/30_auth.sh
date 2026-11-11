#!/bin/bash
#
# Module: Authentication & User Information
# 認証・ユーザ情報収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [30_auth] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

AUTH_DIR="${OUTPUT_DIR}/config"
ensure_dir "${AUTH_DIR}" || { log_error "[30_auth] Failed to create ${AUTH_DIR}"; exit 1; }

log_info "[30_auth] Starting authentication information collection"

# ユーザ・グループ情報
log_info "Collecting user and group information"
safe_copy "/etc/passwd" "${AUTH_DIR}/"
safe_copy "/etc/shadow" "${AUTH_DIR}/"
safe_copy "/etc/group" "${AUTH_DIR}/"
safe_copy "/etc/gshadow" "${AUTH_DIR}/"

# sudoers設定
log_info "Collecting sudo configuration"
safe_copy "/etc/sudoers" "${AUTH_DIR}/"
safe_copy "/etc/sudoers.d/" "${AUTH_DIR}/sudoers.d/"

# PAM設定
log_info "Collecting PAM configuration"
safe_copy "/etc/pam.d/" "${AUTH_DIR}/pam.d/"
safe_copy "/etc/security/" "${AUTH_DIR}/security/"

# SSH設定
log_info "Collecting SSH configuration"
safe_copy "/etc/ssh/" "${AUTH_DIR}/ssh/"
# ホスト秘密鍵は持ち出さない（公開鍵 *.pub と設定は残す）
if [[ -d "${AUTH_DIR}/ssh" ]]; then
    find "${AUTH_DIR}/ssh" -type f -name 'ssh_host_*_key' -exec rm -f {} + 2>/dev/null || true
fi

# ユーザごとのSSH設定
for user_home in /root /home/*; do
    if [[ -d "$user_home" ]]; then
        username="$(basename "$user_home")"
        if [[ -d "${user_home}/.ssh" ]]; then
            log_info "Collecting SSH config for user: ${username}"
            mkdir -p "${AUTH_DIR}/user_ssh/${username}"
            safe_copy "${user_home}/.ssh/authorized_keys" "${AUTH_DIR}/user_ssh/${username}/"
            safe_copy "${user_home}/.ssh/known_hosts" "${AUTH_DIR}/user_ssh/${username}/"
            safe_copy "${user_home}/.ssh/config" "${AUTH_DIR}/user_ssh/${username}/"
            # 秘密鍵はコピーしない（セキュリティ上の理由）
        fi
    fi
done

# 現在ログイン中のユーザ
log_info "Collecting current login sessions"
who -a > "${AUTH_DIR}/who_all.txt" 2>&1
w -h > "${AUTH_DIR}/w_output.txt" 2>&1

# ログイン履歴分析
last -Faixw > "${AUTH_DIR}/last_full.txt" 2>&1 || last -a > "${AUTH_DIR}/last_full.txt" 2>&1

log_success "[30_auth] Authentication information collection completed"
exit 0
