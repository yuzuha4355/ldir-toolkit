#!/bin/bash
#
# Module: Filesystem Information
# ファイルシステム情報収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [70_filesystem] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

FS_DIR="${OUTPUT_DIR}/filesystem"
ensure_dir "${FS_DIR}" || { log_error "[70_filesystem] Failed to create ${FS_DIR}"; exit 1; }

log_info "[70_filesystem] Starting filesystem information collection"

# マウント情報
log_info "Collecting mount information"
capture "${FS_DIR}/mount_points.txt" mount
capture "${FS_DIR}/proc_mounts.txt" cat /proc/mounts
safe_copy "/etc/fstab" "${FS_DIR}/fstab.txt"

# ディスク情報
capture "${FS_DIR}/disk_usage_human.txt" df -h
capture "${FS_DIR}/disk_inode_usage.txt" df -i
capture "${FS_DIR}/block_devices_filesystems.txt" lsblk -f

# 最近変更されたファイル
log_info "Finding recently modified files"
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    find / "${LDIR_FIND_PRUNE[@]}" -type f -mtime -7 "${LDIR_FIND_LS[@]}" > "${FS_DIR}/modified_last_7days.txt" 2>/dev/null || log_debug "find reported errors while scanning / (expected for /proc etc.)"
else
    # fast mode: limit to high-signal paths to avoid long scans
    {
        for p in /etc /var/log /var/spool /root /home /tmp /var/tmp; do
            [[ -e "$p" ]] || continue
            find "$p" -xdev "${LDIR_FIND_PRUNE[@]}" -type f -mtime -7 "${LDIR_FIND_LS[@]}" 2>/dev/null
        done
    } > "${FS_DIR}/modified_last_7days.txt" 2>/dev/null || true
fi

find /tmp "${LDIR_FIND_PRUNE[@]}" -type f "${LDIR_FIND_LS[@]}" > "${FS_DIR}/tmp_files.txt" 2>/dev/null || true
find /var/tmp "${LDIR_FIND_PRUNE[@]}" -type f "${LDIR_FIND_LS[@]}" > "${FS_DIR}/var_tmp_files.txt" 2>/dev/null || true

# SUID/SGID ファイル（権限昇格に悪用される可能性）と
# ワールドライタブルファイル（脆弱性の可能性）
#
# 走査は 1 回にまとめる（別々に find を回すと同じツリーを 2 度歩く）。
#
# 所要時間は対象のファイル数に比例する。/opt や /usr/local に数百万ファイルある
# 実機では、キャッシュが効いていない初回の走査だけで 2 分を超えた。
# fast モードは初動用なので、この検索全体に時間の上限（既定 60 秒）を設ける。
# 上限に達した場合は、そこまでの結果を残し、WARN と scan_incomplete.txt で明示する。
# 1) どちらかの条件に当たるファイルの候補を 1 回の走査で集める
# 2) 候補（少数）だけを条件ごとに振り分ける
log_info "Finding SUID/SGID and world-writable files"

PERM_CANDIDATES="${FS_DIR}/.perm_candidates.tmp"
: > "${PERM_CANDIDATES}"
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    find / "${LDIR_FIND_PRUNE[@]}" -type f \( -perm -4000 -o -perm -2000 -o -perm -0002 \) -print0 \
        >> "${PERM_CANDIDATES}" 2>/dev/null || log_debug "find reported errors during permission search"
