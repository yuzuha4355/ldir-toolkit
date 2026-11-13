#!/bin/bash
#
# Module: Virtualization
# 仮想化の情報収集モジュール
#
# ゲスト側: このホスト自身が VM か（種別、判定の根拠、ゲストエージェント）
# ホスト側: このホストが VM / システムコンテナを動かしているか
#   libvirt (KVM / QEMU)、Proxmox VE、LXC、LXD / Incus、VirtualBox、Xen dom0、
#   稼働中のハイパーバイザのプロセス
#
# 方針:
#   - 管理コマンド（virsh, qm, pct 等）はデーモンが応答しないと固まるので、すべて時間を区切る
#   - VM のディスクイメージ・メモリの中身は取らない（パス・存在・サイズのみ）
#   - 鍵の置き場（/etc/libvirt/secrets, /etc/pve/priv 等）と秘密鍵は収集しない
#   - VM 定義の中の秘匿値（VNC/SPICE のパスワード、cloud-init の user-data 等）は伏せる
#   - 対象ホストを変えない: 設定ファイルを新たに作るコマンド（root で初めて動かす
#     VBoxManage、LXD の lxc クライアント）は使わない。LXD / Incus は API を直接読む
#   - アプリケーションコンテナ（Docker 等）は 30_containers が扱う
#
# LDIR_VIRT_ROOT を付けると /etc /var /run /proc /sys /dev をその下から読む（テスト用）。
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [35_virtualization] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

V_DIR="${OUTPUT_DIR}/virtualization"
G_DIR="${V_DIR}/guest"
H_DIR="${V_DIR}/host"
ensure_dir "${G_DIR}" || { log_error "[35_virtualization] Failed to create ${G_DIR}"; exit 1; }

R="${LDIR_VIRT_ROOT:-}"
T="${LDIR_VIRT_TIMEOUT:-20}"
EXCLUDED="${V_DIR}/excluded_files.txt"
INCOMPLETE="${V_DIR}/scan_incomplete.txt"
HOST_FOUND=0
# VM ごとの詳細の問い合わせに使える時間（fast: 60 秒、full: 無制限）。
# 数百台の VM を抱えるホストで fast モードが読めない時間にならないようにする
if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
    VIRT_BUDGET="${LDIR_VIRT_BUDGET:-0}"
else
    VIRT_BUDGET="${LDIR_VIRT_BUDGET:-60}"
fi
VIRT_START=${SECONDS}
BUDGET_HIT=0

# 単体で実行された場合（ldir-collect.sh を経由しない）
if [[ -z "${VIRT_TYPE:-}" || -n "${R}" ]]; then
    # shellcheck source=../lib/detect_distro_advanced.sh
    source "${SCRIPT_DIR}/lib/detect_distro_advanced.sh"
    detect_virtualization
fi
if [[ -z "${LDIR_LOG_SINCE_EPOCH:-}" ]]; then
    ldir_resolve_log_settings || { log_error "[35_virtualization] ${LDIR_SETTINGS_ERROR}"; exit 1; }
fi

log_info "[35_virtualization] Starting virtualization information collection (this host: ${VIRT_TYPE})"

# budget_ok <何を飛ばすか>: 時間の上限内なら 0。超えたら記録して 1
budget_ok() {
    [[ "${VIRT_BUDGET}" = "0" ]] && return 0
    if (( SECONDS - VIRT_START < VIRT_BUDGET )); then
        return 0
    fi
    echo "$1: not collected (time budget of ${VIRT_BUDGET}s used up; use --mode full or LDIR_VIRT_BUDGET=0)" >> "${INCOMPLETE}"
    if [[ ${BUDGET_HIT} -eq 0 ]]; then
        BUDGET_HIT=1
        log_warn "[35_virtualization] per-VM queries stopped at the ${VIRT_BUDGET}s budget; details are partial (see virtualization/scan_incomplete.txt)"
    fi
    return 1
}

# capture_redacted <出力> [--json] <コマンド...>
# 時間制限付きで実行し、秘匿値を伏せて保存する。失敗したら .failed.txt に残して WARN。
capture_redacted() {
    local out="$1"; shift
    local json=0 tmp
    if [[ "$1" = "--json" ]]; then json=1; shift; fi
    tmp="${out}.tmp"
    ensure_dir "$(dirname "$out")"
    if capture_try "$tmp" run_limited "$T" "$@"; then
        if [[ ${json} -eq 1 ]]; then
            ldir_json_split < "$tmp" | redact_config > "$out"
        else
            redact_config < "$tmp" > "$out"
        fi
        rm -f "$tmp"
        return 0
    fi
    mv -f "$tmp" "${out}.failed.txt" 2>/dev/null
    log_warn "[35_virtualization] Command failed or timed out: $* -> ${out##*/}.failed.txt"
    return 1
}

