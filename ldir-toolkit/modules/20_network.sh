#!/bin/bash
#
# Module: Network Information
# ネットワーク情報収集モジュール
#

OUTPUT_DIR="${1:-}"
if [[ -z "${OUTPUT_DIR}" ]]; then
    echo "[ERROR] [20_network] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

NET_DIR="${OUTPUT_DIR}/network"
ensure_dir "${NET_DIR}" || { log_error "[20_network] Failed to create ${NET_DIR}"; exit 1; }

log_info "[20_network] Starting network information collection"

# ネットワーク接続状態
log_info "Collecting network connection states"
if command -v ss &> /dev/null; then
    capture "${NET_DIR}/ss_listening.txt" ss -tupln
    capture "${NET_DIR}/ss_established.txt" ss -tup
    capture "${NET_DIR}/ss_summary.txt" ss -s
    capture "${NET_DIR}/ss_all.txt" ss -anp
fi

if command -v netstat &> /dev/null; then
    capture "${NET_DIR}/netstat_listening.txt" netstat -tulpn
    capture "${NET_DIR}/netstat_all.txt" netstat -anp
    capture "${NET_DIR}/netstat_routing.txt" netstat -rn
    capture "${NET_DIR}/netstat_statistics.txt" netstat -s
fi

# /proc からのネットワーク情報
log_info "Collecting network information from /proc"
safe_copy "/proc/net/tcp" "${NET_DIR}/"
safe_copy "/proc/net/tcp6" "${NET_DIR}/"
safe_copy "/proc/net/udp" "${NET_DIR}/"
safe_copy "/proc/net/udp6" "${NET_DIR}/"
safe_copy "/proc/net/raw" "${NET_DIR}/"
safe_copy "/proc/net/route" "${NET_DIR}/"
safe_copy "/proc/net/arp" "${NET_DIR}/"

# ARPキャッシュ
capture_try "${NET_DIR}/arp_cache.txt" arp -a || capture "${NET_DIR}/arp_cache.txt" ip neigh show

# ルーティングテーブル
capture_try "${NET_DIR}/ip_routes.txt" ip route show || capture "${NET_DIR}/routes.txt" route -n
capture "${NET_DIR}/ip_routes_all_tables.txt" ip route show table all

# ネットワークインターフェース詳細
capture_try "${NET_DIR}/ip_addresses.txt" ip addr show || capture "${NET_DIR}/ip_addresses.txt" ifconfig -a
capture "${NET_DIR}/ip_links.txt" ip link show

# インターフェース統計
capture "${NET_DIR}/interface_statistics.txt" ip -s link

# DNS設定
safe_copy "/etc/resolv.conf" "${NET_DIR}/"
safe_copy "/etc/hosts" "${NET_DIR}/"
safe_copy "/etc/hostname" "${NET_DIR}/"
safe_copy "/etc/nsswitch.conf" "${NET_DIR}/"
# TCP Wrappers（sshd 等への接続元制限。書き換えられることがある）
safe_copy "/etc/hosts.allow" "${NET_DIR}/"
safe_copy "/etc/hosts.deny" "${NET_DIR}/"

# ファイアウォール設定
# 失敗は WARN（ファイアウォールの状態が取れていない）。ただしコンテナ内では
# 権限が無いのが普通なので DEBUG に留める（capture_host）。
log_info "Collecting firewall configuration"
if have_cmd iptables; then
    capture_host "${NET_DIR}/iptables_filter.txt" iptables -L -v -n
    capture_host "${NET_DIR}/iptables_nat.txt" iptables -t nat -L -v -n
    capture_host "${NET_DIR}/iptables_mangle.txt" iptables -t mangle -L -v -n
    capture_host "${NET_DIR}/iptables_raw.txt" iptables -t raw -L -v -n
    capture_host "${NET_DIR}/iptables_save.txt" iptables-save
fi

if have_cmd ip6tables; then
    capture_host "${NET_DIR}/ip6tables.txt" ip6tables -L -v -n
fi

if have_cmd ufw; then
    capture_host "${NET_DIR}/ufw_status.txt" ufw status verbose
fi

# firewalld が停止中なら firewall-cmd は 252 で終わる。それは状態であって収集の失敗ではない
if have_cmd firewall-cmd; then
    capture_try "${NET_DIR}/firewalld_config.txt" firewall-cmd --list-all
    case $? in
        0|127) ;;
        252) log_debug "firewalld is not running" ;;
        *) log_warn "Command failed: firewall-cmd --list-all -> firewalld_config.txt" ;;
    esac
fi

# nftables (新しいファイアウォール)
if have_cmd nft; then
    capture_host "${NET_DIR}/nftables_ruleset.txt" nft list ruleset
fi

# 確立された接続（プロセス情報付き）。lsof は該当なしでも 1 で終わる
if have_cmd lsof; then
    capture_try "${NET_DIR}/lsof_network_connections.txt" lsof -i \
        || [[ -s "${NET_DIR}/lsof_network_connections.txt" ]] \
        || echo "lsof -i: no network files (exit 1 with no output)" > "${NET_DIR}/lsof_network_connections.txt"
fi

# ネットワークサービス
log_info "Collecting network services configuration"
safe_copy "/etc/services" "${NET_DIR}/"
safe_copy "/etc/networks" "${NET_DIR}/"

# NetworkManager設定（デスクトップ環境）
safe_copy "/etc/NetworkManager/" "${NET_DIR}/NetworkManager/"

# systemd-networkd設定
safe_copy "/etc/systemd/network/" "${NET_DIR}/systemd-network/"

log_success "[20_network] Network information collection completed"
exit 0
