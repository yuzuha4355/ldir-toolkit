#!/bin/bash
#
# Module: Containers & Kubernetes
# コンテナ / Kubernetes 収集モジュール
#
# このホストが「コンテナを動かす側」である場合の情報を集める。
# （このホスト自身がコンテナ内かどうかは 90_custom_environment が扱う）
#
# 方針:
#   - ランタイムへの問い合わせは時間制限付き（デーモンが応答しない場合に備える）
#   - inspect の Env は redact_env で秘匿値を伏せる
#   - 秘密鍵・kubeconfig・Secret の実体は収集しない
#   - コンテナ内部のファイルシステムやログ本体は収集しない（容量が読めないため）
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [30_containers] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

C_DIR="${OUTPUT_DIR}/containers"
ensure_dir "${C_DIR}" || { log_error "[30_containers] Failed to create ${C_DIR}"; exit 1; }

log_info "[30_containers] Starting container information collection"

ensure_dir "${C_DIR}/config"
CMD_TIMEOUT="${LDIR_CONTAINER_TIMEOUT:-20}"
FOUND=0

# out <file> <cmd...> : 時間制限付きで実行し、出力を保存
out() {
    local file="$1"; shift
    ensure_dir "$(dirname "$file")"
    if ! run_limited "${CMD_TIMEOUT}" "$@" > "$file" 2>&1; then
        log_warn "[30_containers] Command failed or timed out: $*"
        return 1
    fi
}

# Docker / Podman は CLI がほぼ同じなので共通化する
collect_docker_like() {
    local cli="$1"
    local dir="${C_DIR}/${cli}"

    have_cmd "$cli" || return 0
    FOUND=1
    log_info "[30_containers] ${cli} found"
    ensure_dir "$dir"

    "$cli" --version > "${dir}/version.txt" 2>&1 || true

    # デーモンに届かなければ、以降の問い合わせは行わない
    if ! out "${dir}/info.txt" "$cli" info; then
        log_info "[30_containers] ${cli} is installed but not responding; skipping runtime queries"
        return 0
    fi

    out "${dir}/ps_all.txt" "$cli" ps -a --no-trunc || true
    out "${dir}/images.txt" "$cli" images --no-trunc --digests || true
    out "${dir}/networks.txt" "$cli" network ls --no-trunc || true
    out "${dir}/volumes.txt" "$cli" volume ls || true

    # コンテナごとの詳細（特権、マウント、capabilities、起動コマンド）
    local ids id
    ids="$(run_limited "${CMD_TIMEOUT}" "$cli" ps -aq --no-trunc 2>/dev/null)" || ids=""
    if [[ -n "$ids" ]]; then
        ensure_dir "${dir}/inspect"
        for id in $ids; do
            run_limited "${CMD_TIMEOUT}" "$cli" inspect "$id" 2>/dev/null \
                | redact_env > "${dir}/inspect/${id}.json" || true
            # イメージからの変更点（追加・改変されたファイル）
            run_limited "${CMD_TIMEOUT}" "$cli" diff "$id" > "${dir}/inspect/${id}.diff.txt" 2>/dev/null || true
            if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
                run_limited "${CMD_TIMEOUT}" "$cli" top "$id" > "${dir}/inspect/${id}.top.txt" 2>/dev/null || true
                run_limited "${CMD_TIMEOUT}" "$cli" logs --tail 1000 --timestamps "$id" \
                    > "${dir}/inspect/${id}.logs_tail.txt" 2>&1 || true
            fi
        done

        # 調査で先に見る項目の要約
        "$cli" ps -aq 2>/dev/null | while read -r id; do
            run_limited "${CMD_TIMEOUT}" "$cli" inspect --format \
                '{{.Id}}	{{.Name}}	privileged={{.HostConfig.Privileged}}	pid={{.HostConfig.PidMode}}	net={{.HostConfig.NetworkMode}}	caps={{.HostConfig.CapAdd}}	binds={{.HostConfig.Binds}}' \
                "$id" 2>/dev/null
        done > "${dir}/risk_summary.tsv" || true
    fi

    # ネットワーク詳細
    local nets net
    nets="$(run_limited "${CMD_TIMEOUT}" "$cli" network ls -q 2>/dev/null)" || nets=""
    if [[ -n "$nets" ]]; then
        for net in $nets; do
            run_limited "${CMD_TIMEOUT}" "$cli" network inspect "$net" 2>/dev/null
        done > "${dir}/network_inspect.json" || true
    fi
}

collect_docker_like docker
collect_docker_like podman

# --- 設定ファイル ---
if [[ -d /etc/docker ]]; then
    FOUND=1
    safe_copy "/etc/docker/daemon.json" "${C_DIR}/config/docker/daemon.json"
    # 鍵ファイル (key.json, *.key) は持ち出さない
    find /etc/docker -type f "${LDIR_FIND_LS[@]}" > "${C_DIR}/config/docker_file_list.txt" 2>/dev/null || true
