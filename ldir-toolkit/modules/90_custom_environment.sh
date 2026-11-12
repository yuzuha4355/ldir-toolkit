#!/bin/bash
#######################################################################
# Module: Custom Environment Detection
# カスタマイズ環境・特殊環境の情報収集
#
# v0.2.1 hardening:
# - Common interface: $1 = COLLECTION_DIR
# - Source common.sh for logging & helpers
# - Avoid non-expanded ~ patterns
#######################################################################

set -u

COLLECTION_DIR="${1:-}"
if [[ -z "${COLLECTION_DIR}" ]]; then
    echo "[ERROR] [custom_environment] Missing output directory argument" >&2
    exit 1
fi

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# common.sh expects OUTPUT_DIR to log to OUTPUT_DIR/metadata/collection.log
OUTPUT_DIR="${COLLECTION_DIR}"
export OUTPUT_DIR
source "${SCRIPT_DIR}/lib/common.sh"

MODULE_NAME="custom_environment"
MOD_DIR="${COLLECTION_DIR}/${MODULE_NAME}"
ensure_dir "${MOD_DIR}" || { log_error "[${MODULE_NAME}] Failed to create ${MOD_DIR}"; exit 1; }

log_info "[${MODULE_NAME}] Starting custom environment detection..."

# 1. Init System詳細情報
ensure_dir "${MOD_DIR}/init_system"

case "${INIT_SYSTEM:-unknown}" in
    systemd)
        log_info "[${MODULE_NAME}] Collecting systemd information..."
        save_command_output "systemctl --version" "${MOD_DIR}/init_system/systemd_version.txt"
        save_command_output "systemctl list-units --type=service --state=running" "${MOD_DIR}/init_system/running_services.txt"
        save_command_output "systemctl list-timers --all" "${MOD_DIR}/init_system/timers.txt"
        ;;
    openrc)
        log_info "[${MODULE_NAME}] Collecting OpenRC information..."
        save_command_output "rc-status -a" "${MOD_DIR}/init_system/openrc_status.txt"
        save_command_output "rc-update show" "${MOD_DIR}/init_system/openrc_services.txt"
        safe_copy "/etc/rc.conf" "${MOD_DIR}/init_system/rc.conf"
        ;;
    runit)
        log_info "[${MODULE_NAME}] Collecting runit information..."
        save_command_output "sv status /var/service/*" "${MOD_DIR}/init_system/runit_services.txt"
        safe_copy "/etc/runit/runsvdir/current" "${MOD_DIR}/init_system/"
        ;;
    s6)
        log_info "[${MODULE_NAME}] Collecting s6 information..."
        save_command_output "s6-rc -l list" "${MOD_DIR}/init_system/s6_services.txt" || true
        safe_copy "/etc/s6" "${MOD_DIR}/init_system/s6_config"
        ;;
    sysvinit)
        log_info "[${MODULE_NAME}] Collecting SysVinit information..."
        save_command_output "chkconfig --list" "${MOD_DIR}/init_system/chkconfig.txt" || \
        save_command_output "service --status-all" "${MOD_DIR}/init_system/service_status.txt"
        safe_copy "/etc/inittab" "${MOD_DIR}/init_system/inittab"
        ;;
    *)
        log_warn "[${MODULE_NAME}] Unknown init system: ${INIT_SYSTEM:-unknown}"
        ;;
esac

# 2. パッケージマネージャー情報
ensure_dir "${MOD_DIR}/packages"