# ファイル名に使える形にする（スナップショット名等）
safe_name() {
    local n="${1//[^A-Za-z0-9._-]/_}"
    echo "${n:-_}"
}

# 稼働中のプロセスの comm 一覧（1 度だけ読む）
PROC_COMMS="$(cat "${R}"/proc/[0-9]*/comm 2>/dev/null | LC_ALL=C sort -u)"
proc_running() {
    local p
    for p in "$@"; do
        grep -qx -- "$p" <<< "${PROC_COMMS}" && return 0
    done
    return 1
}

# =====================================================================
# ゲスト側: このホスト自身は VM か
# =====================================================================
log_info "Collecting guest-side virtualization information"
{
    echo "Result: ${VIRT_TYPE} (${VIRT_SOURCE})"
    echo "# The result also appears in metadata/manifest.txt (Virtualization)."
    echo "# Sources below are what this host reported; any of them can be faked by a hypervisor."
    echo ""
    echo "== systemd-detect-virt"
    if [[ -z "${R}" ]] && have_cmd systemd-detect-virt; then
        for opt in "" --vm --container; do
            # shellcheck disable=SC2086  # 空の opt は引数にしない
            printf 'systemd-detect-virt %s: %s\n' "${opt:-(default)}" "$(run_limited 10 systemd-detect-virt ${opt} 2>&1)"
        done
    else
        echo "not available"
    fi
    echo ""
    echo "== DMI (/sys/class/dmi/id)"
    for k in sys_vendor product_name product_version product_serial product_uuid board_vendor board_name \
             bios_vendor bios_version chassis_vendor chassis_type; do
        f="${R}/sys/class/dmi/id/${k}"
        [[ -r "$f" ]] && printf '%s: %s\n' "$k" "$(cat "$f" 2>/dev/null)"
    done
    [[ -d "${R}/sys/class/dmi/id" ]] || echo "not available"
    echo ""
    echo "== /proc/cpuinfo"
    if [[ -r "${R}/proc/cpuinfo" ]]; then
        if grep -qE '^flags[[:space:]]*:.*[[:space:]]hypervisor([[:space:]]|$)' "${R}/proc/cpuinfo"; then
            echo "hypervisor flag: present"
        elif grep -qE '^flags[[:space:]]*:' "${R}/proc/cpuinfo"; then
            echo "hypervisor flag: absent"
        else
            echo "hypervisor flag: no flags line (not x86?)"
        fi
        grep -m1 -E '^(model name|Hardware|CPU implementer)' "${R}/proc/cpuinfo"
    else
        echo "not readable"
    fi
    echo ""
    echo "== /sys/hypervisor"
    for k in type uuid version/major version/minor; do
        f="${R}/sys/hypervisor/${k}"
        [[ -r "$f" ]] && printf '%s: %s\n' "$k" "$(cat "$f" 2>/dev/null)"
    done
    [[ -d "${R}/sys/hypervisor" ]] || echo "not present"
    echo ""
    echo "== /proc/xen"
    if [[ -r "${R}/proc/xen/capabilities" ]]; then
        echo "capabilities: $(cat "${R}/proc/xen/capabilities" 2>/dev/null) (control_d = this is dom0)"
    else
        echo "not present"
    fi
    if [[ -z "${R}" ]] && have_cmd virt-what; then
        echo ""
        echo "== virt-what"
        run_limited 20 virt-what 2>&1
    fi
} > "${G_DIR}/virt_detection.txt"

# 仮想化に関係するカーネルモジュール（ゲスト: virtio, vmw_*, hv_*; ホスト: kvm, vhost, vfio）
if [[ -r "${R}/proc/modules" ]]; then
    grep -E '^(virtio[^ ]*|vmw_[^ ]*|vmxnet3|vboxguest|vboxsf|vboxvideo|vboxdrv|vboxnet[^ ]*|hv_[^ ]*|hyperv_[^ ]*|xen[^ ]*|kvm[^ ]*|vhost[^ ]*|vfio[^ ]*) ' \
        "${R}/proc/modules" > "${V_DIR}/virt_kernel_modules.txt" 2>/dev/null \
        || echo "no virtualization-related kernel modules loaded" > "${V_DIR}/virt_kernel_modules.txt"
fi

