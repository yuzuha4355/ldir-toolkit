#!/bin/bash
#
# LDIR-Toolkit 全ディストリビューション自動テストスクリプト
#

set -e

echo "=========================================="
echo "LDIR-Toolkit 自動テスト開始"
echo "=========================================="
echo ""

# カラー定義
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 出力ディレクトリのクリーンアップ
echo -e "${YELLOW}[準備]${NC} 出力ディレクトリをクリーンアップ中..."
rm -rf shared-output/*

# コンテナの起動
echo -e "${BLUE}[起動]${NC} すべてのコンテナをビルド・起動中..."
docker-compose up -d --build

# 少し待機
echo -e "${YELLOW}[待機]${NC} コンテナの起動を待機中..."
sleep 5

# テスト実行
echo ""
echo "=========================================="
echo "テスト実行"
echo "=========================================="
echo ""

# Ubuntu
echo -e "${GREEN}[Ubuntu]${NC} LDIR-Toolkit実行中..."
docker exec ldir-ubuntu-test /opt/ldir-toolkit/ldir-collect.sh /output
echo -e "${GREEN}[Ubuntu]${NC} 完了"
echo ""

# Debian
echo -e "${GREEN}[Debian]${NC} LDIR-Toolkit実行中..."
docker exec ldir-debian-test /opt/ldir-toolkit/ldir-collect.sh /output
echo -e "${GREEN}[Debian]${NC} 完了"
echo ""

# Rocky Linux
echo -e "${GREEN}[Rocky Linux]${NC} LDIR-Toolkit実行中..."
docker exec ldir-rocky-test /opt/ldir-toolkit/ldir-collect.sh /output
echo -e "${GREEN}[Rocky Linux]${NC} 完了"
echo ""

# 結果の確認
echo ""
echo "=========================================="
echo "収集結果"
echo "=========================================="
echo ""
ls -lh shared-output/

echo ""
echo "=========================================="
echo "詳細情報"
echo "=========================================="
echo ""

# 各ディストリビューションの収集結果サマリー
for dir in shared-output/*/; do
    if [[ -f "${dir}metadata/manifest.txt" ]]; then
        echo "--- $(basename "$dir") ---"
        cat "${dir}metadata/manifest.txt"
        echo ""
    fi
done

echo ""
echo -e "${GREEN}=========================================="
echo "テスト完了"
echo "==========================================${NC}"
echo ""
echo "収集結果は shared-output/ ディレクトリに保存されています"
echo ""
echo "コンテナを停止するには:"
echo "  docker-compose down"
echo ""
echo "コンテナに入るには:"
echo "  docker exec -it ldir-ubuntu-test /bin/bash"
echo "  docker exec -it ldir-debian-test /bin/bash"
echo "  docker exec -it ldir-rocky-test /bin/bash"
echo ""
