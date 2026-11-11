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
mount > "${FS_DIR}/mount_points.txt" 2>&1
cat /proc/mounts > "${FS_DIR}/proc_mounts.txt" 2>&1
cat /etc/fstab > "${FS_DIR}/fstab.txt" 2>&1

# ディスク情報
df -h > "${FS_DIR}/disk_usage_human.txt" 2>&1
df -i > "${FS_DIR}/disk_inode_usage.txt" 2>&1
lsblk -f > "${FS_DIR}/block_devices_filesystems.txt" 2>&1 || true

# 最近変更されたファイル
log_info "Finding recently modified files"
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    find / "${LDIR_FIND_PRUNE[@]}" -type f -mtime -7 -ls > "${FS_DIR}/modified_last_7days.txt" 2>/dev/null || log_debug "find reported errors while scanning / (expected for /proc etc.)"
else
    # fast mode: limit to high-signal paths to avoid long scans
    {
        for p in /etc /var/log /var/spool /root /home /tmp /var/tmp; do
            [[ -e "$p" ]] || continue
            find "$p" -xdev "${LDIR_FIND_PRUNE[@]}" -type f -mtime -7 -ls 2>/dev/null
        done
    } > "${FS_DIR}/modified_last_7days.txt" 2>/dev/null || true
fi

find /tmp "${LDIR_FIND_PRUNE[@]}" -type f -ls > "${FS_DIR}/tmp_files.txt" 2>/dev/null || true
find /var/tmp "${LDIR_FIND_PRUNE[@]}" -type f -ls > "${FS_DIR}/var_tmp_files.txt" 2>/dev/null || true

# SUID/SGID ファイル（権限昇格に悪用される可能性）
log_info "Finding SUID/SGID files"
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    find / "${LDIR_FIND_PRUNE[@]}" -type f \( -perm -4000 -o -perm -2000 \) -ls > "${FS_DIR}/suid_sgid_files.txt" 2>/dev/null || log_debug "find reported errors during SUID/SGID search"

    # ワールドライタブルファイル（脆弱性の可能性）
    log_info "Finding world-writable files"
    find / "${LDIR_FIND_PRUNE[@]}" -type f -perm -0002 -ls > "${FS_DIR}/world_writable_files.txt" 2>/dev/null || true
else
    # fast mode: focus on common abuse paths
    {
        for p in /etc /usr/local /opt /tmp /var/tmp /dev/shm; do
            [[ -e "$p" ]] || continue
            find "$p" -xdev "${LDIR_FIND_PRUNE[@]}" -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null
        done
    } > "${FS_DIR}/suid_sgid_files.txt" 2>/dev/null || true

    {
        for p in /etc /usr/local /opt /tmp /var/tmp /dev/shm; do
            [[ -e "$p" ]] || continue
            find "$p" -xdev "${LDIR_FIND_PRUNE[@]}" -type f -perm -0002 -ls 2>/dev/null
        done
    } > "${FS_DIR}/world_writable_files.txt" 2>/dev/null || true
fi

# 隠しファイル（ドットファイル）
log_info "Finding hidden files in sensitive directories"
find /tmp /var/tmp /dev/shm "${LDIR_FIND_PRUNE[@]}" -name ".*" -ls > "${FS_DIR}/hidden_files_sensitive.txt" 2>/dev/null || true

# /dev/shm の内容（メモリベースのファイル、マルウェアが使用することがある）
ls -laR /dev/shm > "${FS_DIR}/dev_shm_contents.txt" 2>&1 || true

# システムバイナリのハッシュ（改竄検出用）
log_info "Calculating hashes for system binaries"
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    if command -v sha256sum &> /dev/null; then
        find /bin /sbin /usr/bin /usr/sbin -type f -exec sha256sum {} \; > "${FS_DIR}/system_binaries_hashes.txt" 2>/dev/null || log_warn "Binary hash calculation incomplete"
    fi
else
    echo "Skipped in fast mode (set LDIR_MODE=full to enable)" > "${FS_DIR}/system_binaries_hashes.txt"
fi

# 削除されたが開かれたままのファイル（プロセスが削除されたファイルを使用）
log_info "Finding deleted but open files"
lsof +L1 > "${FS_DIR}/deleted_open_files.txt" 2>&1 || true

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
find /etc -type f -ls > "${FS_DIR}/etc_file_list.txt" 2>/dev/null || true

# ディレクトリ構造（トップレベル）
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    tree -L 3 -a / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || ls -laR / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || true
else
    # fast mode: top-level only
    ls -la / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || true
fi

log_success "[70_filesystem] Filesystem information collection completed"
exit 0
