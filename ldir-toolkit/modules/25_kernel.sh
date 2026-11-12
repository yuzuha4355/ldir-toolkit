#!/bin/bash
#
# Module: Kernel & Privilege Surface
# カーネル・権限まわりの収集モジュール（rootkit / 権限昇格の調査用）
#
# 収集対象:
#   - ロード済みカーネルモジュール、taint 状態、隠しモジュールの簡易照合
#   - eBPF プログラム / マップ / リンク
#   - 動的リンカの差し込み設定 (/etc/ld.so.preload 等)
#   - file capabilities を持つファイル
#   - sysctl、カーネルログ
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [25_kernel] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

K_DIR="${OUTPUT_DIR}/kernel"
ensure_dir "${K_DIR}" || { log_error "[25_kernel] Failed to create ${K_DIR}"; exit 1; }

log_info "[25_kernel] Starting kernel information collection"

# --- カーネルモジュール ---
log_info "Collecting kernel modules"
if [[ -r /proc/modules ]]; then
    cat /proc/modules > "${K_DIR}/proc_modules.txt" 2>/dev/null || true
fi
if have_cmd lsmod; then
    lsmod > "${K_DIR}/lsmod.txt" 2>&1 || true
fi

# taint: 0 以外は、署名なし/ツリー外モジュールのロード等があったことを示す
if [[ -r /proc/sys/kernel/tainted ]]; then
    {
        echo "tainted=$(cat /proc/sys/kernel/tainted)"
        echo "# 0 = not tainted. Bit meanings: Documentation/admin-guide/tainted-kernels.rst"
    } > "${K_DIR}/tainted.txt"
fi

# モジュールごとの詳細（taint フラグ、ロード元）
if [[ -d /sys/module ]]; then
    {
        printf '%s\t%s\t%s\t%s\n' "module" "initstate" "taint" "srcversion"
        for m in /sys/module/*; do
            [[ -f "$m/initstate" ]] || continue     # initstate を持つ = ロード可能モジュール
            printf '%s\t%s\t%s\t%s\n' \
                "${m##*/}" \
                "$(cat "$m/initstate" 2>/dev/null)" \
                "$(cat "$m/taint" 2>/dev/null)" \
                "$(cat "$m/srcversion" 2>/dev/null)"
        done
    } > "${K_DIR}/sys_module_details.tsv" 2>/dev/null || true

    # 隠しモジュールの簡易照合:
    # /sys/module には居るのに /proc/modules に居ないモジュールを列挙する。
    # （一覧から自身を外す種類の rootkit は片方にだけ残ることがある。
    #   空であることは「安全」の証明ではない。）
    if [[ -r /proc/modules ]]; then
        sys_tmp="${K_DIR}/.sys.tmp"; proc_tmp="${K_DIR}/.proc.tmp"
        for m in /sys/module/*; do
            [[ -f "$m/initstate" ]] && echo "${m##*/}"
        done | LC_ALL=C sort -u > "$sys_tmp"
        awk '{print $1}' /proc/modules | LC_ALL=C sort -u > "$proc_tmp"
        LC_ALL=C comm -23 "$sys_tmp" "$proc_tmp" > "${K_DIR}/modules_in_sysfs_not_in_proc.txt"
        LC_ALL=C comm -13 "$sys_tmp" "$proc_tmp" > "${K_DIR}/modules_in_proc_not_in_sysfs.txt"
        rm -f "$sys_tmp" "$proc_tmp"
        if [[ -s "${K_DIR}/modules_in_sysfs_not_in_proc.txt" || -s "${K_DIR}/modules_in_proc_not_in_sysfs.txt" ]]; then
            log_warn "[25_kernel] Module lists in /proc/modules and /sys/module differ (see kernel/modules_in_*.txt)"
        fi
    fi
fi

# 起動時にロードされるモジュールの設定（永続化に使われる）
safe_copy "/etc/modules" "${K_DIR}/etc_modules"
safe_copy "/etc/modules-load.d/" "${K_DIR}/modules-load.d/"
safe_copy "/etc/modprobe.d/" "${K_DIR}/modprobe.d/"
safe_copy "/usr/lib/modules-load.d/" "${K_DIR}/usr_lib_modules-load.d/"

# ツリー外モジュール（extra / updates / dkms 配下）
if [[ -d "/lib/modules/$(uname -r)" ]]; then
    find "/lib/modules/$(uname -r)" \( -path '*/extra/*' -o -path '*/updates/*' -o -path '*/dkms/*' \) \
        -type f "${LDIR_FIND_LS[@]}" > "${K_DIR}/out_of_tree_modules.txt" 2>/dev/null || true
fi

