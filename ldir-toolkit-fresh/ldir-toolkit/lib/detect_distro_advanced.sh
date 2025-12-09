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
    elif [ -f /sbin/init ] && strings /sbin/init | grep -q "upstart"; then
        INIT_SYSTEM="upstart"
    elif [ -f /etc/inittab ]; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    export INIT_SYSTEM
}

# ディストリビューション詳細検出
detect_distribution_advanced() {
    # 標準的な検出
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="$NAME"
        DISTRO_VERSION="$VERSION_ID"
        DISTRO_ID="$ID"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO_NAME="$DISTRIB_DESCRIPTION"
        DISTRO_VERSION="$DISTRIB_RELEASE"
        DISTRO_ID="$DISTRIB_ID"
    else
        DISTRO_NAME="Unknown"
        DISTRO_VERSION="Unknown"
        DISTRO_ID="unknown"
    fi

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

# メイン実行
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    detect_all
fi
