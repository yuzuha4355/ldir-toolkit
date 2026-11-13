#!/bin/bash
#
# Module: Authentication & User Information
# 認証・ユーザ情報収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [40_auth] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

AUTH_DIR="${OUTPUT_DIR}/config"
ensure_dir "${AUTH_DIR}" || { log_error "[40_auth] Failed to create ${AUTH_DIR}"; exit 1; }

log_info "[40_auth] Starting authentication information collection"

# ユーザ・グループ情報
log_info "Collecting user and group information"
safe_copy "/etc/passwd" "${AUTH_DIR}/"
safe_copy "/etc/shadow" "${AUTH_DIR}/"
safe_copy "/etc/group" "${AUTH_DIR}/"
safe_copy "/etc/gshadow" "${AUTH_DIR}/"
# NSS 経由（LDAP / SSSD 等）のユーザーも含めた一覧。応答しないディレクトリサーバーに備えて時間を区切る
if have_cmd getent; then
    capture "${AUTH_DIR}/getent_passwd.txt" run_limited 15 getent passwd
    capture "${AUTH_DIR}/getent_group.txt" run_limited 15 getent group
fi
# 各モジュールが調べたホームディレクトリの一覧（調べていない場所が分かるように）
{
    printf '# label\thome\tsource (passwd = from the user database, orphan = no passwd entry points here)\n'
    ldir_user_homes
} > "${AUTH_DIR}/user_homes.tsv"
if grep -q $'\torphan$' "${AUTH_DIR}/user_homes.tsv"; then
    log_info "[40_auth] Home directories without a passwd entry found (see config/user_homes.tsv, source=orphan)"
fi

# sudoers設定
log_info "Collecting sudo configuration"
safe_copy "/etc/sudoers" "${AUTH_DIR}/"
safe_copy "/etc/sudoers.d/" "${AUTH_DIR}/sudoers.d/"
safe_copy "/etc/sudo.conf" "${AUTH_DIR}/"
safe_copy "/etc/doas.conf" "${AUTH_DIR}/"

# PAM設定
log_info "Collecting PAM configuration"
safe_copy "/etc/pam.d/" "${AUTH_DIR}/pam.d/"
safe_copy "/etc/security/" "${AUTH_DIR}/security/"

# SSH設定
# 秘密鍵は名前ではなく中身（PRIVATE KEY）で判定して除外する。HostKey で
# ssh_host_*_key 以外の名前を付けた鍵も含む。除外したものは出力先に一度も書かない。
log_info "Collecting SSH configuration"
copy_config_tree "/etc/ssh" "${AUTH_DIR}/ssh" "${AUTH_DIR}/excluded_files.txt" 0

# 実際に効いている sshd の設定（Include / sshd_config.d を反映した値）。
# AuthorizedKeysFile や HostKey の場所はここから読む
# sshd -T は sshd が動いていないホスト（ソケット起動で /run/sshd が無い等）では失敗する。
# その場合は下で設定ファイルを直接読むので WARN にはせず、理由をファイルに残す。
SSHD_EFFECTIVE="${AUTH_DIR}/sshd_effective_config.txt"
SSHD_BIN=""
if have_cmd sshd; then SSHD_BIN="sshd"; elif [[ -x /usr/sbin/sshd ]]; then SSHD_BIN="/usr/sbin/sshd"; fi
if [[ -n "${SSHD_BIN}" ]] && ! capture_try "${SSHD_EFFECTIVE}" "${SSHD_BIN}" -T; then
    echo "# sshd -T failed (output above). AuthorizedKeysFile was read from sshd_config and sshd_config.d instead (Match blocks not evaluated)." >> "${SSHD_EFFECTIVE}"
    log_debug "[40_auth] sshd -T failed; falling back to the config files"
fi

# AuthorizedKeysFile の値（%h %u %% と ~ を含み得る。相対パスはホームからの相対）。
# sshd -T が使えなければ設定ファイルを直接読む（Match ブロックの中は評価しない）
AUTH_KEYS_PATTERNS=""
if [[ -s "${SSHD_EFFECTIVE}" ]] && grep -qi '^authorizedkeysfile ' "${SSHD_EFFECTIVE}"; then
    AUTH_KEYS_PATTERNS="$(awk 'tolower($1) == "authorizedkeysfile" { $1 = ""; print }' "${SSHD_EFFECTIVE}")"
else
    AUTH_KEYS_PATTERNS="$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
        | awk 'tolower($1) == "match" { exit } tolower($1) == "authorizedkeysfile" { $1 = ""; print; exit }')"
fi
[[ -n "${AUTH_KEYS_PATTERNS// /}" ]] || AUTH_KEYS_PATTERNS=".ssh/authorized_keys .ssh/authorized_keys2"

# ユーザごとのSSH設定（ホームは passwd から。/root と /home 以外も対象）
while IFS=$'\t' read -r username user_home home_src; do
    [[ -n "${user_home}" ]] || continue
    dst="${AUTH_DIR}/user_ssh/${username}"
    if [[ -d "${user_home}/.ssh" ]]; then
        log_info "Collecting SSH config for user: ${username}"
        ensure_dir "$dst"
        # 公開鍵・設定のみ。秘密鍵はコピーしない（名前は ssh_dir_listing.txt に残る）
        safe_copy "${user_home}/.ssh/authorized_keys" "${dst}/"
        safe_copy "${user_home}/.ssh/authorized_keys2" "${dst}/"
        safe_copy "${user_home}/.ssh/known_hosts" "${dst}/"
        safe_copy "${user_home}/.ssh/config" "${dst}/"
        # ログイン時に実行される（永続化に使われる）
        safe_copy "${user_home}/.ssh/rc" "${dst}/"
        safe_copy "${user_home}/.ssh/environment" "${dst}/"
        capture "${dst}/ssh_dir_listing.txt" ls -la "${user_home}/.ssh"
    fi
    # AuthorizedKeysFile が既定以外の場所を指している場合
    for pat in ${AUTH_KEYS_PATTERNS}; do
        [[ "$pat" = "none" ]] && continue
        # passwd に無いホーム（orphan）はユーザー名が分からないので %u を展開できない
        [[ "$pat" == *%u* && "${home_src}" != "passwd" ]] && continue
        f="${pat//%%/%}"
        f="${f//%h/${user_home}}"
        f="${f//%u/${username}}"
        f="${f/#\~/${user_home}}"
        [[ "$f" = /* ]] || f="${user_home}/${f}"
        case "$f" in
            "${user_home}/.ssh/authorized_keys"|"${user_home}/.ssh/authorized_keys2") continue ;;
        esac
        if [[ -f "$f" ]]; then
            flat="${f#/}"
            safe_copy "$f" "${dst}/authorized_keys_file__${flat//\//_}"
        fi
    done
done < <(ldir_user_homes)

# 現在ログイン中のユーザ
log_info "Collecting current login sessions"
capture "${AUTH_DIR}/who_all.txt" who -a
capture "${AUTH_DIR}/w_output.txt" w -h

# ログイン履歴分析
if [[ -e /var/log/wtmp ]]; then
    capture_try "${AUTH_DIR}/last_full.txt" last -Faixw || capture "${AUTH_DIR}/last_full.txt" last -a
fi

log_success "[40_auth] Authentication information collection completed"
exit 0