fi
if [[ -d /etc/containers ]]; then
    FOUND=1
    safe_copy "/etc/containers/" "${C_DIR}/config/containers/"
    # レジストリ認証情報は除外
    rm -f "${C_DIR}/config/containers/auth.json" 2>/dev/null || true
fi
if [[ -d /etc/containerd ]]; then
    FOUND=1
    safe_copy "/etc/containerd/config.toml" "${C_DIR}/config/containerd/config.toml"
fi
if [[ -d /etc/crio ]]; then
    FOUND=1
    safe_copy "/etc/crio/" "${C_DIR}/config/crio/"
fi

# ユーザごとのレジストリ設定は、存在の有無だけ記録する（中身は認証情報）
{
    for user_home in /root /home/*; do
        for f in "${user_home}/.docker/config.json" "${user_home}/.kube/config"; do
            [[ -e "$f" ]] && ls -l "$f"
        done
    done
} > "${C_DIR}/config/user_credential_files_present.txt" 2>/dev/null || true

# docker グループ（所属ユーザは実質 root）
if [[ -r /etc/group ]]; then
    grep -E '^(docker|podman|lxd|incus):' /etc/group > "${C_DIR}/privileged_groups.txt" 2>/dev/null || true
fi

# ソケットの権限
{
    for s in /var/run/docker.sock /run/docker.sock /run/containerd/containerd.sock \
             /run/crio/crio.sock /run/podman/podman.sock; do
        [[ -e "$s" ]] && ls -l "$s"
    done
} > "${C_DIR}/runtime_sockets.txt" 2>/dev/null || true

# --- CRI (containerd / CRI-O) ---
if have_cmd crictl; then
    FOUND=1
    log_info "[30_containers] crictl found"
    if out "${C_DIR}/cri/pods.txt" crictl pods; then
        out "${C_DIR}/cri/ps_all.txt" crictl ps -a || true
        out "${C_DIR}/cri/images.txt" crictl images || true
    fi
fi
if have_cmd ctr; then
    FOUND=1
    out "${C_DIR}/cri/ctr_namespaces.txt" ctr namespaces list || true
fi

# --- Kubernetes ノード ---
if [[ -d /etc/kubernetes || -d /var/lib/kubelet ]]; then
    FOUND=1
    log_info "[30_containers] Kubernetes node files found"
    K8S_DIR="${C_DIR}/kubernetes"
    ensure_dir "${K8S_DIR}"

    # static Pod マニフェスト（kubelet が API を経由せず起動する。永続化に使われる）
    safe_copy "/etc/kubernetes/manifests/" "${K8S_DIR}/static_pod_manifests/"
    safe_copy "/var/lib/kubelet/config.yaml" "${K8S_DIR}/kubelet_config.yaml"
    safe_copy "/var/lib/kubelet/kubeadm-flags.env" "${K8S_DIR}/kubeadm-flags.env"

    # /etc/kubernetes は一覧のみ。*.conf は kubeconfig（認証情報）、pki/ は鍵を含む。
    find /etc/kubernetes "${LDIR_FIND_LS[@]}" > "${K8S_DIR}/etc_kubernetes_file_list.txt" 2>/dev/null || true
    # 証明書（公開情報）のみ回収
    if [[ -d /etc/kubernetes/pki ]]; then
        ensure_dir "${K8S_DIR}/pki_certs"
        find /etc/kubernetes/pki -type f -name '*.crt' -exec cp -a {} "${K8S_DIR}/pki_certs/" \; 2>/dev/null || true
    fi

    # kubelet が現在保持している Pod の一覧（ディレクトリ名 = Pod UID）
    if [[ -d /var/lib/kubelet/pods ]]; then
        ls -la /var/lib/kubelet/pods > "${K8S_DIR}/kubelet_pods.txt" 2>/dev/null || true
    fi

    if have_cmd journalctl; then
        run_limited "${CMD_TIMEOUT}" journalctl -u kubelet --no-pager -n 2000 > "${K8S_DIR}/kubelet_journal_tail.txt" 2>&1 || true
    fi
fi

# --- LXC / LXD ---
if have_cmd lxc-ls; then
    FOUND=1
    out "${C_DIR}/lxc/lxc-ls.txt" lxc-ls --fancy || true
fi

# プロセスから見たコンテナの痕跡（ランタイム CLI が無い・壊されている場合の手がかり）
ps -eo pid,ppid,user,args 2>/dev/null \
    | grep -E 'containerd-shim|runc|crun|conmon|dockerd|kubelet|cri-o|podman' \
    | grep -v grep > "${C_DIR}/container_related_processes.txt" || true
[[ -s "${C_DIR}/container_related_processes.txt" ]] && FOUND=1

if [[ ${FOUND} -eq 0 ]]; then
    log_info "[30_containers] No container runtime detected"
    echo "No container runtime detected on this host" > "${C_DIR}/no_container_runtime.txt"
fi

log_success "[30_containers] Container information collection completed"
exit 0
