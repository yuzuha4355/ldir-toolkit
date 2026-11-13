#!/bin/bash
#######################################################################
# Advanced Distribution Detection Library
# 高度なディストリビューション検出（特殊環境対応）
#######################################################################

# パッケージマネージャー検出
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
    elif command -v emerge &> /dev/null; then
        PKG_MANAGER="emerge"
    else
        PKG_MANAGER="unknown"
    fi
    export PKG_MANAGER
}

# Init system検出
detect_init_system() {
    if [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc ]; then
        INIT_SYSTEM="openrc"
    elif command -v sv &> /dev/null; then
        INIT_SYSTEM="runit"
    elif [ -d /etc/s6 ]; then
        INIT_SYSTEM="s6"
    elif [ -f /sbin/init ] && grep -aq "upstart" /sbin/init 2>/dev/null; then
        INIT_SYSTEM="upstart"
    elif [ -f /etc/inittab ]; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    export INIT_SYSTEM
}

# os-release 形式のファイルから 1 項目だけ読む。
# サブシェル内で source するので、呼び出し元の変数（VERSION, NAME, ID 等）を
# 上書きしない。項目が無ければ空文字を返す（set -u でも安全）。
_ldir_release_get() {
    local file="$1" key="$2"
    [ -r "$file" ] || return 0
    (
        set +u
        # shellcheck disable=SC1090
        . "$file" >/dev/null 2>&1
        eval "printf '%s' \"\${${key}:-}\""
    )
}

# ディストリビューション詳細検出
# LDIR_OS_RELEASE でファイルを差し替え可能（テスト用）
detect_distribution_advanced() {
    local os_release="${LDIR_OS_RELEASE:-/etc/os-release}"

    DISTRO_NAME=""
    DISTRO_VERSION=""
    DISTRO_ID=""

    if [ -f "$os_release" ]; then
        DISTRO_NAME="$(_ldir_release_get "$os_release" NAME)"
        # Arch / Debian testing などは VERSION_ID を持たない
        DISTRO_VERSION="$(_ldir_release_get "$os_release" VERSION_ID)"
        [ -n "$DISTRO_VERSION" ] || DISTRO_VERSION="$(_ldir_release_get "$os_release" BUILD_ID)"
        DISTRO_ID="$(_ldir_release_get "$os_release" ID)"
    elif [ -f /etc/lsb-release ]; then
        DISTRO_NAME="$(_ldir_release_get /etc/lsb-release DISTRIB_DESCRIPTION)"
        DISTRO_VERSION="$(_ldir_release_get /etc/lsb-release DISTRIB_RELEASE)"
        DISTRO_ID="$(_ldir_release_get /etc/lsb-release DISTRIB_ID)"
    fi

    : "${DISTRO_NAME:=Unknown}"
    : "${DISTRO_VERSION:=Unknown}"
    : "${DISTRO_ID:=unknown}"

    # 特殊ディストリビューションの追加検出
    if [ -f /etc/arch-release ]; then
        DISTRO_ID="arch"
    elif [ -f /etc/gentoo-release ]; then
        DISTRO_ID="gentoo"
    elif [ -f /etc/alpine-release ]; then
        DISTRO_ID="alpine"
    elif [ -f /etc/raspbian-release ] || [ -f /etc/rpi-issue ]; then
        DISTRO_ID="raspbian"
    fi

    export DISTRO_NAME DISTRO_VERSION DISTRO_ID
}

# アーキテクチャ検出
detect_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH_TYPE="x86_64"
            ;;
        aarch64|arm64)
            ARCH_TYPE="arm64"
            ;;
        armv7l|armhf)
            ARCH_TYPE="arm32"
            ;;
        i386|i686)
            ARCH_TYPE="x86"
            ;;
        *)
            ARCH_TYPE="$ARCH"
            ;;
    esac
    export ARCH ARCH_TYPE
}

# コンテナ環境検出
detect_container_environment() {
    if [ -f /.dockerenv ]; then
        CONTAINER_TYPE="docker"
    elif grep -q "lxc" /proc/1/cgroup 2>/dev/null; then
        CONTAINER_TYPE="lxc"
    elif [ -f /run/systemd/container ]; then
        CONTAINER_TYPE=$(cat /run/systemd/container)
    elif grep -q "systemd-nspawn" /proc/1/cgroup 2>/dev/null; then
        CONTAINER_TYPE="systemd-nspawn"
    else
        CONTAINER_TYPE="none"
    fi
    export CONTAINER_TYPE
}

# 仮想化の判定（このホスト自身が VM か）
# 使えるものを順に試す。どれも無い環境でも止まらない。
#   1. systemd-detect-virt --vm（あれば最も確か）
#   2. DMI（/sys/class/dmi/id の製品名・ベンダー）
#   3. /sys/hypervisor/type（Xen）
#   4. /proc/cpuinfo の hypervisor フラグ（x86 の VM。種別までは分からない）
# 結果: VIRT_TYPE（kvm, vmware, none, unknown 等）と VIRT_SOURCE（判定に使ったもの）
# LDIR_VIRT_ROOT を付けると /sys や /proc をその下から読む（テスト用）。このとき
# 実ホストを調べる systemd-detect-virt は使わない。
_ldir_virt_from_dmi() {
    local vendor="$1" product="$2"
    case "${vendor}|${product}" in
        *"Amazon EC2"*|*"|"*".metal")
            case "${product}" in *.metal) echo "none" ;; *) echo "amazon" ;; esac ;;
        *QEMU*)                          echo "qemu" ;;
        *KVM*)                           echo "kvm" ;;
        *VMware*)                        echo "vmware" ;;
        *VirtualBox*|*innotek*)          echo "oracle" ;;
        *Microsoft*"Virtual Machine"*)   echo "microsoft" ;;
        *Xen*|*"HVM domU"*)              echo "xen" ;;
        *Google*)                        echo "google" ;;
        *Parallels*)                     echo "parallels" ;;
        *Bochs*)                         echo "bochs" ;;
        *OpenStack*)                     echo "kvm" ;;
        *"Apple Virtualization"*)        echo "apple" ;;
        *) echo "" ;;
    esac
}

