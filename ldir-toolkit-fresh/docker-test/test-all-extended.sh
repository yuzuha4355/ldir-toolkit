#!/bin/bash
#######################################################################
# LDIR Extended Test Script - All 11 Distributions
# 全11ディストリビューションでLDIR-Toolkitを実行
#######################################################################

set -euo pipefail

# カラー定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

COMPOSE_FILE="docker-compose-extended.yml"

# 全ディストリビューションリスト
DISTROS=(
    "centos7"
    "centos9"
    "rocky"
    "alma"
    "amazon"
    "ubuntu20"
    "ubuntu"
    "ubuntu24"
    "debian11"
    "debian"
    "fedora"
)

# バナー表示
echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║    🐉 LDIR Extended Test Suite - 11 Distributions 🐉         ║
║                                                               ║
║    Linux Digital Incident Response Toolkit                   ║
║    Comprehensive Multi-Distribution Testing                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BLUE}[INFO]${NC} Starting comprehensive test across 11 Linux distributions..."
echo -e "${YELLOW}[WARN]${NC} This will take 15-30 minutes and use 6-8GB memory"
echo ""

# 開始時刻記録
START_TIME=$(date +%s)

# 各ディストリビューションをテスト
SUCCESSFUL=0
FAILED=0

for distro in "${DISTROS[@]}"; do
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Testing: ${distro}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # コンテナ起動
    echo -e "${BLUE}[1/4]${NC} Starting ${distro} container..."
    if docker-compose -f "${COMPOSE_FILE}" up -d ${distro}-test 2>&1 | grep -v "is up-to-date"; then
        echo -e "${GREEN}✓${NC} Container started"
    else
        echo -e "${RED}✗${NC} Failed to start container"
        ((FAILED++))
        continue
    fi
    
    # コンテナの準備完了を待つ
    echo -e "${BLUE}[2/4]${NC} Waiting for container to be ready..."
    sleep 3
    
    # LDIR-Toolkit実行
    echo -e "${BLUE}[3/4]${NC} Executing LDIR-Toolkit collection..."
    if docker exec ldir-${distro}-test /opt/ldir-toolkit/ldir-collect.sh /output 2>&1 | tail -5; then
        echo -e "${GREEN}✓${NC} Collection completed"
        ((SUCCESSFUL++))
    else
        echo -e "${RED}✗${NC} Collection failed"
        ((FAILED++))
    fi
    
    # コンテナ停止
    echo -e "${BLUE}[4/4]${NC} Stopping container..."
    docker-compose -f "${COMPOSE_FILE}" stop ${distro}-test > /dev/null 2>&1
    echo -e "${GREEN}✓${NC} Container stopped"
    
    echo ""
done

# 終了時刻記録
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# 全コンテナ停止
echo -e "${BLUE}[INFO]${NC} Cleaning up containers..."
docker-compose -f "${COMPOSE_FILE}" down > /dev/null 2>&1

# レポート生成
echo -e "${BLUE}[INFO]${NC} Generating visual report..."
if [ -f "./generate_report.sh" ]; then
    ./generate_report.sh
else
    echo -e "${YELLOW}[WARN]${NC} generate_report.sh not found, skipping report generation"
fi

# サマリー表示
echo ""
echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                     TEST SUMMARY                              ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${GREEN}✓ Successful:${NC} ${SUCCESSFUL}/${#DISTROS[@]}"
echo -e "${RED}✗ Failed:${NC}     ${FAILED}/${#DISTROS[@]}"
echo -e "${BLUE}⏱ Duration:${NC}   ${MINUTES}m ${SECONDS}s"
echo ""

# 収集結果統計
if [ -d "shared-output" ]; then
    TOTAL_FILES=$(find shared-output -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh shared-output 2>/dev/null | awk '{print $1}')
    COLLECTIONS=$(find shared-output -maxdepth 1 -type d -name "*-forensics_*" 2>/dev/null | wc -l)
    
    echo -e "${CYAN}📊 Collection Statistics:${NC}"
    echo -e "   Collections: ${COLLECTIONS}"
    echo -e "   Total Files: ${TOTAL_FILES}"
    echo -e "   Total Size:  ${TOTAL_SIZE}"
    echo ""
fi

# 次のステップ案内
echo -e "${CYAN}${BOLD}Next Steps:${NC}"
echo -e "  1. View HTML report: ${GREEN}firefox shared-output/collection_report.html${NC}"
echo -e "  2. Analyze results:  ${GREEN}ls -la shared-output/*-forensics_*/metadata/${NC}"
echo -e "  3. ZIP logs:         ${GREEN}zip -r collected_logs.zip shared-output/${NC}"
echo ""

echo -e "${GREEN}${BOLD}🎉 All tests completed!${NC}"
