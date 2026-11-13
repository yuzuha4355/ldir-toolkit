#!/bin/bash
#
# Module: Persistence Mechanisms
# 永続化機構収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [50_persistence] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PERSIST_DIR="${OUTPUT_DIR}/persistence"
ensure_dir "${PERSIST_DIR}" || { log_error "[50_persistence] Failed to create ${PERSIST_DIR}"; exit 1; }

log_info "[50_persistence] Starting persistence mechanism collection"

# systemd units（systemdが存在する場合）
if command -v systemctl &> /dev/null; then
    log_info "Collecting systemd configuration"

    # 稼働中の systemd への問い合わせ。コンテナ等で systemd が PID 1 でない場合は
    # 必ず失敗するので行わない（ユニットファイルのコピーは下で常に行う）。
    if [[ -d /run/systemd/system ]]; then
        capture "${PERSIST_DIR}/systemd_unit_files.txt" systemctl list-unit-files
        capture "${PERSIST_DIR}/systemd_units_all.txt" systemctl list-units --all
        capture "${PERSIST_DIR}/systemd_timers.txt" systemctl list-timers --all
        capture "${PERSIST_DIR}/systemd_status.txt" systemctl status
    else
        echo "systemd is installed but not running as PID 1; runtime queries skipped" > "${PERSIST_DIR}/systemd_not_running.txt"
    fi

    # カスタムユニットファイルのコピー
    safe_copy "/etc/systemd/system/" "${PERSIST_DIR}/systemd_system/"
    safe_copy "/usr/lib/systemd/system/" "${PERSIST_DIR}/systemd_usr_lib/"
    # usrmerge 環境では /lib は /usr/lib へのリンク。同じ実体なら二重に取らない。
    if [[ "$(readlink -f /lib/systemd/system 2>/dev/null)" != "$(readlink -f /usr/lib/systemd/system 2>/dev/null)" ]]; then
        safe_copy "/lib/systemd/system/" "${PERSIST_DIR}/systemd_lib/"
    fi

    # ユーザ単位の systemd user units
    for user_home in /root /home/*; do
        if [[ -d "$user_home" ]]; then
            username="$(basename "$user_home")"
            if [[ -d "${user_home}/.config/systemd/user" ]]; then
                safe_copy "${user_home}/.config/systemd/user/" "${PERSIST_DIR}/systemd_user_${username}/"
            fi
        fi
    done
fi

# SysVinit スクリプト
log_info "Collecting init scripts"
safe_copy "/etc/init.d/" "${PERSIST_DIR}/init.d/"
safe_copy "/etc/rc.local" "${PERSIST_DIR}/"

# Upstart（古いUbuntu等）
safe_copy "/etc/init/" "${PERSIST_DIR}/upstart/"

# cron関連
log_info "Collecting cron configuration"
safe_copy "/etc/crontab" "${PERSIST_DIR}/"
safe_copy "/etc/cron.d/" "${PERSIST_DIR}/cron.d/"
safe_copy "/etc/cron.daily/" "${PERSIST_DIR}/cron.daily/"
safe_copy "/etc/cron.hourly/" "${PERSIST_DIR}/cron.hourly/"
safe_copy "/etc/cron.weekly/" "${PERSIST_DIR}/cron.weekly/"
safe_copy "/etc/cron.monthly/" "${PERSIST_DIR}/cron.monthly/"
safe_copy "/var/spool/cron/" "${PERSIST_DIR}/user_crontabs/"

# cronのログ
crontab -l > "${PERSIST_DIR}/root_crontab.txt" 2>&1 || echo "No root crontab" > "${PERSIST_DIR}/root_crontab.txt"

# 各ユーザのcrontab
# crontab を持つユーザの分だけ残す（"no crontab for X" だけのファイルを量産しない）
if have_cmd crontab; then
    ensure_dir "${PERSIST_DIR}/user_crontab_l"
    while IFS=: read -r user _; do
        [[ -n "$user" ]] || continue
        out="${PERSIST_DIR}/user_crontab_l/${user}.txt"
        if ! crontab -l -u "$user" > "$out" 2>/dev/null || [[ ! -s "$out" ]]; then
            rm -f "$out"
        fi
    done < /etc/passwd
fi

# at jobs
log_info "Collecting at jobs"
safe_copy "/var/spool/at/" "${PERSIST_DIR}/at_jobs/"
atq > "${PERSIST_DIR}/at_queue.txt" 2>&1 || true

# デスクトップ自動起動
log_info "Collecting desktop autostart configurations"
safe_copy "/etc/xdg/autostart/" "${PERSIST_DIR}/autostart_system/"

for user_home in /root /home/*; do
    if [[ -d "$user_home" ]]; then
        username="$(basename "$user_home")"
        safe_copy "${user_home}/.config/autostart/" "${PERSIST_DIR}/autostart_user_${username}/"
    fi
done

# LD_PRELOAD悪用の検出
log_info "Scanning for LD_PRELOAD references"
# 実機では /etc の全文検索に数十秒かかることがある。上限を設け、打ち切った場合は記録する
run_limited 60 grep -r "LD_PRELOAD" /etc/ > "${PERSIST_DIR}/ld_preload_references.txt" 2>/dev/null
case $? in
    0) ;;
    1) echo "No LD_PRELOAD references found" > "${PERSIST_DIR}/ld_preload_references.txt" ;;
    124) log_warn "[50_persistence] LD_PRELOAD scan of /etc hit the 60s limit; result is partial" ;;
    *) [[ -s "${PERSIST_DIR}/ld_preload_references.txt" ]] || echo "No LD_PRELOAD references found" > "${PERSIST_DIR}/ld_preload_references.txt" ;;
esac

# 環境変数での永続化
env | grep -E "(LD_PRELOAD|LD_LIBRARY_PATH)" > "${PERSIST_DIR}/env_preload.txt" 2>&1 || echo "No suspicious env vars" > "${PERSIST_DIR}/env_preload.txt"

# シェル初期化ファイル（マルウェアが改変することがある）
log_info "Collecting shell initialization files"
for user_home in /root /home/*; do
    if [[ -d "$user_home" ]]; then
        username="$(basename "$user_home")"
        mkdir -p "${PERSIST_DIR}/shell_init/${username}"
        safe_copy "${user_home}/.bashrc" "${PERSIST_DIR}/shell_init/${username}/"
        safe_copy "${user_home}/.bash_profile" "${PERSIST_DIR}/shell_init/${username}/"
        safe_copy "${user_home}/.profile" "${PERSIST_DIR}/shell_init/${username}/"
        safe_copy "${user_home}/.zshrc" "${PERSIST_DIR}/shell_init/${username}/"
        safe_copy "${user_home}/.zprofile" "${PERSIST_DIR}/shell_init/${username}/"
    fi
done

safe_copy "/etc/profile" "${PERSIST_DIR}/"
safe_copy "/etc/bash.bashrc" "${PERSIST_DIR}/"
safe_copy "/etc/profile.d/" "${PERSIST_DIR}/profile.d/"

log_success "[50_persistence] Persistence mechanism collection completed"
exit 0
