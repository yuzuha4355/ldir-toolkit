#!/bin/bash
#
# Module: Web Browser Artifacts
# Webブラウザアーティファクト収集モジュール
#

OUTPUT_DIR="$1"
WEB_DIR="${OUTPUT_DIR}/web"

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

log_info "[80_web] Starting web browser artifacts collection"

for user_home in /root /home/*; do
    if [[ ! -d "$user_home" ]]; then
        continue
    fi
    
    username="$(basename "$user_home")"
    log_info "Collecting browser data for user: ${username}"
    
    # Firefox
    if [[ -d "${user_home}/.mozilla/firefox/" ]]; then
        log_info "  - Firefox profiles found"
        for profile in "${user_home}/.mozilla/firefox/"*.default* "${user_home}/.mozilla/firefox/"*release*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                log_info "    - Profile: ${profile_name}"
                
                mkdir -p "${WEB_DIR}/firefox_${username}_${profile_name}"
                
                # 履歴・ブックマーク
                safe_copy "${profile}/places.sqlite" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                safe_copy "${profile}/places.sqlite-wal" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                
                # Cookie
                safe_copy "${profile}/cookies.sqlite" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                
                # ダウンロード履歴
                safe_copy "${profile}/downloads.sqlite" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                
                # フォーム履歴
                safe_copy "${profile}/formhistory.sqlite" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                
                # セッション情報
                safe_copy "${profile}/sessionstore.jsonlz4" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                safe_copy "${profile}/sessionstore-backups/" "${WEB_DIR}/firefox_${username}_${profile_name}/sessionstore-backups/"
                
                # パスワード（暗号化されている）
                safe_copy "${profile}/logins.json" "${WEB_DIR}/firefox_${username}_${profile_name}/"
                safe_copy "${profile}/key4.db" "${WEB_DIR}/firefox_${username}_${profile_name}/"
            fi
        done
    fi
    
    # Google Chrome
    if [[ -d "${user_home}/.config/google-chrome/" ]]; then
        log_info "  - Chrome profiles found"
        for profile in "${user_home}/.config/google-chrome/Default" "${user_home}/.config/google-chrome/Profile"*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                log_info "    - Profile: ${profile_name}"
                
                mkdir -p "${WEB_DIR}/chrome_${username}_${profile_name}"
                
                # 履歴
                safe_copy "${profile}/History" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                safe_copy "${profile}/History-journal" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                
                # Cookie
                safe_copy "${profile}/Cookies" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                safe_copy "${profile}/Cookies-journal" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                
                # ログインデータ（暗号化）
                safe_copy "${profile}/Login Data" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                
                # ブックマーク
                safe_copy "${profile}/Bookmarks" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                
                # トップサイト
                safe_copy "${profile}/Top Sites" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                
                # Web Data（フォーム履歴等）
                safe_copy "${profile}/Web Data" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                
                # セッション
                safe_copy "${profile}/Current Session" "${WEB_DIR}/chrome_${username}_${profile_name}/"
                safe_copy "${profile}/Last Session" "${WEB_DIR}/chrome_${username}_${profile_name}/"
            fi
        done
    fi
    
    # Chromium
    if [[ -d "${user_home}/.config/chromium/" ]]; then
        log_info "  - Chromium profiles found"
        for profile in "${user_home}/.config/chromium/Default" "${user_home}/.config/chromium/Profile"*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                
                mkdir -p "${WEB_DIR}/chromium_${username}_${profile_name}"
                
                safe_copy "${profile}/History" "${WEB_DIR}/chromium_${username}_${profile_name}/"
                safe_copy "${profile}/Cookies" "${WEB_DIR}/chromium_${username}_${profile_name}/"
                safe_copy "${profile}/Login Data" "${WEB_DIR}/chromium_${username}_${profile_name}/"
                safe_copy "${profile}/Bookmarks" "${WEB_DIR}/chromium_${username}_${profile_name}/"
            fi
        done
    fi
    
    # Opera
    if [[ -d "${user_home}/.config/opera/" ]]; then
        log_info "  - Opera profile found"
        mkdir -p "${WEB_DIR}/opera_${username}"
        safe_copy "${user_home}/.config/opera/History" "${WEB_DIR}/opera_${username}/"
        safe_copy "${user_home}/.config/opera/Cookies" "${WEB_DIR}/opera_${username}/"
    fi
    
    # Brave
    if [[ -d "${user_home}/.config/BraveSoftware/Brave-Browser/" ]]; then
        log_info "  - Brave profile found"
        for profile in "${user_home}/.config/BraveSoftware/Brave-Browser/Default" "${user_home}/.config/BraveSoftware/Brave-Browser/Profile"*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                mkdir -p "${WEB_DIR}/brave_${username}_${profile_name}"
                safe_copy "${profile}/History" "${WEB_DIR}/brave_${username}_${profile_name}/"
                safe_copy "${profile}/Cookies" "${WEB_DIR}/brave_${username}_${profile_name}/"
            fi
        done
    fi
    
    # Edge
    if [[ -d "${user_home}/.config/microsoft-edge/" ]]; then
        log_info "  - Edge profile found"
        for profile in "${user_home}/.config/microsoft-edge/Default" "${user_home}/.config/microsoft-edge/Profile"*; do
            if [[ -d "$profile" ]]; then
                profile_name="$(basename "$profile")"
                mkdir -p "${WEB_DIR}/edge_${username}_${profile_name}"
                safe_copy "${profile}/History" "${WEB_DIR}/edge_${username}_${profile_name}/"
                safe_copy "${profile}/Cookies" "${WEB_DIR}/edge_${username}_${profile_name}/"
            fi
        done
    fi
    
done

log_success "[80_web] Web browser artifacts collection completed"
exit 0