# ゲストエージェント。多くはハイパーバイザやクラウドの側から、このゲストの中で
# コマンドを実行する経路になる（侵入経路・横展開の経路として見る）
AGENTS_FOUND=0
agent_row() {
    local name="$1" bins="$2" procs="$3" paths="$4" note="$5"
    local b d p x found="" running=""
    for b in ${bins}; do
        for d in /usr/bin /usr/sbin /bin /sbin /usr/local/bin /usr/local/sbin /usr/libexec /snap/bin; do
            if [[ -x "${R}${d}/${b}" ]]; then
                found="${found}${found:+ }${d}/${b}"
                break
            fi
        done
    done
    for p in ${paths}; do
        # shellcheck disable=SC2086  # glob の展開が目的
        for x in "${R}"${p}; do
            [[ -e "$x" ]] && found="${found}${found:+ }${x#"${R}"}"
        done
    done
    for p in ${procs}; do
        proc_running "$p" && running="${running}${running:+ }${p}"
    done
    [[ -n "${found}${running}" ]] || return 0
    AGENTS_FOUND=1
    printf '%s\t%s\t%s\t%s\n' "$name" "${found:--}" "${running:-no}" "$note"
}
{
    printf 'AGENT\tINSTALLED\tRUNNING\tWHY IT MATTERS\n'
    agent_row qemu-guest-agent "qemu-ga" "qemu-ga" "/etc/qemu/qemu-ga.conf /etc/sysconfig/qemu-ga" \
        "the hypervisor host can run commands in this guest (guest-exec) unless blocked in the agent config"
    agent_row open-vm-tools "vmtoolsd vmware-toolbox-cmd" "vmtoolsd" "/etc/vmware-tools" \
        "vCenter can run programs in this guest (Guest Operations) with guest credentials"
    agent_row virtualbox-guest-additions "VBoxService VBoxControl" "VBoxService" "/opt/VBoxGuestAdditions-*" \
        "the VirtualBox host can run programs in this guest (guestcontrol)"
    agent_row hyperv-daemons "hv_kvp_daemon hypervkvpd hv_vss_daemon hypervvssd" \
        "hv_kvp_daemon hypervkvpd hv_vss_daemon hypervvssd" "" \
        "Hyper-V host exchanges data (KVP) and triggers snapshots (VSS) through these"
    agent_row xe-guest-utilities "xe-daemon" "xe-daemon" "" "XenServer / XCP-ng guest metrics"
    agent_row parallels-tools "prltoolsd" "prltoolsd" "" "Parallels host integration"
    agent_row spice-vdagent "spice-vdagentd spice-vdagent" "spice-vdagentd spice-vdagent" "" \
        "clipboard and file transfer between the host console and this guest"
    agent_row amazon-ssm-agent "amazon-ssm-agent" "amazon-ssm-agen" "/etc/amazon/ssm" \
        "AWS Systems Manager can run commands here (Run Command / Session Manager)"
    agent_row google-guest-agent "google_guest_agent google_osconfig_agent" "google_guest_ag google_osconfig" "" \
        "manages users and SSH keys from instance metadata; OS Config can run scripts"
    agent_row azure-linux-agent "waagent" "" "/etc/waagent.conf /var/lib/waagent" \
        "Azure Run Command and VM extensions run through it"
} > "${G_DIR}/guest_agents.tsv"
if [[ ${AGENTS_FOUND} -eq 0 ]]; then
    echo "No known guest or cloud agent found" >> "${G_DIR}/guest_agents.tsv"
fi

# エージェントの設定（どの操作を許しているか。qemu-ga の BLACKLIST / allow-rpcs 等）
copy_config_file "${R}/etc/qemu/qemu-ga.conf" "${G_DIR}/agent_config/qemu-ga.conf" "${EXCLUDED}"
copy_config_file "${R}/etc/sysconfig/qemu-ga" "${G_DIR}/agent_config/sysconfig_qemu-ga" "${EXCLUDED}"
copy_config_file "${R}/etc/default/qemu-guest-agent" "${G_DIR}/agent_config/default_qemu-guest-agent" "${EXCLUDED}"
copy_config_file "${R}/etc/vmware-tools/tools.conf" "${G_DIR}/agent_config/vmware-tools.conf" "${EXCLUDED}"
copy_config_file "${R}/etc/waagent.conf" "${G_DIR}/agent_config/waagent.conf" "${EXCLUDED}"
copy_config_tree "${R}/etc/amazon/ssm" "${G_DIR}/agent_config/amazon_ssm" "${EXCLUDED}" 1
# エージェントのログ（期間と容量の上限は 60_logs と同じ）
collect_log_group guest_agent "${R}/var/log" "${G_DIR}/agent_logs" "${V_DIR}" \
    'vmware-vmsvc*.log*' 'vmware-vmtoolsd*.log*' 'vmware-vmusr*.log*' 'qemu-ga*' 'vboxadd*.log*' \
    'waagent.log*' 'amazon/ssm'

