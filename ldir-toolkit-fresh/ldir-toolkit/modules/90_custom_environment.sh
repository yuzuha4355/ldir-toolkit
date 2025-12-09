#!/bin/bash
#######################################################################
# Module: Custom Environment Detection
# カスタマイズ環境・特殊環境の情報収集
#######################################################################

MODULE_NAME="custom_environment"
OUTPUT_DIR="${COLLECTION_DIR}/${MODULE_NAME}"
mkdir -p "${OUTPUT_DIR}"

log_info "[${MODULE_NAME}] Starting custom environment detection..."

# 1. Init System詳細情報
mkdir -p "${OUTPUT_DIR}/init_system"

case "${INIT_SYSTEM}" in
    systemd)
        log_info "[${MODULE_NAME}] Collecting systemd information..."
        save_command_output "systemctl --version" "${OUTPUT_DIR}/init_system/systemd_version.txt"
        save_command_output "systemctl list-units --type=service --state=running" "${OUTPUT_DIR}/init_system/running_services.txt"
        save_command_output "systemctl list-timers --all" "${OUTPUT_DIR}/init_system/timers.txt"
        ;;
    openrc)
        log_info "[${MODULE_NAME}] Collecting OpenRC information..."
        save_command_output "rc-status -a" "${OUTPUT_DIR}/init_system/openrc_status.txt"
        save_command_output "rc-update show" "${OUTPUT_DIR}/init_system/openrc_services.txt"
        safe_copy "/etc/rc.conf" "${OUTPUT_DIR}/init_system/rc.conf"
        ;;
    runit)
        log_info "[${MODULE_NAME}] Collecting runit information..."
        save_command_output "sv status /var/service/*" "${OUTPUT_DIR}/init_system/runit_services.txt"
        safe_copy "/etc/runit/runsvdir/current" "${OUTPUT_DIR}/init_system/"
        ;;
    s6)
        log_info "[${MODULE_NAME}] Collecting s6 information..."
        save_command_output "s6-rc -l list" "${OUTPUT_DIR}/init_system/s6_services.txt" 2>/dev/null || true
        safe_copy "/etc/s6" "${OUTPUT_DIR}/init_system/s6_config"
        ;;
    sysvinit)
        log_info "[${MODULE_NAME}] Collecting SysVinit information..."
        save_command_output "chkconfig --list" "${OUTPUT_DIR}/init_system/chkconfig.txt" 2>/dev/null || \
        save_command_output "service --status-all" "${OUTPUT_DIR}/init_system/service_status.txt"
        safe_copy "/etc/inittab" "${OUTPUT_DIR}/init_system/inittab"
        ;;
    *)
        log_warn "[${MODULE_NAME}] Unknown init system: ${INIT_SYSTEM}"
        ;;
esac

# 2. パッケージマネージャー情報
mkdir -p "${OUTPUT_DIR}/packages"

case "${PKG_MANAGER}" in
    apt)
        log_info "[${MODULE_NAME}] Collecting APT package information..."
        save_command_output "dpkg -l" "${OUTPUT_DIR}/packages/dpkg_list.txt"
        save_command_output "apt list --installed" "${OUTPUT_DIR}/packages/apt_installed.txt"
        safe_copy "/var/log/dpkg.log" "${OUTPUT_DIR}/packages/dpkg.log"
        safe_copy "/var/log/apt/history.log" "${OUTPUT_DIR}/packages/apt_history.log"
        ;;
    dnf|yum)
        log_info "[${MODULE_NAME}] Collecting YUM/DNF package information..."
        save_command_output "${PKG_MANAGER} list installed" "${OUTPUT_DIR}/packages/installed_packages.txt"
        save_command_output "${PKG_MANAGER} history" "${OUTPUT_DIR}/packages/package_history.txt"
        safe_copy "/var/log/dnf.log" "${OUTPUT_DIR}/packages/dnf.log"
        safe_copy "/var/log/yum.log" "${OUTPUT_DIR}/packages/yum.log"
        ;;
    pacman)
        log_info "[${MODULE_NAME}] Collecting Pacman package information..."
        save_command_output "pacman -Q" "${OUTPUT_DIR}/packages/pacman_installed.txt"
        safe_copy "/var/log/pacman.log" "${OUTPUT_DIR}/packages/pacman.log"
        ;;
    zypper)
        log_info "[${MODULE_NAME}] Collecting Zypper package information..."
        save_command_output "zypper packages --installed-only" "${OUTPUT_DIR}/packages/zypper_installed.txt"
        safe_copy "/var/log/zypp/history" "${OUTPUT_DIR}/packages/zypper_history.txt"
        ;;
    apk)
        log_info "[${MODULE_NAME}] Collecting APK package information..."
        save_command_output "apk info -v" "${OUTPUT_DIR}/packages/apk_installed.txt"
        safe_copy "/var/log/apk.log" "${OUTPUT_DIR}/packages/apk.log"
        ;;
    emerge)
        log_info "[${MODULE_NAME}] Collecting Portage package information..."
        save_command_output "qlist -I" "${OUTPUT_DIR}/packages/portage_installed.txt" 2>/dev/null || \
        save_command_output "emerge --list-sets" "${OUTPUT_DIR}/packages/portage_sets.txt"
        safe_copy "/var/log/emerge.log" "${OUTPUT_DIR}/packages/emerge.log"
        ;;
    *)
        log_warn "[${MODULE_NAME}] Unknown package manager: ${PKG_MANAGER}"
        ;;
esac

# 3. セキュリティモジュール詳細
mkdir -p "${OUTPUT_DIR}/security"