else
    # fast mode: focus on common abuse paths
    # 小さく、悪用されやすい場所から先に見る（上限に達しても重要な場所は済んでいる）
    SCAN_BUDGET="${LDIR_FAST_SCAN_BUDGET:-60}"
    if ! have_cmd timeout; then
        # timeout が無いと走査を途中で止められない。上限は場所の切れ目でしか効かない
        log_warn "[70_filesystem] 'timeout' is not available; the ${SCAN_BUDGET}s budget cannot interrupt a scan in progress"
    fi
    # /usr/bin /usr/sbin は SUID が普通に置かれる場所（v0.3.2 までは fast の対象外だった）。
    # 数千ファイル程度なので、巨大になり得る /usr/local /opt より先に見る。
    # /bin /sbin は usrmerge 環境では /usr へのリンクなので、別物のときだけ見る。
    scan_paths=(/tmp /var/tmp /dev/shm /etc /usr/bin /usr/sbin)
    for p in /bin /sbin; do
        [[ -L "$p" ]] || scan_paths+=("$p")
    done
    scan_paths+=(/usr/libexec /usr/local /opt)
    scan_start=${SECONDS}
    for p in "${scan_paths[@]}"; do
        [[ -e "$p" ]] || continue
        remaining=$(( SCAN_BUDGET - (SECONDS - scan_start) ))
        if [[ ${remaining} -le 0 ]]; then
            echo "$p: not scanned (time budget of ${SCAN_BUDGET}s used up)" >> "${FS_DIR}/scan_incomplete.txt"
            continue
        fi
        run_limited "${remaining}" find "$p" -xdev "${LDIR_FIND_PRUNE[@]}" -type f \( -perm -4000 -o -perm -2000 -o -perm -0002 \) -print0 \
            >> "${PERM_CANDIDATES}" 2>/dev/null
        if [[ $? -eq 124 ]]; then
            echo "$p: partially scanned (time budget of ${SCAN_BUDGET}s used up)" >> "${FS_DIR}/scan_incomplete.txt"
        fi
    done
    if [[ -s "${FS_DIR}/scan_incomplete.txt" ]]; then
        log_warn "[70_filesystem] SUID/SGID and world-writable search stopped at the ${SCAN_BUDGET}s budget; lists are partial (see filesystem/scan_incomplete.txt, or use --mode full)"
    fi
fi

# classify_candidates <出力ファイル> <find の条件（文字列）>
# 候補を xargs でまとめて find に渡し、条件に合うものだけ詳細表示する。
# （bash の read ループで 1 件ずつ読むと、候補が数万件ある実機で 20 秒以上かかった）
LS_ACTION="${LDIR_FIND_LS[*]}"
classify_candidates() {
    local out="$1" cond="$2"
    : > "$out"
    [[ -s "${PERM_CANDIDATES}" ]] || return 0
    # shellcheck disable=SC2016  # $@ は内側の sh で展開する
    xargs -0 -r sh -c 'find "$@" -maxdepth 0 '"${cond} ${LS_ACTION}" _ \
        < "${PERM_CANDIDATES}" >> "$out" 2>/dev/null || true
}

classify_candidates "${FS_DIR}/suid_sgid_files.txt" '\( -perm -4000 -o -perm -2000 \)'
classify_candidates "${FS_DIR}/world_writable_files.txt" '-perm -0002'

# 打ち切られた場合は、一覧そのものの先頭に明記する。
# 空の一覧だけを見た人が「該当なし」と読み違えないようにするため。
if [[ -s "${FS_DIR}/scan_incomplete.txt" ]]; then
    for list in "${FS_DIR}/suid_sgid_files.txt" "${FS_DIR}/world_writable_files.txt"; do
        {
            echo "# PARTIAL RESULT: the fast-mode time budget ran out before all locations were scanned."
            echo "# An empty or short list here does NOT mean no such files exist."
            echo "# Locations not fully scanned are listed in scan_incomplete.txt. Use --mode full for a complete list."
            cat "$list"
        } > "${list}.tmp" && mv -f "${list}.tmp" "$list"
    done
fi
rm -f "${PERM_CANDIDATES}"

# 隠しファイル（ドットファイル）
log_info "Finding hidden files in sensitive directories"
find /tmp /var/tmp /dev/shm "${LDIR_FIND_PRUNE[@]}" -name ".*" "${LDIR_FIND_LS[@]}" > "${FS_DIR}/hidden_files_sensitive.txt" 2>/dev/null || true

# /dev/shm の内容（メモリベースのファイル、マルウェアが使用することがある）
capture_partial "${FS_DIR}/dev_shm_contents.txt" ls -laR /dev/shm