# =====================================================================
# ホスト側: このホストは VM / システムコンテナを動かしているか
# =====================================================================
log_info "Collecting host-side virtualization information"

# --- 稼働中のハイパーバイザのプロセス（管理ツールが無い・壊されている場合の手がかり）---
VM_PROCS=0
UNMANAGED_QEMU=""
{
    printf 'PID\tUID\tCOMM\tCMDLINE\n'
    for d in "${R}"/proc/[0-9]*; do
        comm=""
        read -r comm < "${d}/comm" 2>/dev/null || continue
        case "${comm}" in
            qemu-system-*|qemu-kvm|qemu-dm|kvm|VBoxHeadless|VirtualBoxVM|VirtualBox|VBoxSVC|vmware-vmx| \
            firecracker|cloud-hyperviso*|crosvm|xenstored|xenconsoled|libvirtd|virtqemud|virtxend|virtlxcd| \
            virtlogd|pmxcfs|pvedaemon|pveproxy|qmeventd|lxd|incusd|lxc-start|lxc-monitord) ;;
            *) continue ;;
        esac
        cmdline="$(tr '\0' ' ' < "${d}/cmdline" 2>/dev/null)"
        # カーネルスレッドは cmdline が空
        [[ -n "${cmdline}" ]] || continue
        uid="$(awk '/^Uid:/ { print $2; exit }' "${d}/status" 2>/dev/null)"
        printf '%s\t%s\t%s\t%s\n' "${d##*/}" "${uid:-?}" "${comm}" "${cmdline}"
        case "${comm}" in
            qemu-system-*|qemu-kvm|kvm|VBoxHeadless|VirtualBoxVM|vmware-vmx|firecracker|cloud-hyperviso*|crosvm)
                VM_PROCS=$((VM_PROCS + 1)) ;;
        esac
        # libvirt / Proxmox が起動した QEMU は、コマンドラインにそれぞれの管理下のパスが入る。
        # どちらでもない QEMU は、管理ツールの外で手動で起動された VM（調査対象）
        case "${comm}" in
            qemu-system-*|qemu-kvm|kvm)
                case "${cmdline}" in
                    *libvirt*|*qemu-server*) ;;
                    *) UNMANAGED_QEMU="${UNMANAGED_QEMU}${UNMANAGED_QEMU:+ }${d##*/}" ;;
                esac ;;
        esac
    done
} > "${V_DIR}/hypervisor_processes.tsv"
if [[ $(wc -l < "${V_DIR}/hypervisor_processes.tsv") -gt 1 ]]; then
    HOST_FOUND=1
    log_info "[35_virtualization] Hypervisor-related processes running (${VM_PROCS} VM process(es)); see virtualization/hypervisor_processes.tsv"
else
    rm -f "${V_DIR}/hypervisor_processes.tsv"
fi
if [[ -n "${UNMANAGED_QEMU}" ]]; then
    log_warn "[35_virtualization] QEMU running outside libvirt and Proxmox (PID ${UNMANAGED_QEMU}); a manually started VM can hide activity from the host (see virtualization/hypervisor_processes.tsv)"
fi

# KVM を使えるか（使えるだけでは「VM を動かしている」とはみなさない）
if [[ -e "${R}/dev/kvm" ]]; then
    {
        ls -l "${R}/dev/kvm" 2>&1
        for p in "${R}"/sys/module/kvm_intel/parameters/nested "${R}"/sys/module/kvm_amd/parameters/nested; do
            [[ -r "$p" ]] && echo "${p#"${R}"}: $(cat "$p" 2>/dev/null)"
        done
    } > "${V_DIR}/kvm_device.txt"
fi

# 所属すると VM / コンテナを操作できるグループ（libvirt, lxd, incus は実質 root）
if [[ -r "${R}/etc/group" ]]; then
    grep -E '^(libvirt|libvirt-qemu|libvirtd|kvm|lxd|incus|incus-admin|vboxusers):' "${R}/etc/group" \
        > "${V_DIR}/privileged_groups.txt" 2>/dev/null || rm -f "${V_DIR}/privileged_groups.txt"
