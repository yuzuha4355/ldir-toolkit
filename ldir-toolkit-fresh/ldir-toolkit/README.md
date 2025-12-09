# LDIR-Toolkit - Linux Digital Incident Response Toolkit

## 概要

LDIR-Toolkit は、Linuxシステムにおけるデジタルフォレンジックアーティファクトを収集・分析するための統合ツールです。Windows版CDIR-C/CDIR-Aに相当するLinux版として設計されています。

## 特徴

- **統合収集**: 一つのコマンドで必要な全てのアーティファクトを収集
- **モジュール式**: 各収集項目が独立したモジュールとして実装
- **ディストリビューション対応**: 主要なLinuxディストリビューションを自動検出
- **エラー耐性**: 一部のモジュールが失敗しても処理を継続
- **完全性検証**: 収集データのSHA256ハッシュを自動計算
- **詳細ログ**: 収集プロセス全体を記録

## 収集されるアーティファクト

### 1. システム情報 (10_system_info.sh)
- OS情報、カーネルバージョン
- ハードウェア情報
- ネットワーク設定
- タイムゾーン

### 2. ログファイル (20_logs.sh)
- systemd journal
- 認証ログ (auth.log/secure)
- システムログ (syslog/messages)
- ログイン履歴 (wtmp/btmp/lastlog)
- Webサーバ/データベースログ

### 3. 認証情報 (30_auth.sh)
- ユーザ・グループ情報
- sudoers設定
- SSH設定と公開鍵
- PAM設定

### 4. 永続化機構 (40_persistence.sh)
- systemdユニットファイル
- cron設定
- 起動スクリプト
- シェル初期化ファイル
- デスクトップ自動起動
- LD_PRELOAD参照

### 5. 実行履歴 (50_execution.sh)
- 実行中プロセス
- /proc情報
- コマンド履歴 (bash/zsh)
- auditdログ

### 6. ネットワーク情報 (60_network.sh)
- ネットワーク接続状態
- ルーティングテーブル
- ARPキャッシュ
- ファイアウォール設定
- DNS設定

### 7. ファイルシステム (70_filesystem.sh)
- マウント情報
- 最近変更されたファイル
- SUID/SGIDファイル
- 隠しファイル
- システムバイナリのハッシュ

### 8. Webブラウザ (80_web.sh)
- Firefox履歴・Cookie
- Chrome/Chromium履歴・Cookie
- Brave/Opera/Edge履歴

## インストール

```bash
# リポジトリのクローン（GitHubにアップロード後）
git clone https://github.com/your-repo/ldir-toolkit.git
cd ldir-toolkit

# 実行権限の付与
chmod +x ldir-collect.sh
chmod +x modules/*.sh
chmod +x lib/*.sh
```

## 使用方法

### 基本的な使用方法

```bash
# root権限で実行（デフォルト出力先: /tmp/LDIR_OUTPUT）
sudo ./ldir-collect.sh

# 出力先を指定して実行
sudo ./ldir-collect.sh /media/usb/evidence

# USBメディアへの収集例
sudo mount /dev/sdb1 /mnt/usb
sudo ./ldir-collect.sh /mnt/usb/evidence
```

### 出力構造

```
/output/directory/
└── hostname_20251204_143052/
    ├── metadata/
    │   ├── collection.log       # 収集プロセスのログ
    │   ├── manifest.txt         # 収集情報のマニフェスト
    │   ├── file_hashes.txt      # 全ファイルのSHA256ハッシュ
    │   └── module_*.log         # 各モジュールの実行ログ
    ├── system/                  # システム情報
    ├── logs/                    # ログファイル
    ├── config/                  # 設定ファイル・認証情報
    ├── persistence/             # 永続化機構
    ├── execution/               # 実行履歴
    ├── network/                 # ネットワーク情報
    ├── filesystem/              # ファイルシステム情報
    └── web/                     # ブラウザアーティファクト
```

## 対応ディストリビューション

- Ubuntu / Debian
- CentOS / RHEL / Fedora
- Arch Linux / Manjaro
- openSUSE / SLES
- その他のsystemd/SysVinitベースのディストリビューション

## 必要な権限

- **root権限が必須**: 多くのログファイルや設定ファイルはroot所有のため

## 推奨環境

- **実行方法**: Live USBから起動、または対象システム上で直接実行
- **ストレージ**: 外部USB/ネットワークストレージへの出力を推奨
- **メモリ**: 最低512MB（収集データ量による）

## インシデント対応フロー

1. **準備**
   ```bash
   # USBメモリにツールをコピー
   cp -r ldir-toolkit /mnt/usb/
   ```

2. **対象システムで実行**
   ```bash
   cd /mnt/usb/ldir-toolkit
   sudo ./ldir-collect.sh /mnt/usb/evidence
   ```

3. **収集完了後**
   - `manifest.txt` で収集内容を確認
   - `file_hashes.txt` でデータ完全性を検証
   - 収集データを安全な場所へコピー

4. **分析**
   - タイムライン分析
   - 永続化機構の確認
   - ネットワーク接続の調査
   - 不審なプロセス/ファイルの特定

## トラブルシューティング

### 権限エラー
```bash
[ERROR] This script must be run as root
```
**解決**: `sudo` を使用して実行してください

### 一部モジュールの失敗
- ログに `[WARN]` が表示される場合、該当ファイルが存在しないか、アクセスできません
- 収集は継続されるため、他のデータは正常に収集されます

### ディスク容量不足
- 出力先に十分な空き容量があることを確認してください
- 大規模システムでは数GB必要になることがあります

## 開発情報

### アーキテクチャ

```
ldir-toolkit/
├── ldir-collect.sh         # メインスクリプト
├── lib/
│   ├── common.sh           # 共通関数（ログ、ファイルコピー）
│   └── detect_distro.sh    # ディストリビューション検出
└── modules/
    ├── 10_system_info.sh   # システム情報
    ├── 20_logs.sh          # ログ収集
    ├── 30_auth.sh          # 認証情報
    ├── 40_persistence.sh   # 永続化機構
    ├── 50_execution.sh     # 実行履歴
    ├── 60_network.sh       # ネットワーク
    ├── 70_filesystem.sh    # ファイルシステム
    └── 80_web.sh           # Webブラウザ
```

### モジュールの追加方法

1. `modules/` に新しいスクリプトを作成
2. ファイル名を `[番号]_[名前].sh` の形式に
3. 第一引数として `OUTPUT_DIR` を受け取る
4. `exit 0` で正常終了

```bash
#!/bin/bash
OUTPUT_DIR="$1"
CUSTOM_DIR="${OUTPUT_DIR}/custom"

# 共通関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

log_info "Starting custom collection"
# 収集処理
log_success "Custom collection completed"
exit 0
```

## ライセンス

MIT License

## 貢献

プルリクエスト、Issue報告を歓迎します。

## 参考資料

- SANS SIFT Workstation
- JPCERT/CC インシデントハンドリングマニュアル
- The Sleuth Kit
- CDIR-C/CDIR-A (Cyber Defense Institute)

## バージョン履歴

- **v0.1.0** (2024-12-04): 初版リリース
  - 基本的な収集機能
  - 8つのコアモジュール
  - 主要ディストリビューション対応

## 作成者

[@yuzuha4355](https://github.com/yuzuha4355)

## 連絡先

Issue: https://github.com/your-repo/ldir-toolkit/issues
