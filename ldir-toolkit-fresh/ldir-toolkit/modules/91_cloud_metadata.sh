#!/bin/bash
#######################################################################
# Module: Cloud Metadata Collection
# クラウド環境メタデータ収集（AWS/Azure/GCP/Oracle Cloud等）
#######################################################################

MODULE_NAME="cloud_metadata"
OUTPUT_DIR="${COLLECTION_DIR}/${MODULE_NAME}"
mkdir -p "${OUTPUT_DIR}"

log_info "[${MODULE_NAME}] Starting cloud metadata collection..."

# タイムアウト設定（クラウドでない場合の待機を短縮）
TIMEOUT=2

# 1. AWS EC2 メタデータ
check_aws() {
    log_info "[${MODULE_NAME}] Checking for AWS EC2..."
    
    AWS_METADATA_URL="http://169.254.169.254/latest/meta-data/"
    
    if curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}" &>/dev/null; then
        mkdir -p "${OUTPUT_DIR}/aws"
        log_info "[${MODULE_NAME}] AWS EC2 detected"
        
        # 基本情報
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}instance-id" > "${OUTPUT_DIR}/aws/instance-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}instance-type" > "${OUTPUT_DIR}/aws/instance-type.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}ami-id" > "${OUTPUT_DIR}/aws/ami-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}hostname" > "${OUTPUT_DIR}/aws/hostname.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}local-ipv4" > "${OUTPUT_DIR}/aws/local-ipv4.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}public-ipv4" > "${OUTPUT_DIR}/aws/public-ipv4.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}placement/availability-zone" > "${OUTPUT_DIR}/aws/availability-zone.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}placement/region" > "${OUTPUT_DIR}/aws/region.txt" 2>/dev/null
        
        # セキュリティグループ
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}security-groups" > "${OUTPUT_DIR}/aws/security-groups.txt" 2>/dev/null
        
        # IAMロール
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}iam/security-credentials/" > "${OUTPUT_DIR}/aws/iam-role.txt" 2>/dev/null
        
        # ユーザーデータ
        curl -sf --max-time ${TIMEOUT} "http://169.254.169.254/latest/user-data" > "${OUTPUT_DIR}/aws/user-data.txt" 2>/dev/null
        
        # ネットワークインターフェース
        curl -sf --max-time ${TIMEOUT} "${AWS_METADATA_URL}network/interfaces/macs/" > "${OUTPUT_DIR}/aws/network-macs.txt" 2>/dev/null
        
        log_success "[${MODULE_NAME}] AWS metadata collected"
        return 0
    fi
    return 1
}

# 2. Azure メタデータ
check_azure() {
    log_info "[${MODULE_NAME}] Checking for Azure..."
    
    AZURE_METADATA_URL="http://169.254.169.254/metadata/instance?api-version=2021-02-01"
    
    if curl -sf --max-time ${TIMEOUT} -H "Metadata:true" "${AZURE_METADATA_URL}" &>/dev/null; then
        mkdir -p "${OUTPUT_DIR}/azure"
        log_info "[${MODULE_NAME}] Azure detected"
        
        # インスタンスメタデータ（JSON形式）
        curl -sf --max-time ${TIMEOUT} -H "Metadata:true" "${AZURE_METADATA_URL}" > "${OUTPUT_DIR}/azure/instance-metadata.json" 2>/dev/null
        
        # アテステーション情報
        curl -sf --max-time ${TIMEOUT} -H "Metadata:true" "http://169.254.169.254/metadata/attested/document?api-version=2021-02-01" > "${OUTPUT_DIR}/azure/attested-data.json" 2>/dev/null
        
        # スケジュールイベント
        curl -sf --max-time ${TIMEOUT} -H "Metadata:true" "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01" > "${OUTPUT_DIR}/azure/scheduled-events.json" 2>/dev/null
        
        log_success "[${MODULE_NAME}] Azure metadata collected"
        return 0
    fi
    return 1
}

# 3. Google Cloud Platform メタデータ
check_gcp() {
    log_info "[${MODULE_NAME}] Checking for GCP..."
    
    GCP_METADATA_URL="http://metadata.google.internal/computeMetadata/v1/"
    
    if curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}" &>/dev/null; then
        mkdir -p "${OUTPUT_DIR}/gcp"
        log_info "[${MODULE_NAME}] GCP detected"
        
        # インスタンス情報
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/?recursive=true" > "${OUTPUT_DIR}/gcp/instance-metadata.json" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/id" > "${OUTPUT_DIR}/gcp/instance-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/name" > "${OUTPUT_DIR}/gcp/instance-name.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/zone" > "${OUTPUT_DIR}/gcp/zone.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/machine-type" > "${OUTPUT_DIR}/gcp/machine-type.txt" 2>/dev/null
        
        # ネットワーク情報
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/network-interfaces/" > "${OUTPUT_DIR}/gcp/network-interfaces.txt" 2>/dev/null
        
        # サービスアカウント
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}instance/service-accounts/" > "${OUTPUT_DIR}/gcp/service-accounts.txt" 2>/dev/null
        
        # プロジェクト情報
        curl -sf --max-time ${TIMEOUT} -H "Metadata-Flavor: Google" "${GCP_METADATA_URL}project/?recursive=true" > "${OUTPUT_DIR}/gcp/project-metadata.json" 2>/dev/null
        
        log_success "[${MODULE_NAME}] GCP metadata collected"
        return 0
    fi
    return 1
}