fi

# --- libvirt (KVM / QEMU / Xen / LXC driver) ---
if have_cmd virsh || [[ -d "${R}/etc/libvirt" ]] || proc_running libvirtd virtqemud virtxend virtlxcd; then
    HOST_FOUND=1
    L_DIR="${H_DIR}/libvirt"
    ensure_dir "${L_DIR}"
    log_info "[35_virtualization] libvirt found"
    # /etc/libvirt/qemu/*.xml は永続的な VM 定義（VNC/SPICE のパスワードを含み得るので伏せる）。
    # /etc/libvirt/secrets/ はディスク暗号化等の鍵の値なので取らない
    copy_config_tree "${R}/etc/libvirt" "${L_DIR}/etc_libvirt" "${EXCLUDED}" 1

    SOCK=""
    for s in /run/libvirt/libvirt-sock /run/libvirt/virtqemud-sock /run/libvirt/virtxend-sock \
             /run/libvirt/virtlxcd-sock /var/run/libvirt/libvirt-sock; do
        if [[ -e "${R}${s}" ]]; then
            SOCK="${SOCK}${SOCK:+ }${s}"
        fi
    done

    if have_cmd virsh; then
        if [[ -z "${SOCK}" ]]; then
            echo "virsh is installed but no libvirt daemon socket was found; not queried" > "${L_DIR}/virsh_not_queried.txt"
            log_debug "[35_virtualization] virsh present, no libvirt socket"
        elif capture "${L_DIR}/virsh_version.txt" run_limited "$T" virsh version; then
            capture "${L_DIR}/virsh_uri.txt" run_limited "$T" virsh uri
            capture "${L_DIR}/nodeinfo.txt" run_limited "$T" virsh nodeinfo
            capture "${L_DIR}/domains.txt" run_limited "$T" virsh list --all
            capture "${L_DIR}/networks.txt" run_limited "$T" virsh net-list --all
            capture "${L_DIR}/storage_pools.txt" run_limited "$T" virsh pool-list --all --details
            # 鍵の一覧（UUID と用途のみ。値は読まない）
            capture "${L_DIR}/secrets_list.txt" run_limited "$T" virsh secret-list

            : > "${L_DIR}/disk_images.txt"
            # 名前に空白を含み得るので 1 行ずつ読む（fd 3: 中のコマンドに標準入力を取られないように）
            while IFS= read -r u <&3; do
                [[ -n "$u" ]] || continue
                budget_ok "libvirt domain ${u}" || continue
                dd="${L_DIR}/domains/${u}"
                ensure_dir "$dd"
                capture "${dd}/dominfo.txt" run_limited "$T" virsh dominfo "$u"
                # 既定の dumpxml は VNC/SPICE のパスワードを含めない（--security-info を付けない）。
                # それでも伏せる処理は通す
                capture_redacted "${dd}/domain.xml" virsh dumpxml "$u"
                capture "${dd}/domblklist.txt" run_limited "$T" virsh domblklist "$u" --details
                capture "${dd}/domiflist.txt" run_limited "$T" virsh domiflist "$u"
                capture "${dd}/snapshots.txt" run_limited "$T" virsh snapshot-list "$u" --parent
                while IFS= read -r sn <&4; do
                    [[ -n "$sn" ]] || continue
                    capture_redacted "${dd}/snapshot_$(safe_name "$sn").xml" virsh snapshot-dumpxml "$u" "$sn"
                done 4< <(run_limited "$T" virsh snapshot-list "$u" --name 2>/dev/null)
                # ディスクイメージ: パスと存在・サイズのみ（中身は読まない）
                awk 'NR > 2 && ($1 == "file" || $1 == "block") && $4 != "-" && $4 != "" { $1 = $2 = $3 = ""; sub(/^ +/, ""); print }' \
                    "${dd}/domblklist.txt" 2>/dev/null | while IFS= read -r img; do
                        if [[ -e "${R}${img}" ]]; then
                            printf '%s\t%s\n' "$u" "$(ls -lL "${R}${img}" 2>&1)"
                        else
                            printf '%s\tmissing: %s\n' "$u" "$img"
                        fi
                    done >> "${L_DIR}/disk_images.txt"
            done 3< <(run_limited "$T" virsh list --all --uuid 2>/dev/null)
            while IFS= read -r n <&3; do
                [[ -n "$n" ]] || continue
                budget_ok "libvirt network ${n}" || continue
                capture_redacted "${L_DIR}/networks/$(safe_name "$n").xml" virsh net-dumpxml "$n"
                # 停止中のネットワークでは失敗する（想定内）
                capture_try "${L_DIR}/networks/$(safe_name "$n").dhcp_leases.txt" run_limited "$T" virsh net-dhcp-leases "$n"
            done 3< <(run_limited "$T" virsh net-list --all --name 2>/dev/null)
            while IFS= read -r p <&3; do
                [[ -n "$p" ]] || continue
                budget_ok "libvirt storage pool ${p}" || continue
                capture_redacted "${L_DIR}/storage_pools/$(safe_name "$p").xml" virsh pool-dumpxml "$p"
                # 停止中のプールでは失敗する（想定内）
                capture_try "${L_DIR}/storage_pools/$(safe_name "$p").volumes.txt" run_limited "$T" virsh vol-list "$p" --details
            done 3< <(run_limited "$T" virsh pool-list --all --name 2>/dev/null)
        else
            log_warn "[35_virtualization] libvirt socket exists (${SOCK}) but virsh did not answer; VM list not collected"
        fi
    fi

    # 状態ファイル・イメージの置き場の一覧（中身は取らない）
    {
        for p in /var/lib/libvirt/images /var/lib/libvirt/qemu/save /var/lib/libvirt/qemu/snapshot \
                 /var/lib/libvirt/qemu/dump /var/lib/libvirt/qemu/nvram /var/lib/libvirt/boot; do
            [[ -d "${R}${p}" ]] && find "${R}${p}" -maxdepth 2 "${LDIR_FIND_LS[@]}" 2>/dev/null
        done
    } > "${L_DIR}/image_and_state_files.txt"
    collect_log_group libvirt "${R}/var/log/libvirt" "${L_DIR}/logs" "${V_DIR}" '*'
