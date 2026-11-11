#!/bin/bash
#######################################################################
# Module: Cloud Metadata Collection
# クラウド環境メタデータ収集（AWS/Azure/GCP/Oracle Cloud等）
#
# v0.2.1 hardening:
# - Common interface: $1 = COLLECTION_DIR
# - Source common.sh
# - AWS IMDSv2 token support (best-effort)
# - Optional disable via LDIR_ENABLE_CLOUD_METADATA=0 (default: 1)
#######################################################################

set -u

COLLECTION_DIR="${1:-}"
if [[ -z "${COLLECTION_DIR}" ]]; then
    echo "[ERROR] [cloud_metadata] Missing output directory argument" >&2
    exit 1
fi

# Feature flag (safety for environments where network access should be avoided)
LDIR_ENABLE_CLOUD_METADATA="${LDIR_ENABLE_CLOUD_METADATA:-1}"

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${COLLECTION_DIR}"
export OUTPUT_DIR
source "${SCRIPT_DIR}/lib/common.sh"

MODULE_NAME="cloud_metadata"
MOD_DIR="${COLLECTION_DIR}/${MODULE_NAME}"
ensure_dir "${MOD_DIR}" || { log_error "[${MODULE_NAME}] Failed to create ${MOD_DIR}"; exit 1; }

if [[ "${LDIR_ENABLE_CLOUD_METADATA}" != "1" ]]; then
    log_info "[${MODULE_NAME}] Disabled by LDIR_ENABLE_CLOUD_METADATA=${LDIR_ENABLE_CLOUD_METADATA}"
    echo "cloud_metadata disabled" > "${MOD_DIR}/disabled.txt"
    exit 0
fi

log_info "[${MODULE_NAME}] Starting cloud metadata collection..."

# タイムアウト設定（クラウドでない場合の待機を短縮）
TIMEOUT="${LDIR_CLOUD_METADATA_TIMEOUT:-2}"

curl_get() {
    local url="$1"
    shift || true
    # --noproxy: メタデータ API はリンクローカル。http_proxy 経由で問い合わせると
    # プロキシ側が応答してしまい、クラウド環境だと誤判定し得る。
    curl -sf --noproxy '*' --max-time "${TIMEOUT}" "$@" "$url"
}

# --- AWS IMDS helpers (IMDSv2 best-effort) ---
aws_get_token() {
    # token TTL 60s (short-lived)
    curl -sf --noproxy '*' --max-time "${TIMEOUT}" -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true
}

aws_curl_get() {
    local path="$1"  # e.g. instance-id
    local token="${2:-}"

    local base="http://169.254.169.254/latest/meta-data/"
    if [[ -n "$token" ]]; then
        curl_get "${base}${path}" -H "X-aws-ec2-metadata-token: ${token}" 2>/dev/null
    else
        curl_get "${base}${path}" 2>/dev/null
    fi
}

aws_curl_user_data() {
    local token="${1:-}"
    local url="http://169.254.169.254/latest/user-data"
    if [[ -n "$token" ]]; then
        curl_get "$url" -H "X-aws-ec2-metadata-token: ${token}" 2>/dev/null
    else
        curl_get "$url" 2>/dev/null
    fi
}