detect_virtualization() {
    local root="${LDIR_VIRT_ROOT:-}" out vendor product t
    VIRT_TYPE=""
    VIRT_SOURCE=""
    if [ -z "$root" ] && command -v systemd-detect-virt >/dev/null 2>&1; then
        out="$(systemd-detect-virt --vm 2>/dev/null)" || true
        if [ -n "$out" ]; then
            VIRT_TYPE="$out"
            VIRT_SOURCE="systemd-detect-virt"
        fi
    fi
    if [ -z "$VIRT_TYPE" ] && [ -r "${root}/sys/class/dmi/id/sys_vendor" ]; then
        vendor="$(cat "${root}/sys/class/dmi/id/sys_vendor" 2>/dev/null)"
        product="$(cat "${root}/sys/class/dmi/id/product_name" 2>/dev/null)"
        t="$(_ldir_virt_from_dmi "$vendor" "$product")"
        if [ -n "$t" ]; then
            VIRT_TYPE="$t"
            VIRT_SOURCE="dmi: ${vendor} / ${product}"
        fi
    fi
    if [ -z "$VIRT_TYPE" ] && [ -r "${root}/sys/hypervisor/type" ]; then
        t="$(cat "${root}/sys/hypervisor/type" 2>/dev/null)"
        if [ -n "$t" ]; then
            VIRT_TYPE="$t"
            VIRT_SOURCE="/sys/hypervisor/type"
        fi
    fi
    if [ -z "$VIRT_TYPE" ] && [ -r "${root}/proc/cpuinfo" ]; then
        if grep -qE '^flags[[:space:]]*:.*[[:space:]]hypervisor([[:space:]]|$)' "${root}/proc/cpuinfo" 2>/dev/null; then
            VIRT_TYPE="vm-unknown-hypervisor"
            VIRT_SOURCE="cpuinfo hypervisor flag"
        elif grep -qE '^flags[[:space:]]*:' "${root}/proc/cpuinfo" 2>/dev/null && [ -r "${root}/sys/class/dmi/id/sys_vendor" ]; then
            # x86 で hypervisor フラグが無く、DMI も既知の VM ではない
            VIRT_TYPE="none"
            VIRT_SOURCE="cpuinfo and dmi"
        fi
    fi
    if [ -z "$VIRT_TYPE" ]; then
        VIRT_TYPE="unknown"
        VIRT_SOURCE="no usable detection source"
    fi
    export VIRT_TYPE VIRT_SOURCE
}

# SELinux/AppArmor検出
detect_security_modules() {
    # SELinux
    if command -v getenforce &> /dev/null; then
        SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
    else
        SELINUX_STATUS="Not installed"
    fi

    # AppArmor
    if command -v aa-status &> /dev/null; then
        APPARMOR_STATUS=$(aa-status --enabled 2>/dev/null && echo "Enabled" || echo "Disabled")
    else
        APPARMOR_STATUS="Not installed"
    fi

    export SELINUX_STATUS APPARMOR_STATUS
}

# ログディレクトリ検出（非標準パス対応）
detect_log_paths() {
    # 標準パス
    if [ -d /var/log ]; then
        LOG_DIR="/var/log"
    elif [ -d /var/adm ]; then
        LOG_DIR="/var/adm"
    else
        LOG_DIR="unknown"
    fi

    # systemd journal
    if [ -d /var/log/journal ]; then
        JOURNAL_DIR="/var/log/journal"
    elif [ -d /run/log/journal ]; then
        JOURNAL_DIR="/run/log/journal"
    else
        JOURNAL_DIR="none"
    fi

    # syslog
    if [ -f /var/log/syslog ]; then
        SYSLOG_FILE="/var/log/syslog"
    elif [ -f /var/log/messages ]; then
        SYSLOG_FILE="/var/log/messages"
    else
        SYSLOG_FILE="none"
    fi

    # auth log
    if [ -f /var/log/auth.log ]; then
        AUTH_LOG="/var/log/auth.log"
    elif [ -f /var/log/secure ]; then
        AUTH_LOG="/var/log/secure"
    else
        AUTH_LOG="none"
    fi

    export LOG_DIR JOURNAL_DIR SYSLOG_FILE AUTH_LOG
}

# すべての検出を実行
detect_all() {
    detect_package_manager
    detect_init_system
    detect_distribution_advanced
    detect_architecture
    detect_container_environment
    detect_security_modules
    detect_log_paths
    
    # 環境情報サマリー出力
    log_info "=== Environment Detection ==="
    log_info "Distribution: ${DISTRO_NAME} ${DISTRO_VERSION} (${DISTRO_ID})"
    log_info "Architecture: ${ARCH_TYPE} (${ARCH})"
    log_info "Package Manager: ${PKG_MANAGER}"
    log_info "Init System: ${INIT_SYSTEM}"
    log_info "Container: ${CONTAINER_TYPE}"
    log_info "SELinux: ${SELINUX_STATUS}"
    log_info "AppArmor: ${APPARMOR_STATUS}"
    log_info "Log Directory: ${LOG_DIR}"
}

# メイン実行（単体で実行された場合。通常は ldir-collect.sh から source される）
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    # shellcheck source=common.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
    detect_all
fi