fi

# --- Proxmox VE ---
if [[ -d "${R}/etc/pve" ]] || have_cmd qm || have_cmd pct; then
    HOST_FOUND=1
    P_DIR="${H_DIR}/proxmox"
    ensure_dir "${P_DIR}"
    log_info "[35_virtualization] Proxmox VE found"
    have_cmd pveversion && capture "${P_DIR}/pveversion.txt" run_limited "$T" pveversion -v
    if [[ -d "${R}/etc/pve" ]]; then
        # /etc/pve は pmxcfs（FUSE）。クラスタが壊れていると読むだけで固まるので、先に確かめる
        if run_limited 10 ls "${R}/etc/pve" > /dev/null 2>&1; then
            # VM / コンテナの定義（qemu-server/*.conf, lxc/*.conf、スナップショットも同じファイル）、
            # storage.cfg, user.cfg, datacenter.cfg, firewall/ 等。
            # priv/（鍵、パスワードのハッシュ、API トークン）と *.key は取らない
            copy_config_tree "${R}/etc/pve" "${P_DIR}/etc_pve" "${EXCLUDED}" 1
        else
            echo "/etc/pve did not respond within 10s (pmxcfs hung?); not copied" > "${P_DIR}/etc_pve_not_copied.txt"
            log_warn "[35_virtualization] /etc/pve did not respond within 10s; VM definitions not collected"
        fi
    fi
    have_cmd qm && capture "${P_DIR}/qm_list.txt" run_limited "$T" qm list
    have_cmd pct && capture "${P_DIR}/pct_list.txt" run_limited "$T" pct list
    have_cmd pvesm && capture "${P_DIR}/pvesm_status.txt" run_limited "$T" pvesm status
    # クラスタでないノードでは失敗する（想定内）
    have_cmd pvecm && capture_try "${P_DIR}/pvecm_status.txt" run_limited "$T" pvecm status
    {
        for p in /var/lib/vz/images /var/lib/vz/dump /var/lib/vz/template; do
            [[ -d "${R}${p}" ]] && find "${R}${p}" -maxdepth 2 "${LDIR_FIND_LS[@]}" 2>/dev/null
        done
    } > "${P_DIR}/image_and_backup_files.txt"
    # タスクログ（VM の作成・起動・移行・バックアップ等の操作記録）と Web UI / API のアクセスログ
    collect_log_group pve_tasks "${R}/var/log/pve/tasks" "${P_DIR}/tasks" "${V_DIR}" '*'
    collect_log_group pve_proxy "${R}/var/log/pveproxy" "${P_DIR}/pveproxy" "${V_DIR}" 'access.log*'
fi