# --- 動的リンカへの差し込み ---
# /etc/ld.so.preload は通常存在しない。存在する場合は全プロセスにライブラリが注入される。
log_info "Collecting dynamic linker configuration"
if [[ -e /etc/ld.so.preload ]]; then
    safe_copy "/etc/ld.so.preload" "${K_DIR}/ld.so.preload"
    log_warn "[25_kernel] /etc/ld.so.preload exists (libraries are injected into every process)"
else
    echo "/etc/ld.so.preload does not exist (normal)" > "${K_DIR}/ld.so.preload.absent.txt"
fi
safe_copy "/etc/ld.so.conf" "${K_DIR}/ld.so.conf"
safe_copy "/etc/ld.so.conf.d/" "${K_DIR}/ld.so.conf.d/"

# --- eBPF ---
log_info "Collecting eBPF state"
if have_cmd bpftool; then
    run_limited 20 bpftool prog show > "${K_DIR}/bpf_progs.txt" 2>&1 || true
    run_limited 20 bpftool map show > "${K_DIR}/bpf_maps.txt" 2>&1 || true
    run_limited 20 bpftool link show > "${K_DIR}/bpf_links.txt" 2>&1 || true
    run_limited 20 bpftool net show > "${K_DIR}/bpf_net.txt" 2>&1 || true
    run_limited 20 bpftool cgroup tree > "${K_DIR}/bpf_cgroup_tree.txt" 2>&1 || true
else
    echo "bpftool not installed; eBPF programs could not be enumerated" > "${K_DIR}/bpf_unavailable.txt"
fi
# pin された BPF オブジェクト
if [[ -d /sys/fs/bpf ]]; then
    find /sys/fs/bpf "${LDIR_FIND_LS[@]}" > "${K_DIR}/bpf_pinned.txt" 2>/dev/null || true
fi
# 各プロセスが保持する BPF 関連 fd（bpftool が無い環境での手がかり）
{
    for fd in /proc/[0-9]*/fd/*; do
        target="$(readlink "$fd" 2>/dev/null)" || continue
        case "$target" in
            anon_inode:bpf-*) echo "$fd -> $target" ;;
        esac
    done
} > "${K_DIR}/bpf_fds.txt" 2>/dev/null || true

# --- file capabilities ---
# SUID を使わずに特権を持たせる手段。cap_setuid / cap_sys_admin 等は権限昇格に直結する。
log_info "Finding files with capabilities"
if have_cmd getcap; then
    if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
        getcap -r / 2>/dev/null | grep -vF "${OUTPUT_DIR%/}/" > "${K_DIR}/file_capabilities.txt" || true
    else
        # fast mode: 実行ファイルが置かれる場所と、悪用されやすい場所に限定
        {
            for p in /usr/bin /usr/sbin /usr/local /usr/lib /usr/libexec /opt /home /root /tmp /var/tmp /dev/shm; do
                [[ -e "$p" ]] || continue
                getcap -r "$p" 2>/dev/null
            done
        } | grep -vF "${OUTPUT_DIR%/}/" > "${K_DIR}/file_capabilities.txt" || true
    fi
else
    echo "getcap not installed; file capabilities could not be enumerated" > "${K_DIR}/file_capabilities_unavailable.txt"
fi

# --- カーネル設定・状態 ---
log_info "Collecting kernel settings"
if have_cmd sysctl; then
    sysctl -a > "${K_DIR}/sysctl_all.txt" 2>/dev/null || true
fi
safe_copy "/etc/sysctl.conf" "${K_DIR}/sysctl.conf"
safe_copy "/etc/sysctl.d/" "${K_DIR}/sysctl.d/"

# 調査で先に見る値を抜き出しておく
{
    for k in kernel/modules_disabled kernel/kptr_restrict kernel/dmesg_restrict \
             kernel/unprivileged_bpf_disabled kernel/yama/ptrace_scope \
             kernel/kexec_load_disabled kernel/randomize_va_space kernel/core_pattern \
             kernel/modprobe kernel/unprivileged_userns_clone; do
        [[ -r "/proc/sys/$k" ]] && echo "${k//\//.} = $(cat "/proc/sys/$k" 2>/dev/null)"
    done
} > "${K_DIR}/security_sysctls.txt" 2>/dev/null || true

# LSM / lockdown / Secure Boot
[[ -r /sys/kernel/security/lsm ]] && cat /sys/kernel/security/lsm > "${K_DIR}/lsm.txt" 2>/dev/null
[[ -r /sys/kernel/security/lockdown ]] && cat /sys/kernel/security/lockdown > "${K_DIR}/lockdown.txt" 2>/dev/null
if have_cmd mokutil; then
    mokutil --sb-state > "${K_DIR}/secure_boot.txt" 2>&1 || true
fi

# カーネルログ
if have_cmd dmesg; then
    dmesg -T > "${K_DIR}/dmesg.txt" 2>/dev/null || dmesg > "${K_DIR}/dmesg.txt" 2>&1 || true
fi

log_success "[25_kernel] Kernel information collection completed"
exit 0
