# LDIR-Toolkit クイックスタートガイド

## 5分で始めるLinuxフォレンジック

### ステップ1: ダウンロードと展開

```bash
# アーカイブを展開
tar -xzf ldir-toolkit-v0.1.0.tar.gz
cd ldir-toolkit
```

### ステップ2: 実行

```bash
# 基本的な使い方
sudo ./ldir-collect.sh

# 出力先を指定
sudo ./ldir-collect.sh /path/to/output
```

### ステップ3: 結果の確認

```bash
# 出力ディレクトリに移動（ホスト名と日時が自動付与される）
cd /path/to/output/hostname_YYYYMMDD_HHMMSS/

# マニフェストを確認
cat metadata/manifest.txt

# 収集されたファイルを確認
ls -lR
```

## USB収集の例

```bash
# USBメモリをマウント
sudo mount /dev/sdb1 /mnt/usb

# ツールをUSBにコピー
cp -r ldir-toolkit /mnt/usb/

# 収集実行
cd /mnt/usb/ldir-toolkit
sudo ./ldir-collect.sh /mnt/usb/evidence

# 完了後、USBを安全に取り外し
sudo umount /mnt/usb
```

## 収集される主要なデータ

| カテゴリ | 内容 |
|---------|------|
| **system/** | OS情報、ハードウェア、カーネル情報 |
| **logs/** | systemd journal、認証ログ、syslog |
| **config/** | ユーザ情報、SSH設定、PAM設定 |
| **persistence/** | systemdユニット、cron、自動起動 |
| **execution/** | 実行中プロセス、コマンド履歴 |
| **network/** | 接続状態、ファイアウォール、ルーティング |
| **filesystem/** | SUID/SGID、最近の変更、バイナリハッシュ |
| **web/** | ブラウザ履歴、Cookie、ダウンロード |

## トラブルシューティング

### Q: 権限エラーが出る
**A**: `sudo` を付けて実行してください

### Q: 一部のファイルが収集されない
**A**: 正常です。存在しないファイルは警告を出してスキップします

### Q: ディスク容量が足りない
**A**: 大規模システムでは1GB以上必要な場合があります

## 次のステップ

- 収集データの分析方法: README.mdの「分析」セクションを参照
- モジュールのカスタマイズ: README.mdの「開発情報」を参照
- インシデント対応フロー: README.mdの「インシデント対応」を参照

## サポート

- ドキュメント: [README.md](README.md)
- Issue報告: GitHubリポジトリ