# --- LXC（lxc-* ツール）---
if have_cmd lxc-ls || [[ -d "${R}/var/lib/lxc" ]] || [[ -d "${R}/etc/lxc" ]]; then
    HOST_FOUND=1
    X_DIR="${H_DIR}/lxc"
    ensure_dir "${X_DIR}"
    log_info "[35_virtualization] LXC found"
    have_cmd lxc-ls && capture "${X_DIR}/lxc-ls.txt" run_limited "$T" lxc-ls --fancy
    copy_config_tree "${R}/etc/lxc" "${X_DIR}/etc_lxc" "${EXCLUDED}" 1
    for c in "${R}"/var/lib/lxc/*/config; do
        [[ -f "$c" ]] || continue
        name="${c%/config}"; name="${name##*/}"
        copy_config_file "$c" "${X_DIR}/containers/$(safe_name "$name").config" "${EXCLUDED}"
    done
    if [[ -d "${R}/var/lib/lxc" ]]; then
        find "${R}/var/lib/lxc" -maxdepth 2 "${LDIR_FIND_LS[@]}" > "${X_DIR}/var_lib_lxc_listing.txt" 2>/dev/null
    fi
fi

# --- LXD / Incus（API をソケットから直接読む）---
# lxc / incus クライアントは root で初めて動かすと設定ディレクトリを作るため使わない。
# 応答は 1 行の JSON なので、項目ごとに改行してから秘匿値（cloud-init の user-data、
# environment.*、パスワード類）を伏せる。
lxd_like() {
    local name="$1" sock="$2" logdir="$3"
    local dir="${H_DIR}/${name}" tmp
    [[ -e "${R}${sock}" ]] || return 0
    HOST_FOUND=1
    ensure_dir "$dir"
    log_info "[35_virtualization] ${name} API socket found: ${sock}"
    echo "${sock}" > "${dir}/api_socket.txt"
    if ! have_cmd curl; then
        echo "curl not available; the ${name} API was not queried" > "${dir}/not_queried.txt"
        log_warn "[35_virtualization] ${name} is present but curl is missing; instances not listed"
        return 0
    fi
    lxd_api() {
        local out="$1" path="$2"
        tmp="${dir}/.api.tmp"
        if run_limited "$T" curl -sS --unix-socket "${R}${sock}" "http://${name}${path}" > "$tmp" 2>&1 \
            && ! grep -q '"type":"error"' "$tmp"; then
            ldir_json_split < "$tmp" | redact_config > "${dir}/${out}"
            rm -f "$tmp"
            return 0
        fi
        mv -f "$tmp" "${dir}/${out}.failed.txt" 2>/dev/null
        return 1
    }
    if ! lxd_api server.json "/1.0"; then
        log_warn "[35_virtualization] ${name} API did not answer (see virtualization/host/${name}/server.json.failed.txt)"
        return 0
    fi
    # 既定以外のプロジェクトのインスタンスも含める（古い版は all-projects を知らない）
    lxd_api instances.json "/1.0/instances?recursion=1&all-projects=true" \
        || lxd_api instances.json "/1.0/instances?recursion=1" \
        || log_warn "[35_virtualization] ${name}: instance list failed"
    lxd_api profiles.json "/1.0/profiles?recursion=1" || log_warn "[35_virtualization] ${name}: profile list failed"
    lxd_api networks.json "/1.0/networks?recursion=1" || log_warn "[35_virtualization] ${name}: network list failed"
    lxd_api storage_pools.json "/1.0/storage-pools?recursion=1" || log_warn "[35_virtualization] ${name}: storage pool list failed"
    # 信頼されたクライアント証明書（遠隔から操作できる相手。追加されていないか）
    lxd_api certificates.json "/1.0/certificates?recursion=1" || log_warn "[35_virtualization] ${name}: certificate list failed"
    lxd_api projects.json "/1.0/projects?recursion=1" || true
    collect_log_group "${name}_logs" "${R}${logdir%/*}" "${dir}/logs" "${V_DIR}" "${logdir##*/}"
}
lxd_like lxd /var/snap/lxd/common/lxd/unix.socket /var/snap/lxd/common/lxd/logs
lxd_like lxd /var/lib/lxd/unix.socket /var/log/lxd
lxd_like incus /var/lib/incus/unix.socket /var/log/incus

