#!/bin/bash
#
# Module: Web Browser Artifacts
# Webブラウザアーティファクト収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [80_web] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

WEB_DIR="${OUTPUT_DIR}/web"
ensure_dir "${WEB_DIR}" || { log_error "[80_web] Failed to create ${WEB_DIR}"; exit 1; }

log_info "[80_web] Starting web browser artifacts collection"

# fast mode defaults to disabled (PII/secret-rich)
if [[ "${LDIR_ENABLE_WEB:-1}" != "1" ]]; then
    log_info "[80_web] Disabled by LDIR_ENABLE_WEB=${LDIR_ENABLE_WEB}"
    echo "web module disabled" > "${WEB_DIR}/disabled.txt"
    exit 0
fi

# ホームは passwd から（/root と /home/* 以外も対象）。
# ホームの中はリンクをたどらずに写す（ldir_copy_user_files / ldir_copy_user_tree）。
# たどらなかったリンク等は web/excluded_files.txt に残る。
WEB_EXCLUDED="${WEB_DIR}/excluded_files.txt"

# web_copy <ホーム> <ラベル> <プロファイルのディレクトリ> <コピー先> <ファイル名>...
web_copy() {
    local home="$1" user="$2" prof="$3" dst="$4" rel f
    shift 4
    local -a pairs=()
    rel="${prof#"${home%/}/"}"
    for f in "$@"; do pairs+=("${rel}/${f}" "${dst}/${f}"); done
    ldir_copy_user_files "$home" "$user" "${WEB_EXCLUDED}" "${pairs[@]}"
}

while IFS=$'\t' read -r username user_home _; do
    if [[ -z "$user_home" || ! -d "$user_home" ]]; then
        continue
    fi
    log_debug "Checking browser data for user: ${username}"

    # Firefox
    if [[ -d "${user_home}/.mozilla/firefox/" ]]; then
        log_info "  - Firefox profiles found"
        for profile in "${user_home}/.mozilla/firefox/"*.default* "${user_home}/.mozilla/firefox/"*release*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                label="$(ldir_item_label "$username" "$profile")"
                log_info "    - Profile: ${profile_name}"
                d="${WEB_DIR}/firefox_${label}_${profile_name}"
                mkdir -p "$d"
                # 履歴・ブックマーク、Cookie、ダウンロード履歴、フォーム履歴、セッション、
                # パスワード（暗号化されている）
                web_copy "$user_home" "$username" "$profile" "$d" \
                    places.sqlite places.sqlite-wal cookies.sqlite downloads.sqlite formhistory.sqlite \
                    sessionstore.jsonlz4 logins.json key4.db
                ldir_copy_user_tree "$user_home" "$username" "${WEB_EXCLUDED}" \
                    "${profile#"${user_home%/}/"}/sessionstore-backups" "${d}/sessionstore-backups"
            fi
        done
    fi

    # Google Chrome / Chromium / Brave / Edge（同じ形式のプロファイル）
    for browser in google-chrome:chrome chromium:chromium BraveSoftware/Brave-Browser:brave microsoft-edge:edge; do
        bdir="${browser%%:*}"; bname="${browser##*:}"
        [[ -d "${user_home}/.config/${bdir}/" ]] || continue
        log_info "  - ${bname} profiles found"
        for profile in "${user_home}/.config/${bdir}/Default" "${user_home}/.config/${bdir}/Profile"*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                label="$(ldir_item_label "$username" "$profile")"
                log_info "    - Profile: ${profile_name}"
                d="${WEB_DIR}/${bname}_${label}_${profile_name}"
                mkdir -p "$d"
                case "${bname}" in
                    chrome)
                        # 履歴、Cookie、ログインデータ（暗号化）、ブックマーク、トップサイト、
                        # Web Data（フォーム履歴等）、セッション
                        web_copy "$user_home" "$username" "$profile" "$d" \
                            History History-journal Cookies Cookies-journal "Login Data" Bookmarks \
                            "Top Sites" "Web Data" "Current Session" "Last Session" ;;
                    chromium)
                        web_copy "$user_home" "$username" "$profile" "$d" History Cookies "Login Data" Bookmarks ;;
                    *)
                        web_copy "$user_home" "$username" "$profile" "$d" History Cookies ;;
                esac
            fi
        done
    done

    # Opera
    if [[ -d "${user_home}/.config/opera/" ]]; then
        log_info "  - Opera profile found"
        label="$(ldir_item_label "$username" "${user_home%/}/.config/opera")"
        mkdir -p "${WEB_DIR}/opera_${label}"
        web_copy "$user_home" "$username" "${user_home%/}/.config/opera" "${WEB_DIR}/opera_${label}" History Cookies
    fi

done < <(ldir_user_homes)

log_success "[80_web] Web browser artifacts collection completed"
exit 0
