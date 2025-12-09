#!/bin/bash
#######################################################################
# Local Log Archiving Script
# ローカル環境のshared-output/をZIP化してダウンロード可能にする
#######################################################################

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Creating archive of collected logs..."

# アーカイブ名（タイムスタンプ付き）
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="ldir_collected_logs_${TIMESTAMP}.zip"

# shared-output/が存在するか確認
if [ ! -d "shared-output" ]; then
    echo -e "${YELLOW}[WARN]${NC} shared-output/ directory not found!"
    echo -e "${YELLOW}[INFO]${NC} Please run tests first: ./test-all-extended.sh"
    exit 1
fi

# 収集統計を表示
TOTAL_COLLECTIONS=$(find shared-output -maxdepth 1 -type d -name "*-forensics_*" 2>/dev/null | wc -l)
TOTAL_FILES=$(find shared-output -type f 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh shared-output 2>/dev/null | awk '{print $1}')

echo -e "${BLUE}[INFO]${NC} Archive contents:"
echo -e "   Collections: ${TOTAL_COLLECTIONS}"
echo -e "   Total Files: ${TOTAL_FILES}"
echo -e "   Total Size:  ${TOTAL_SIZE}"
echo ""

# ZIP作成
echo -e "${BLUE}[INFO]${NC} Creating ZIP archive..."
zip -r "${ARCHIVE_NAME}" shared-output/ -x "*.zip" > /dev/null 2>&1

# 結果表示
if [ -f "${ARCHIVE_NAME}" ]; then
    ARCHIVE_SIZE=$(ls -lh "${ARCHIVE_NAME}" | awk '{print $5}')
    echo -e "${GREEN}[SUCCESS]${NC} Archive created: ${ARCHIVE_NAME}"
    echo -e "${GREEN}[SUCCESS]${NC} Archive size: ${ARCHIVE_SIZE}"
    echo ""
    
    # Windowsダウンロードフォルダへのコピー案内
    echo -e "${YELLOW}[TIP]${NC} To copy to Windows Downloads folder:"
    echo -e "   ${GREEN}cp ${ARCHIVE_NAME} /mnt/c/Users/YOUR_USERNAME/Downloads/${NC}"
    echo ""
    
    # 絶対パス表示
    ABSOLUTE_PATH=$(realpath "${ARCHIVE_NAME}")
    echo -e "${BLUE}[INFO]${NC} Absolute path: ${ABSOLUTE_PATH}"
else
    echo -e "${RED}[ERROR]${NC} Failed to create archive"
    exit 1
fi