# システムバイナリのハッシュ（改竄検出用）
log_info "Calculating hashes for system binaries"
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    if command -v sha256sum &> /dev/null; then
        # -exec ... + でまとめて渡す（1 ファイルごとに sha256sum を起動しない）
        find /bin /sbin /usr/bin /usr/sbin -type f -exec sha256sum {} + > "${FS_DIR}/system_binaries_hashes.txt" 2>/dev/null || log_warn "Binary hash calculation incomplete"
    fi
else
    echo "Skipped in fast mode (set LDIR_MODE=full to enable)" > "${FS_DIR}/system_binaries_hashes.txt"
fi

# 削除されたが開かれたままのファイル（プロセスが削除されたファイルを使用）
log_info "Finding deleted but open files"
# lsof +L1 は該当が無いと出力なしで 1 を返す
if have_cmd lsof; then
    capture_try "${FS_DIR}/deleted_open_files.txt" lsof +L1 \
        || [[ -s "${FS_DIR}/deleted_open_files.txt" ]] \
        || echo "lsof +L1: no deleted-but-open files (exit 1 with no output)" > "${FS_DIR}/deleted_open_files.txt"
else
    echo "lsof: command not available on this host" > "${FS_DIR}/deleted_open_files.txt"
fi

# パッケージマネージャでインストールされていないバイナリ
# 1 ファイルごとに dpkg -S / rpm -qf を呼ぶと数千回の起動で分単位かかるため、
# 「パッケージ所有ファイルの一覧」を一度だけ作り、実ファイル一覧と突き合わせる。
log_info "Finding unpackaged files in system directories"

list_system_binaries() {
    local d f
    for d in /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            [[ -f "$f" || -L "$f" ]] && echo "$f"
        done
    done | LC_ALL=C sort -u
}

# 所有ファイル一覧を正規化する: usrmerge 環境では /bin/ls として登録された
# ファイルが /usr/bin/ls に実在するため、/bin,/sbin,/lib* を /usr 配下にも展開する。
normalize_owned_list() {
    awk '{ print } /^\/(bin|sbin|lib|lib32|lib64|libx32)\// { print "/usr" $0 }' | LC_ALL=C sort -u
}

find_unpackaged() {
    local owned_cmd="$1" out="$2"
    local owned_tmp="${out}.owned.tmp" present_tmp="${out}.present.tmp"
    if eval "$owned_cmd" 2>/dev/null | normalize_owned_list > "$owned_tmp" && [[ -s "$owned_tmp" ]]; then
        list_system_binaries > "$present_tmp"
        LC_ALL=C comm -23 "$present_tmp" "$owned_tmp" > "$out"
    else
        log_warn "Could not build package file list for unpackaged-binary check: ${out##*/}"
    fi
    rm -f "$owned_tmp" "$present_tmp"
}

if have_cmd dpkg && compgen -G "/var/lib/dpkg/info/*.list" > /dev/null; then
    # Debian系。dpkg-divert / update-alternatives 由来のリンクは一覧に載らないため、
    # 結果は「要確認の候補」であり、即不審という意味ではない。
    find_unpackaged "cat /var/lib/dpkg/info/*.list" "${FS_DIR}/unpackaged_binaries_dpkg.txt"
fi

if have_cmd rpm && rpm -qa >/dev/null 2>&1 && [[ -n "$(rpm -qa 2>/dev/null | head -1)" ]]; then
    # RedHat系
    find_unpackaged "rpm -qal" "${FS_DIR}/unpackaged_binaries_rpm.txt"
fi

# /etc の内容リスト（設定ファイル全体像）
find /etc -type f "${LDIR_FIND_LS[@]}" > "${FS_DIR}/etc_file_list.txt" 2>/dev/null || true

# ディレクトリ構造（トップレベル）
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    tree -L 3 -a / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || ls -laR / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || true
else
    # fast mode: top-level only
    ls -la / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || true
fi

log_success "[70_filesystem] Filesystem information collection completed"
exit 0
