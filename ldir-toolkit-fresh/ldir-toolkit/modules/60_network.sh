#!/bin/bash
#
# Module: Network Information
# ネットワーク情報収集モジュール
#

OUTPUT_DIR="$1"
NET_DIR="${OUTPUT_DIR}/network"

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

log_info "[60_network] Starting network information collection"

# ネットワーク接続状態
log_info "Collecting network connection states"
if command -v ss &> /dev/null; then
    ss -tupln > "${NET_DIR}/ss_listening.txt" 2>&1
    ss -tup > "${NET_DIR}/ss_established.txt" 2>&1
    ss -s > "${NET_DIR}/ss_summary.txt" 2>&1
    ss -anp > "${NET_DIR}/ss_all.txt" 2>&1
fi

if command -v netstat &> /dev/null; then
    netstat -tulpn > "${NET_DIR}/netstat_listening.txt" 2>&1
    netstat -anp > "${NET_DIR}/netstat_all.txt" 2>&1
    netstat -rn > "${NET_DIR}/netstat_routing.txt" 2>&1
    netstat -s > "${NET_DIR}/netstat_statistics.txt" 2>&1
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
arp -a > "${NET_DIR}/arp_cache.txt" 2>&1 || ip neigh show > "${NET_DIR}/arp_cache.txt" 2>&1

# ルーティングテーブル
ip route show > "${NET_DIR}/ip_routes.txt" 2>&1 || route -n > "${NET_DIR}/routes.txt" 2>&1
ip route show table all > "${NET_DIR}/ip_routes_all_tables.txt" 2>&1 || true

# ネットワークインターフェース詳細
ip addr show > "${NET_DIR}/ip_addresses.txt" 2>&1 || ifconfig -a > "${NET_DIR}/ip_addresses.txt" 2>&1
ip link show > "${NET_DIR}/ip_links.txt" 2>&1

# インターフェース統計
ip -s link > "${NET_DIR}/interface_statistics.txt" 2>&1

# DNS設定
safe_copy "/etc/resolv.conf" "${NET_DIR}/"
safe_copy "/etc/hosts" "${NET_DIR}/"
safe_copy "/etc/hostname" "${NET_DIR}/"
safe_copy "/etc/nsswitch.conf" "${NET_DIR}/"

# ファイアウォール設定
log_info "Collecting firewall configuration"
if command -v iptables &> /dev/null; then
    iptables -L -v -n > "${NET_DIR}/iptables_filter.txt" 2>&1 || true
    iptables -t nat -L -v -n > "${NET_DIR}/iptables_nat.txt" 2>&1 || true
    iptables -t mangle -L -v -n > "${NET_DIR}/iptables_mangle.txt" 2>&1 || true
    iptables -t raw -L -v -n > "${NET_DIR}/iptables_raw.txt" 2>&1 || true
    iptables-save > "${NET_DIR}/iptables_save.txt" 2>&1 || true
fi

if command -v ip6tables &> /dev/null; then
    ip6tables -L -v -n > "${NET_DIR}/ip6tables.txt" 2>&1 || true
fi

if command -v ufw &> /dev/null; then
    ufw status verbose > "${NET_DIR}/ufw_status.txt" 2>&1 || true
fi

if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --list-all > "${NET_DIR}/firewalld_config.txt" 2>&1 || true
fi

# nftables (新しいファイアウォール)
if command -v nft &> /dev/null; then
    nft list ruleset > "${NET_DIR}/nftables_ruleset.txt" 2>&1 || true
fi

# 確立された接続（プロセス情報付き）
if command -v lsof &> /dev/null; then
    lsof -i > "${NET_DIR}/lsof_network_connections.txt" 2>&1 || true
fi

# ネットワークサービス
log_info "Collecting network services configuration"
safe_copy "/etc/services" "${NET_DIR}/"
safe_copy "/etc/networks" "${NET_DIR}/"

# NetworkManager設定（デスクトップ環境）
safe_copy "/etc/NetworkManager/" "${NET_DIR}/NetworkManager/"

# systemd-networkd設定
safe_copy "/etc/systemd/network/" "${NET_DIR}/systemd-network/"

log_success "[60_network] Network information collection completed"
exit 0
