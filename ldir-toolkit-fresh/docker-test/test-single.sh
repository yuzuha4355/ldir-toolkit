#!/bin/bash
#
# LDIR-Toolkit 単一ディストリビューションテストスクリプト
#

DISTRO="${1:-ubuntu}"

case "$DISTRO" in
    ubuntu)
        CONTAINER="ldir-ubuntu-test"
        SERVICE="ubuntu-test"
        ;;
    debian)
        CONTAINER="ldir-debian-test"
        SERVICE="debian-test"
        ;;
    rocky|centos)
        CONTAINER="ldir-rocky-test"
        SERVICE="rocky-test"
        ;;
    *)
        echo "Usage: $0 [ubuntu|debian|rocky]"
        exit 1
        ;;
esac

echo "=========================================="
echo "LDIR-Toolkit テスト: ${DISTRO}"
echo "=========================================="
echo ""

# コンテナの起動
echo "[起動] ${DISTRO} コンテナをビルド・起動中..."
docker-compose up -d --build ${SERVICE}

# 待機
echo "[待機] コンテナの起動を待機中..."
sleep 3

# テスト実行
echo ""
echo "[実行] LDIR-Toolkit実行中..."
docker exec ${CONTAINER} /opt/ldir-toolkit/ldir-collect.sh /output

# 結果確認
echo ""
echo "=========================================="
echo "収集結果"
echo "=========================================="
ls -lh shared-output/

echo ""
echo "=========================================="
echo "マニフェスト"
echo "=========================================="
for dir in shared-output/*/; do
    if [[ -f "${dir}metadata/manifest.txt" ]]; then
        cat "${dir}metadata/manifest.txt"
    fi
done

echo ""
echo "テスト完了"
echo ""
echo "コンテナに入るには:"
echo "  docker exec -it ${CONTAINER} /bin/bash"
echo ""
