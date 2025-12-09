#!/bin/bash
#
# Module: Filesystem Information
# ファイルシステム情報収集モジュール
#

OUTPUT_DIR="$1"
FS_DIR="${OUTPUT_DIR}/filesystem"

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

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
find / -type f -mtime -7 -ls > "${FS_DIR}/modified_last_7days.txt" 2>/dev/null || log_warn "Find command failed (expected on some systems)"
find /tmp -type f -ls > "${FS_DIR}/tmp_files.txt" 2>/dev/null || true
find /var/tmp -type f -ls > "${FS_DIR}/var_tmp_files.txt" 2>/dev/null || true

# SUID/SGID ファイル（権限昇格に悪用される可能性）
log_info "Finding SUID/SGID files"
find / -type f \( -perm -4000 -o -perm -2000 \) -ls > "${FS_DIR}/suid_sgid_files.txt" 2>/dev/null || log_warn "SUID/SGID search failed"

# ワールドライタブルファイル（脆弱性の可能性）
log_info "Finding world-writable files"
find / -type f -perm -0002 -ls > "${FS_DIR}/world_writable_files.txt" 2>/dev/null || true

# 隠しファイル（ドットファイル）
log_info "Finding hidden files in sensitive directories"
find /tmp /var/tmp /dev/shm -name ".*" -ls > "${FS_DIR}/hidden_files_sensitive.txt" 2>/dev/null || true

# /dev/shm の内容（メモリベースのファイル、マルウェアが使用することがある）
ls -laR /dev/shm > "${FS_DIR}/dev_shm_contents.txt" 2>&1 || true

# システムバイナリのハッシュ（改竄検出用）
log_info "Calculating hashes for system binaries"
if command -v sha256sum &> /dev/null; then
    find /bin /sbin /usr/bin /usr/sbin -type f -exec sha256sum {} \; > "${FS_DIR}/system_binaries_hashes.txt" 2>/dev/null || log_warn "Binary hash calculation incomplete"
fi

# 削除されたが開かれたままのファイル（プロセスが削除されたファイルを使用）
log_info "Finding deleted but open files"
lsof +L1 > "${FS_DIR}/deleted_open_files.txt" 2>&1 || true

# パッケージマネージャでインストールされていないバイナリ
log_info "Finding unpackaged files in system directories"
# このチェックは時間がかかるため、主要なディレクトリのみ
if command -v dpkg &> /dev/null; then
    # Debian系: dpkg -S でパッケージに属さないファイルを探す
    for file in /usr/bin/* /usr/sbin/*; do
        if [[ -f "$file" ]]; then
            dpkg -S "$file" &>/dev/null || echo "$file" >> "${FS_DIR}/unpackaged_binaries_dpkg.txt"
        fi
    done 2>/dev/null || true
fi

if command -v rpm &> /dev/null; then
    # RedHat系: rpm -qf でパッケージに属さないファイルを探す
    for file in /usr/bin/* /usr/sbin/*; do
        if [[ -f "$file" ]]; then
            rpm -qf "$file" &>/dev/null || echo "$file" >> "${FS_DIR}/unpackaged_binaries_rpm.txt"
        fi
    done 2>/dev/null || true
fi

# /etc の内容リスト（設定ファイル全体像）
find /etc -type f -ls > "${FS_DIR}/etc_file_list.txt" 2>/dev/null || true

# ディレクトリ構造（トップレベル）
tree -L 3 -a / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || ls -laR / > "${FS_DIR}/directory_tree.txt" 2>/dev/null || true

log_success "[70_filesystem] Filesystem information collection completed"
exit 0