if [ "${SELINUX_STATUS}" != "Not installed" ]; then
    log_info "[${MODULE_NAME}] Collecting SELinux information..."
    save_command_output "sestatus" "${OUTPUT_DIR}/security/selinux_status.txt"
    save_command_output "getsebool -a" "${OUTPUT_DIR}/security/selinux_booleans.txt"
    safe_copy "/etc/selinux/config" "${OUTPUT_DIR}/security/selinux_config"
fi

if [ "${APPARMOR_STATUS}" != "Not installed" ]; then
    log_info "[${MODULE_NAME}] Collecting AppArmor information..."
    save_command_output "aa-status" "${OUTPUT_DIR}/security/apparmor_status.txt"
    safe_copy "/etc/apparmor.d/" "${OUTPUT_DIR}/security/apparmor_profiles"
fi

# 4. コンテナ環境情報
if [ "${CONTAINER_TYPE}" != "none" ]; then
    mkdir -p "${OUTPUT_DIR}/container"
    log_info "[${MODULE_NAME}] Container detected: ${CONTAINER_TYPE}"
    
    # cgroup情報
    safe_copy "/proc/1/cgroup" "${OUTPUT_DIR}/container/cgroup.txt"
    safe_copy "/proc/1/mountinfo" "${OUTPUT_DIR}/container/mountinfo.txt"
    
    # Docker特有
    if [ "${CONTAINER_TYPE}" = "docker" ]; then
        safe_copy "/.dockerenv" "${OUTPUT_DIR}/container/dockerenv"
        save_command_output "cat /proc/1/environ | tr '\\0' '\\n'" "${OUTPUT_DIR}/container/docker_env.txt"
    fi
fi

# 5. ARM/組込み環境特有情報
if [ "${ARCH_TYPE}" = "arm32" ] || [ "${ARCH_TYPE}" = "arm64" ]; then
    mkdir -p "${OUTPUT_DIR}/arm_specific"
    log_info "[${MODULE_NAME}] ARM architecture detected"
    
    # Raspberry Pi検出
    if [ -f /proc/device-tree/model ]; then
        safe_copy "/proc/device-tree/model" "${OUTPUT_DIR}/arm_specific/device_model.txt"
    fi
    
    # GPIO情報
    if [ -d /sys/class/gpio ]; then
        save_command_output "ls -la /sys/class/gpio" "${OUTPUT_DIR}/arm_specific/gpio_info.txt"
    fi
    
    # Device Tree情報
    if [ -d /proc/device-tree ]; then
        save_command_output "find /proc/device-tree -type f | head -50" "${OUTPUT_DIR}/arm_specific/device_tree.txt"
    fi
fi

# 6. カスタムディレクトリ構造検出
mkdir -p "${OUTPUT_DIR}/custom_paths"

# 非標準ホームディレクトリ
if [ -f /etc/default/useradd ]; then
    safe_copy "/etc/default/useradd" "${OUTPUT_DIR}/custom_paths/useradd_defaults"
fi

# カスタムマウントポイント
save_command_output "mount | grep -v '(^proc\\|^sys\\|^dev\\|^tmpfs)'" "${OUTPUT_DIR}/custom_paths/custom_mounts.txt"

# 非標準サービスポート
save_command_output "ss -tlnp | grep -v ':22\\|:80\\|:443'" "${OUTPUT_DIR}/custom_paths/non_standard_ports.txt"

# 7. 環境変数（システム全体）
mkdir -p "${OUTPUT_DIR}/environment"

save_command_output "env" "${OUTPUT_DIR}/environment/current_env.txt"
safe_copy "/etc/environment" "${OUTPUT_DIR}/environment/etc_environment"
safe_copy "/etc/profile" "${OUTPUT_DIR}/environment/profile"
safe_copy "/etc/profile.d/" "${OUTPUT_DIR}/environment/profile.d"

# 8. カスタム設定ファイル検出
mkdir -p "${OUTPUT_DIR}/custom_configs"

# よくあるカスタム設定
CUSTOM_CONFIGS=(
    "/opt/*/conf"
    "/usr/local/etc"
    "/etc/opt"
    "~/.config"
)

for pattern in "${CUSTOM_CONFIGS[@]}"; do
    for path in ${pattern}; do
        if [ -e "$path" ]; then
            safe_copy "$path" "${OUTPUT_DIR}/custom_configs/$(basename $path)"
        fi
    done
done

# 9. ディストリビューション固有ファイル
mkdir -p "${OUTPUT_DIR}/distro_specific"

case "${DISTRO_ID}" in
    arch)
        safe_copy "/etc/pacman.conf" "${OUTPUT_DIR}/distro_specific/"
        safe_copy "/etc/makepkg.conf" "${OUTPUT_DIR}/distro_specific/"
        ;;
    gentoo)
        safe_copy "/etc/portage" "${OUTPUT_DIR}/distro_specific/portage"
        safe_copy "/var/lib/portage/world" "${OUTPUT_DIR}/distro_specific/world"
        ;;
    alpine)
        safe_copy "/etc/apk/world" "${OUTPUT_DIR}/distro_specific/apk_world"
        safe_copy "/etc/apk/repositories" "${OUTPUT_DIR}/distro_specific/apk_repositories"
        ;;
    raspbian)
        safe_copy "/boot/config.txt" "${OUTPUT_DIR}/distro_specific/boot_config.txt"
        safe_copy "/boot/cmdline.txt" "${OUTPUT_DIR}/distro_specific/boot_cmdline.txt"
        ;;
esac

log_success "[${MODULE_NAME}] Custom environment detection complete"
