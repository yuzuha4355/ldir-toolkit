#!/bin/bash
#
# LDIR-Toolkit - Distribution Detection
# ディストリビューション自動検出
#

detect_distribution() {
    # グローバル変数として設定
    DISTRO_NAME="unknown"
    DISTRO_VERSION="unknown"
    AUTH_LOG="/var/log/auth.log"
    SYSLOG="/var/log/syslog"
    
    # /etc/os-release が最も標準的
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO_NAME="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        DISTRO_PRETTY="${PRETTY_NAME:-unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO_NAME="rhel"
        DISTRO_VERSION="$(cat /etc/redhat-release | grep -oP '\d+\.\d+' | head -1)"
        DISTRO_PRETTY="$(cat /etc/redhat-release)"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO_NAME="debian"
        DISTRO_VERSION="$(cat /etc/debian_version)"
        DISTRO_PRETTY="Debian ${DISTRO_VERSION}"
    fi
    
    log_info "Detected Distribution: ${DISTRO_PRETTY}"
    
    # ディストリビューションごとのログファイルパス設定
    case "$DISTRO_NAME" in
        ubuntu|debian|linuxmint)
            AUTH_LOG="/var/log/auth.log"
            SYSLOG="/var/log/syslog"
            PACKAGE_MANAGER="apt"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            AUTH_LOG="/var/log/secure"
            SYSLOG="/var/log/messages"
            PACKAGE_MANAGER="yum"
            ;;
        arch|manjaro)
            AUTH_LOG="/var/log/auth.log"
            SYSLOG="/var/log/syslog"
            PACKAGE_MANAGER="pacman"
            ;;
        opensuse*|sles)
            AUTH_LOG="/var/log/messages"
            SYSLOG="/var/log/messages"
            PACKAGE_MANAGER="zypper"
            ;;
        *)
            log_warn "Unknown distribution, using default paths"
            AUTH_LOG="/var/log/auth.log"
            SYSLOG="/var/log/syslog"
            PACKAGE_MANAGER="unknown"
            ;;
    esac
    
    # 検出結果をエクスポート
    export DISTRO_NAME DISTRO_VERSION DISTRO_PRETTY
    export AUTH_LOG SYSLOG PACKAGE_MANAGER
    
    log_info "Auth Log: ${AUTH_LOG}"
    log_info "Syslog: ${SYSLOG}"
    log_info "Package Manager: ${PACKAGE_MANAGER}"
}

# init システムの検出
detect_init_system() {
    if [[ -d /run/systemd/system ]]; then
        INIT_SYSTEM="systemd"
    elif [[ -f /sbin/init ]] && [[ "$(readlink /sbin/init)" == *"upstart"* ]]; then
        INIT_SYSTEM="upstart"
    elif [[ -d /etc/init.d ]]; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    
    export INIT_SYSTEM
    log_info "Init System: ${INIT_SYSTEM}"
}