# 1. AWS EC2 メタデータ
check_aws() {
    log_info "[${MODULE_NAME}] Checking for AWS EC2..."

    local token
    token="$(aws_get_token)"

    # Detection: IMDSv2 (token) first, then fall back to IMDSv1
    if [[ -z "$token" ]] || ! aws_curl_get "" "$token" &>/dev/null; then
        token=""
        aws_curl_get "" &>/dev/null || return 1
    fi

    ensure_dir "${MOD_DIR}/aws"
    log_info "[${MODULE_NAME}] AWS EC2 detected"

    aws_curl_get "instance-id" "$token" > "${MOD_DIR}/aws/instance-id.txt" 2>/dev/null || true
    aws_curl_get "instance-type" "$token" > "${MOD_DIR}/aws/instance-type.txt" 2>/dev/null || true
    aws_curl_get "ami-id" "$token" > "${MOD_DIR}/aws/ami-id.txt" 2>/dev/null || true
    aws_curl_get "hostname" "$token" > "${MOD_DIR}/aws/hostname.txt" 2>/dev/null || true
    aws_curl_get "local-ipv4" "$token" > "${MOD_DIR}/aws/local-ipv4.txt" 2>/dev/null || true
    aws_curl_get "public-ipv4" "$token" > "${MOD_DIR}/aws/public-ipv4.txt" 2>/dev/null || true
    aws_curl_get "placement/availability-zone" "$token" > "${MOD_DIR}/aws/availability-zone.txt" 2>/dev/null || true

    # region endpoint differs by generation; keep best-effort
    aws_curl_get "placement/region" "$token" > "${MOD_DIR}/aws/region.txt" 2>/dev/null || true

    aws_curl_get "security-groups" "$token" > "${MOD_DIR}/aws/security-groups.txt" 2>/dev/null || true
    aws_curl_get "iam/security-credentials/" "$token" > "${MOD_DIR}/aws/iam-role.txt" 2>/dev/null || true

    aws_curl_user_data "$token" > "${MOD_DIR}/aws/user-data.txt" 2>/dev/null || true
    aws_curl_get "network/interfaces/macs/" "$token" > "${MOD_DIR}/aws/network-macs.txt" 2>/dev/null || true

    log_success "[${MODULE_NAME}] AWS metadata collected"
    return 0
}

# 2. Azure メタデータ
check_azure() {
    log_info "[${MODULE_NAME}] Checking for Azure..."

    local url="http://169.254.169.254/metadata/instance?api-version=2021-02-01"
    if curl_get "$url" -H "Metadata:true" &>/dev/null; then
        ensure_dir "${MOD_DIR}/azure"
        log_info "[${MODULE_NAME}] Azure detected"

        curl_get "$url" -H "Metadata:true" > "${MOD_DIR}/azure/instance-metadata.json" 2>/dev/null || true
        curl_get "http://169.254.169.254/metadata/attested/document?api-version=2021-02-01" -H "Metadata:true" > "${MOD_DIR}/azure/attested-data.json" 2>/dev/null || true
        curl_get "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" -H "Metadata:true" > "${MOD_DIR}/azure/scheduled-events.json" 2>/dev/null || true

        log_success "[${MODULE_NAME}] Azure metadata collected"
        return 0
    fi
    return 1
}

# 3. Google Cloud Platform メタデータ
check_gcp() {
    log_info "[${MODULE_NAME}] Checking for GCP..."

    local base="http://metadata.google.internal/computeMetadata/v1/"
    if curl_get "$base" -H "Metadata-Flavor: Google" &>/dev/null; then
        ensure_dir "${MOD_DIR}/gcp"
        log_info "[${MODULE_NAME}] GCP detected"

        curl_get "${base}instance/?recursive=true" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/instance-metadata.json" 2>/dev/null || true
        curl_get "${base}instance/id" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/instance-id.txt" 2>/dev/null || true
        curl_get "${base}instance/name" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/instance-name.txt" 2>/dev/null || true
        curl_get "${base}instance/zone" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/zone.txt" 2>/dev/null || true
        curl_get "${base}instance/machine-type" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/machine-type.txt" 2>/dev/null || true
        curl_get "${base}instance/network-interfaces/" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/network-interfaces.txt" 2>/dev/null || true
        curl_get "${base}instance/service-accounts/" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/service-accounts.txt" 2>/dev/null || true
        curl_get "${base}project/?recursive=true" -H "Metadata-Flavor: Google" > "${MOD_DIR}/gcp/project-metadata.json" 2>/dev/null || true

        log_success "[${MODULE_NAME}] GCP metadata collected"
        return 0
    fi
    return 1
}