# --- VirtualBox ---
VB_DIR="${H_DIR}/virtualbox"
if have_cmd VBoxManage; then
    HOST_FOUND=1
    ensure_dir "${VB_DIR}"
    log_info "[35_virtualization] VirtualBox found"
    if [[ -e "${R}/root/.config/VirtualBox/VirtualBox.xml" || -e "${R}/root/.VirtualBox/VirtualBox.xml" ]]; then
        capture "${VB_DIR}/version.txt" run_limited "$T" VBoxManage --version
        capture "${VB_DIR}/vms.txt" run_limited "$T" VBoxManage list vms
        capture "${VB_DIR}/runningvms.txt" run_limited "$T" VBoxManage list runningvms
        for u in $(sed -n 's/.*{\([0-9a-fA-F-]*\)}$/\1/p' "${VB_DIR}/vms.txt" 2>/dev/null); do
            budget_ok "VirtualBox VM ${u}" || continue
            capture_redacted "${VB_DIR}/vms/${u}.txt" VBoxManage showvminfo "$u" --machinereadable
        done
    else
        # root で初めて VBoxManage を動かすと設定ファイルを作り、VBoxSVC を起動する（ホストの変更）
        echo "VBoxManage was not run: root has no VirtualBox configuration; running it would create one and start VBoxSVC. Per-user VMs: see user_*/ below." \
            > "${VB_DIR}/not_queried.txt"
    fi
fi
# ユーザーごとの VM 登録（VirtualBox の VM はユーザーごと。root の VBoxManage からは見えない）
if [[ -z "${R}" ]]; then
    while IFS=$'\t' read -r username user_home _; do
        [[ -n "$user_home" ]] || continue
        for x in "${user_home}/.config/VirtualBox/VirtualBox.xml" "${user_home}/.VirtualBox/VirtualBox.xml"; do
            [[ -f "$x" ]] || continue
            HOST_FOUND=1
            copy_config_file "$x" "${VB_DIR}/user_${username}/VirtualBox.xml" "${EXCLUDED}"
        done
        if [[ -d "${user_home}/VirtualBox VMs" ]]; then
            HOST_FOUND=1
            ensure_dir "${VB_DIR}/user_${username}"
            find "${user_home}/VirtualBox VMs" -maxdepth 2 "${LDIR_FIND_LS[@]}" > "${VB_DIR}/user_${username}/vm_files.txt" 2>/dev/null
        fi
    done < <(ldir_user_homes)
fi

# --- Xen（dom0 のみ）---
XEN_DOM0=0
grep -qs control_d "${R}/proc/xen/capabilities" && XEN_DOM0=1
if [[ ${XEN_DOM0} -eq 1 ]] || { have_cmd xl && [[ -d "${R}/etc/xen" ]]; }; then
    HOST_FOUND=1
    XEN_DIR="${H_DIR}/xen"
    ensure_dir "${XEN_DIR}"
    log_info "[35_virtualization] Xen found (dom0=${XEN_DOM0})"
    copy_config_tree "${R}/etc/xen" "${XEN_DIR}/etc_xen" "${EXCLUDED}" 1
    if [[ ${XEN_DOM0} -eq 1 ]] && have_cmd xl; then
        capture "${XEN_DIR}/xl_info.txt" run_limited "$T" xl info
        capture "${XEN_DIR}/xl_list.txt" run_limited "$T" xl list
        capture_redacted "${XEN_DIR}/xl_list_long.json" --json xl list -l
    elif [[ ${XEN_DOM0} -eq 0 ]]; then
        echo "xl is installed but this is not a Xen dom0; not queried" > "${XEN_DIR}/xl_not_queried.txt"
    fi
    collect_log_group xen "${R}/var/log/xen" "${XEN_DIR}/logs" "${V_DIR}" '*'
fi

if [[ ${HOST_FOUND} -eq 0 ]]; then
    log_info "[35_virtualization] No hypervisor or VM manager detected on this host"
    {
        echo "No hypervisor, VM manager or system-container manager detected on this host."
        echo "Checked: libvirt (virsh, /etc/libvirt, daemons), Proxmox VE (/etc/pve, qm, pct),"
        echo "LXC (lxc-ls, /var/lib/lxc, /etc/lxc), LXD / Incus (API sockets), VirtualBox"
        echo "(VBoxManage, per-user VirtualBox.xml), Xen dom0 (/proc/xen, xl), and running"
        echo "hypervisor processes (QEMU, VirtualBox, VMware, Firecracker, Cloud Hypervisor, crosvm)."
        if [[ -e "${R}/dev/kvm" ]]; then
            echo "/dev/kvm exists: this host can run KVM guests, but nothing using it was found."
        fi
        echo "Whether this host is itself a VM: guest/virt_detection.txt"
    } > "${V_DIR}/no_hypervisor_detected.txt"
fi

log_success "[35_virtualization] Virtualization information collection completed"
exit 0