case "${PKG_MANAGER:-unknown}" in
    apt)
        log_info "[${MODULE_NAME}] Collecting APT package information..."
        save_command_output "dpkg -l" "${MOD_DIR}/packages/dpkg_list.txt"
        save_command_output "apt list --installed" "${MOD_DIR}/packages/apt_installed.txt"
        safe_copy "/var/log/dpkg.log" "${MOD_DIR}/packages/dpkg.log"
        safe_copy "/var/log/apt/history.log" "${MOD_DIR}/packages/apt_history.log"
        ;;
    dnf|yum)
        log_info "[${MODULE_NAME}] Collecting YUM/DNF package information..."
        save_command_output "${PKG_MANAGER} list installed" "${MOD_DIR}/packages/installed_packages.txt"
        save_command_output "${PKG_MANAGER} history" "${MOD_DIR}/packages/package_history.txt"
        safe_copy "/var/log/dnf.log" "${MOD_DIR}/packages/dnf.log"
        safe_copy "/var/log/yum.log" "${MOD_DIR}/packages/yum.log"
        ;;
    pacman)
        log_info "[${MODULE_NAME}] Collecting Pacman package information..."
        save_command_output "pacman -Q" "${MOD_DIR}/packages/pacman_installed.txt"
        safe_copy "/var/log/pacman.log" "${MOD_DIR}/packages/pacman.log"
        ;;
    zypper)
        log_info "[${MODULE_NAME}] Collecting Zypper package information..."
        save_command_output "zypper packages --installed-only" "${MOD_DIR}/packages/zypper_installed.txt"
        safe_copy "/var/log/zypp/history" "${MOD_DIR}/packages/zypper_history.txt"
        ;;
    apk)
        log_info "[${MODULE_NAME}] Collecting APK package information..."
        save_command_output "apk info -v" "${MOD_DIR}/packages/apk_installed.txt"
        safe_copy "/var/log/apk.log" "${MOD_DIR}/packages/apk.log"
        ;;
    emerge)
        log_info "[${MODULE_NAME}] Collecting Portage package information..."
        save_command_output "qlist -I" "${MOD_DIR}/packages/portage_installed.txt" || \
        save_command_output "emerge --list-sets" "${MOD_DIR}/packages/portage_sets.txt"
        safe_copy "/var/log/emerge.log" "${MOD_DIR}/packages/emerge.log"
        ;;
    *)
        log_warn "[${MODULE_NAME}] Unknown package manager: ${PKG_MANAGER:-unknown}"
        ;;
esac

# 3. セキュリティモジュール詳細
ensure_dir "${MOD_DIR}/security"

if [[ "${SELINUX_STATUS:-Not installed}" != "Not installed" ]]; then
    log_info "[${MODULE_NAME}] Collecting SELinux information..."
    save_command_output "sestatus" "${MOD_DIR}/security/selinux_status.txt" || true
    save_command_output "getsebool -a" "${MOD_DIR}/security/selinux_booleans.txt" || true
    safe_copy "/etc/selinux/config" "${MOD_DIR}/security/selinux_config"
fi

if [[ "${APPARMOR_STATUS:-Not installed}" != "Not installed" ]]; then
    log_info "[${MODULE_NAME}] Collecting AppArmor information..."
    save_command_output "aa-status" "${MOD_DIR}/security/apparmor_status.txt" || true
    safe_copy "/etc/apparmor.d/" "${MOD_DIR}/security/apparmor_profiles"
fi

# 4. コンテナ環境情報
if [[ "${CONTAINER_TYPE:-none}" != "none" ]]; then
    ensure_dir "${MOD_DIR}/container"
    log_info "[${MODULE_NAME}] Container detected: ${CONTAINER_TYPE}"

    safe_copy "/proc/1/cgroup" "${MOD_DIR}/container/cgroup.txt"
    safe_copy "/proc/1/mountinfo" "${MOD_DIR}/container/mountinfo.txt"

    if [[ "${CONTAINER_TYPE}" = "docker" ]]; then
        safe_copy "/.dockerenv" "${MOD_DIR}/container/dockerenv" || true
        { tr '\0' '\n' < /proc/1/environ | redact_env > "${MOD_DIR}/container/docker_env.txt"; } 2>/dev/null || true
    fi
fi

# 5. ARM/組込み環境特有情報
if [[ "${ARCH_TYPE:-}" = "arm32" || "${ARCH_TYPE:-}" = "arm64" ]]; then
    ensure_dir "${MOD_DIR}/arm_specific"
    log_info "[${MODULE_NAME}] ARM architecture detected"

    if [[ -f /proc/device-tree/model ]]; then
        safe_copy "/proc/device-tree/model" "${MOD_DIR}/arm_specific/device_model.txt"
    fi

    if [[ -d /sys/class/gpio ]]; then
        save_command_output "ls -la /sys/class/gpio" "${MOD_DIR}/arm_specific/gpio_info.txt" || true
    fi

    if [[ -d /proc/device-tree ]]; then
        save_command_output "find /proc/device-tree -type f | head -50" "${MOD_DIR}/arm_specific/device_tree.txt" || true
    fi