# 4. Oracle Cloud Infrastructure メタデータ
check_oci() {
    log_info "[${MODULE_NAME}] Checking for Oracle Cloud..."

    local base="http://169.254.169.254/opc/v1/"
    if curl_get "${base}instance/" &>/dev/null; then
        ensure_dir "${MOD_DIR}/oci"
        log_info "[${MODULE_NAME}] Oracle Cloud detected"

        curl_get "${base}instance/" > "${MOD_DIR}/oci/instance-metadata.json" 2>/dev/null || true
        curl_get "${base}instance/id" > "${MOD_DIR}/oci/instance-id.txt" 2>/dev/null || true
        curl_get "${base}instance/region" > "${MOD_DIR}/oci/region.txt" 2>/dev/null || true
        curl_get "${base}instance/shape" > "${MOD_DIR}/oci/shape.txt" 2>/dev/null || true
        curl_get "${base}vnics/" > "${MOD_DIR}/oci/vnics.json" 2>/dev/null || true

        log_success "[${MODULE_NAME}] Oracle Cloud metadata collected"
        return 0
    fi
    return 1
}

# 5. DigitalOcean メタデータ
check_digitalocean() {
    log_info "[${MODULE_NAME}] Checking for DigitalOcean..."

    local base="http://169.254.169.254/metadata/v1/"
    if curl_get "$base" &>/dev/null; then
        ensure_dir "${MOD_DIR}/digitalocean"
        log_info "[${MODULE_NAME}] DigitalOcean detected"

        curl_get "${base}id" > "${MOD_DIR}/digitalocean/droplet-id.txt" 2>/dev/null || true
        curl_get "${base}hostname" > "${MOD_DIR}/digitalocean/hostname.txt" 2>/dev/null || true
        curl_get "${base}region" > "${MOD_DIR}/digitalocean/region.txt" 2>/dev/null || true
        curl_get "${base}interfaces/" > "${MOD_DIR}/digitalocean/interfaces.json" 2>/dev/null || true
        curl_get "${base}tags" > "${MOD_DIR}/digitalocean/tags.txt" 2>/dev/null || true

        log_success "[${MODULE_NAME}] DigitalOcean metadata collected"
        return 0
    fi
    return 1
}

# 6. Alibaba Cloud メタデータ
check_alibaba() {
    log_info "[${MODULE_NAME}] Checking for Alibaba Cloud..."

    local base="http://100.100.100.200/latest/meta-data/"
    if curl_get "$base" &>/dev/null; then
        ensure_dir "${MOD_DIR}/alibaba"
        log_info "[${MODULE_NAME}] Alibaba Cloud detected"

        curl_get "${base}instance-id" > "${MOD_DIR}/alibaba/instance-id.txt" 2>/dev/null || true
        curl_get "${base}instance-type" > "${MOD_DIR}/alibaba/instance-type.txt" 2>/dev/null || true
        curl_get "${base}region-id" > "${MOD_DIR}/alibaba/region-id.txt" 2>/dev/null || true
        curl_get "${base}zone-id" > "${MOD_DIR}/alibaba/zone-id.txt" 2>/dev/null || true
        curl_get "${base}private-ipv4" > "${MOD_DIR}/alibaba/private-ipv4.txt" 2>/dev/null || true
        curl_get "${base}eipv4" > "${MOD_DIR}/alibaba/public-ipv4.txt" 2>/dev/null || true

        log_success "[${MODULE_NAME}] Alibaba metadata collected"
        return 0
    fi
    return 1
}

# すべてのクラウドプロバイダーをチェック
CLOUD_DETECTED=0

if ! have_cmd curl; then
    log_warn "[${MODULE_NAME}] curl not found; skipping cloud metadata"
    echo "curl not available" > "${MOD_DIR}/skipped.txt"
    exit 0
fi

check_aws && CLOUD_DETECTED=1
check_azure && CLOUD_DETECTED=1
check_gcp && CLOUD_DETECTED=1
check_oci && CLOUD_DETECTED=1
check_digitalocean && CLOUD_DETECTED=1
check_alibaba && CLOUD_DETECTED=1

if [[ ${CLOUD_DETECTED} -eq 0 ]]; then
    log_info "[${MODULE_NAME}] No cloud environment detected (on-premises or unsupported cloud)"
    echo "No cloud environment detected" > "${MOD_DIR}/no_cloud.txt"
fi

log_success "[${MODULE_NAME}] Cloud metadata collection complete"
exit 0