# 4. Oracle Cloud Infrastructure メタデータ
check_oci() {
    log_info "[${MODULE_NAME}] Checking for Oracle Cloud..."
    
    OCI_METADATA_URL="http://169.254.169.254/opc/v1/"
    
    if curl -sf --max-time ${TIMEOUT} "${OCI_METADATA_URL}instance/" &>/dev/null; then
        mkdir -p "${OUTPUT_DIR}/oci"
        log_info "[${MODULE_NAME}] Oracle Cloud detected"
        
        # インスタンス情報
        curl -sf --max-time ${TIMEOUT} "${OCI_METADATA_URL}instance/" > "${OUTPUT_DIR}/oci/instance-metadata.json" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${OCI_METADATA_URL}instance/id" > "${OUTPUT_DIR}/oci/instance-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${OCI_METADATA_URL}instance/region" > "${OUTPUT_DIR}/oci/region.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${OCI_METADATA_URL}instance/shape" > "${OUTPUT_DIR}/oci/shape.txt" 2>/dev/null
        
        # VNIC情報
        curl -sf --max-time ${TIMEOUT} "${OCI_METADATA_URL}vnics/" > "${OUTPUT_DIR}/oci/vnics.json" 2>/dev/null
        
        log_success "[${MODULE_NAME}] Oracle Cloud metadata collected"
        return 0
    fi
    return 1
}

# 5. DigitalOcean メタデータ
check_digitalocean() {
    log_info "[${MODULE_NAME}] Checking for DigitalOcean..."
    
    DO_METADATA_URL="http://169.254.169.254/metadata/v1/"
    
    if curl -sf --max-time ${TIMEOUT} "${DO_METADATA_URL}" &>/dev/null; then
        mkdir -p "${OUTPUT_DIR}/digitalocean"
        log_info "[${MODULE_NAME}] DigitalOcean detected"
        
        curl -sf --max-time ${TIMEOUT} "${DO_METADATA_URL}id" > "${OUTPUT_DIR}/digitalocean/droplet-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${DO_METADATA_URL}hostname" > "${OUTPUT_DIR}/digitalocean/hostname.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${DO_METADATA_URL}region" > "${OUTPUT_DIR}/digitalocean/region.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${DO_METADATA_URL}interfaces/" > "${OUTPUT_DIR}/digitalocean/interfaces.json" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${DO_METADATA_URL}tags" > "${OUTPUT_DIR}/digitalocean/tags.txt" 2>/dev/null
        
        log_success "[${MODULE_NAME}] DigitalOcean metadata collected"
        return 0
    fi
    return 1
}

# 6. Alibaba Cloud メタデータ
check_alibaba() {
    log_info "[${MODULE_NAME}] Checking for Alibaba Cloud..."
    
    ALIBABA_METADATA_URL="http://100.100.100.200/latest/meta-data/"
    
    if curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}" &>/dev/null; then
        mkdir -p "${OUTPUT_DIR}/alibaba"
        log_info "[${MODULE_NAME}] Alibaba Cloud detected"
        
        curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}instance-id" > "${OUTPUT_DIR}/alibaba/instance-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}instance-type" > "${OUTPUT_DIR}/alibaba/instance-type.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}region-id" > "${OUTPUT_DIR}/alibaba/region-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}zone-id" > "${OUTPUT_DIR}/alibaba/zone-id.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}private-ipv4" > "${OUTPUT_DIR}/alibaba/private-ipv4.txt" 2>/dev/null
        curl -sf --max-time ${TIMEOUT} "${ALIBABA_METADATA_URL}eipv4" > "${OUTPUT_DIR}/alibaba/public-ipv4.txt" 2>/dev/null
        
        log_success "[${MODULE_NAME}] Alibaba Cloud metadata collected"
        return 0
    fi
    return 1
}

# すべてのクラウドプロバイダーをチェック
CLOUD_DETECTED=0

check_aws && CLOUD_DETECTED=1
check_azure && CLOUD_DETECTED=1
check_gcp && CLOUD_DETECTED=1
check_oci && CLOUD_DETECTED=1
check_digitalocean && CLOUD_DETECTED=1
check_alibaba && CLOUD_DETECTED=1

if [ ${CLOUD_DETECTED} -eq 0 ]; then
    log_info "[${MODULE_NAME}] No cloud environment detected (on-premises or unsupported cloud)"
    echo "No cloud environment detected" > "${OUTPUT_DIR}/no_cloud.txt"
fi

log_success "[${MODULE_NAME}] Cloud metadata collection complete"
