# LDIR-Toolkit Docker テスト環境

## 概要

LDIR-Toolkitを安全にテストするためのDocker環境です。
複数のLinuxディストリビューションでツールの動作を検証できます。

## 含まれる環境

- **Ubuntu 22.04** (ubuntu-test)
- **Debian 12** (debian-test)
- **Rocky Linux 9** (rocky-test) - CentOS後継

## 前提条件

- Docker がインストールされていること
- Docker Compose がインストールされていること

## クイックスタート

### 1. 環境の起動

```bash
# すべてのコンテナをビルド・起動
docker-compose up -d --build
```

### 2. コンテナに入る

```bash
# Ubuntu環境
docker exec -it ldir-ubuntu-test /bin/bash

# Debian環境
docker exec -it ldir-debian-test /bin/bash

# Rocky Linux環境
docker exec -it ldir-rocky-test /bin/bash
```

### 3. LDIR-Toolkitを実行

コンテナ内で:

```bash
# デフォルト出力先で実行
./ldir-collect.sh

# 共有ボリュームに出力（ホストから確認可能）
./ldir-collect.sh /output
```

### 4. 収集結果の確認

ホスト側で:

```bash
# 共有出力ディレクトリを確認
ls -la shared-output/
```

### 5. 環境の停止・削除

```bash
# 停止
docker-compose down

# 停止＋イメージ削除
docker-compose down --rmi all

# 停止＋イメージ削除＋ボリューム削除
docker-compose down --rmi all -v
```

## 詳細な使用方法

### 特定のディストリビューションのみ起動

```bash
# Ubuntuのみ
docker-compose up -d ubuntu-test

# Debianのみ
docker-compose up -d debian-test

# Rocky Linuxのみ
docker-compose up -d rocky-test
```

### ログの確認

```bash
# すべてのコンテナのログ
docker-compose logs

# 特定のコンテナのログ
docker-compose logs ubuntu-test

# ログをフォロー
docker-compose logs -f ubuntu-test
```

### コンテナの状態確認

```bash
docker-compose ps
```

## テストシナリオ例

### シナリオ1: 基本的な動作確認

```bash
# Ubuntuコンテナに入る
docker exec -it ldir-ubuntu-test /bin/bash

# ツールを実行
./ldir-collect.sh /output

# ホスト側で結果確認
exit
ls -la shared-output/
```

### シナリオ2: 複数ディストリビューションでの比較

```bash
# すべて起動
docker-compose up -d

# Ubuntu
docker exec -it ldir-ubuntu-test ./ldir-collect.sh /output

# Debian
docker exec -it ldir-debian-test ./ldir-collect.sh /output

# Rocky Linux
docker exec -it ldir-rocky-test ./ldir-collect.sh /output

# 結果を比較
ls -la shared-output/
```

### シナリオ3: 特定モジュールのテスト

```bash
docker exec -it ldir-ubuntu-test /bin/bash

# 特定のモジュールのみ実行（手動）
cd /opt/ldir-toolkit
OUTPUT_DIR=/tmp/test_output
mkdir -p $OUTPUT_DIR
bash modules/20_logs.sh $OUTPUT_DIR
```

## ディレクトリ構造

```
ldir-docker-test/
├── Dockerfile.ubuntu        # Ubuntu用Dockerfile
├── Dockerfile.debian        # Debian用Dockerfile
├── Dockerfile.centos        # Rocky Linux用Dockerfile
├── docker-compose.yml       # Docker Compose設定
├── ldir-toolkit/            # LDIR-Toolkitのソース
│   ├── ldir-collect.sh
│   ├── modules/
│   ├── lib/
│   └── ...
├── shared-output/           # 共有出力ディレクトリ（ホスト⇔コンテナ）
└── README.md               # このファイル
```

## トラブルシューティング

### Q: コンテナが起動しない

**A**: Dockerデーモンが起動しているか確認
```bash
docker ps
```

### Q: privileged: true が必要な理由

**A**: LDIR-Toolkitは以下の操作に特権が必要です:
- /proc へのフルアクセス
- systemd journal へのアクセス
- すべてのログファイルへのアクセス

### Q: 収集結果がホストに表示されない

**A**: 出力先を `/output` に指定してください
```bash
./ldir-collect.sh /output
```

### Q: モジュールが一部失敗する

**A**: 正常です。コンテナ環境では一部のファイルが存在しない場合があります。
ログで `[WARN]` を確認してください。

## セキュリティに関する注意

- この環境はテスト専用です
- privileged モードを使用しているため、プロダクション環境では使用しないでください
- コンテナ内のパスワードはテスト用のダミーです

## カスタマイズ

### 追加パッケージのインストール

Dockerfileに追加:
```dockerfile
RUN apt-get install -y your-package
```

### テストデータの追加

Dockerfileに追加:
```dockerfile
RUN echo "test data" > /var/log/custom.log
```

## ライセンス

LDIR-Toolkitと同様、MIT Licenseです。

## バージョン

- Docker環境バージョン: 1.0.0
- LDIR-Toolkit: v0.1.0