fi

# 6. カスタムディレクトリ構造検出
ensure_dir "${MOD_DIR}/custom_paths"

if [[ -f /etc/default/useradd ]]; then
    safe_copy "/etc/default/useradd" "${MOD_DIR}/custom_paths/useradd_defaults"
fi

# カスタムマウントポイント（分かりやすい形で保存）
# NOTE: mount の出力形式は環境差が大きいので raw も残す
save_command_output "mount" "${MOD_DIR}/custom_paths/mount_raw.txt" || true

# 非標準サービスポート（ss が無い環境もある）
save_command_output "ss -tlnp" "${MOD_DIR}/custom_paths/listening_ports_ss.txt" || true

# 7. 環境変数（システム全体）
ensure_dir "${MOD_DIR}/environment"

# 収集プロセスの環境変数は system/environment_variables.txt に 1 か所だけ保存する
safe_copy "/etc/environment" "${MOD_DIR}/environment/etc_environment"
safe_copy "/etc/profile" "${MOD_DIR}/environment/profile"
safe_copy "/etc/profile.d/" "${MOD_DIR}/environment/profile.d"

# 8. カスタム設定ファイル検出
ensure_dir "${MOD_DIR}/custom_configs"

# よくあるカスタム設定（ワイルドカードは unquoted で回す）
CUSTOM_CONFIGS=(
    "/opt/*/conf"
    "/usr/local/etc"
    "/etc/opt"
)

for pattern in "${CUSTOM_CONFIGS[@]}"; do
    for path in ${pattern}; do
        if [[ -e "$path" ]]; then
            # /opt/a/conf と /opt/b/conf が衝突しないよう、パス全体から名前を作る
            # 例: /opt/a/conf -> opt_a_conf
            flat="${path#/}"
            if [[ -d "$path" ]]; then
                safe_copy "${path%/}/" "${MOD_DIR}/custom_configs/${flat//\//_}/"
            else
                safe_copy "$path" "${MOD_DIR}/custom_configs/${flat//\//_}"
            fi
        fi
    done
done

# ユーザの ~/.config
# ブラウザや Electron アプリのプロファイルを含み GB 単位になり得るうえ、
# Cookie 等も入る（LDIR_ENABLE_WEB=0 の意図と矛盾する）。
# - fast: 一覧だけ記録
# - full: 丸ごと回収
for user_home in /root /home/*; do
    if [[ -d "$user_home/.config" ]]; then
        username="$(basename "$user_home")"
        find "$user_home/.config" -maxdepth 3 "${LDIR_FIND_LS[@]}" > "${MOD_DIR}/custom_configs/user_config_${username}_listing.txt" 2>/dev/null || true
        if [[ "${LDIR_MODE:-fast}" = "full" ]]; then
            safe_copy "$user_home/.config" "${MOD_DIR}/custom_configs/user_config_${username}"
        fi
    fi
done

# 9. ディストリビューション固有ファイル
ensure_dir "${MOD_DIR}/distro_specific"

case "${DISTRO_ID:-unknown}" in
    arch)
        safe_copy "/etc/pacman.conf" "${MOD_DIR}/distro_specific/"
        safe_copy "/etc/makepkg.conf" "${MOD_DIR}/distro_specific/"
        ;;
    gentoo)
        safe_copy "/etc/portage" "${MOD_DIR}/distro_specific/portage"
        safe_copy "/var/lib/portage/world" "${MOD_DIR}/distro_specific/world"
        ;;
    alpine)
        safe_copy "/etc/apk/world" "${MOD_DIR}/distro_specific/apk_world"
        safe_copy "/etc/apk/repositories" "${MOD_DIR}/distro_specific/apk_repositories"
        ;;
    raspbian)
        safe_copy "/boot/config.txt" "${MOD_DIR}/distro_specific/boot_config.txt"
        safe_copy "/boot/cmdline.txt" "${MOD_DIR}/distro_specific/boot_cmdline.txt"
        ;;
esac

log_success "[${MODULE_NAME}] Custom environment detection complete"
exit 0
