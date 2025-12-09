================================================================================
  LDIR-Toolkit v0.2.0 - Extended Multi-Environment Support
  Linux Disaster & Incident Response Toolkit - 拡張版
================================================================================

【概要 Overview】
LDIR-Toolkitは、Linuxシステムにおけるインシデント対応・フォレンジック調査のための
軽量かつ包括的なデータ収集ツールです。本拡張版（v0.2.0）は、標準的なディストリ
ビューションに加え、特殊環境・カスタマイズ環境にも対応しています。

【対応環境 Supported Environments】

◆ Standard Distributions（標準ディストリビューション）
  - Ubuntu (20.04 LTS / 22.04 LTS / 24.04 LTS)
  - Debian (11 / 12 / sid)
  - Rocky Linux (8 / 9)
  - AlmaLinux (8 / 9)
  - CentOS (7 / Stream 8 / Stream 9)
  - Fedora (38 / 39 / 40)
  - Amazon Linux 2 / 2023

◆ Special Purpose（特殊用途）
  - Arch Linux
  - openSUSE Leap / Tumbleweed
  - Gentoo Linux
  - Alpine Linux

◆ Embedded & IoT（組み込み・IoT）
  - Raspberry Pi OS (Raspbian)
  - Armbian

◆ Cloud-Specific（クラウド特化）
  - Oracle Linux
  - Google Cloud Optimized OS

◆ Custom Environments（カスタム環境）
  - systemd-less environments (OpenRC / runit / s6)
  - Minimal configurations (busybox-based)
  - SELinux / AppArmor enabled systems
  - Non-standard path configurations

【主な機能 Key Features】

✓ 自動ディストリビューション検出（Advanced Detection）
  - /etc/os-release 解析
  - パッケージマネージャ検出（apt/yum/dnf/pacman/zypper/apk）
  - Init system 検出（systemd/OpenRC/runit/s6）
  
✓ 包括的データ収集（10モジュール）
  1. システム情報 (System Info)
  2. ログファイル (Logs)
  3. 認証情報 (Authentication)
  4. 永続化機構 (Persistence)
  5. 実行履歴 (Execution History)
  6. ネットワーク (Network)
  7. ファイルシステム (Filesystem)
  8. Webアーティファクト (Web Artifacts)
  9. カスタム環境対応 (Custom Environment Detection)
  10. クラウドメタデータ (Cloud Metadata) - NEW in v0.2.0

✓ 証跡性の確保
  - SHA256ハッシュ生成（file_hashes.txt）
  - マニフェスト作成（manifest.txt）
  - 実行ログ保存（execution.log）

【クイックスタート Quickstart】

◆ パターン1: Linuxサーバ直接実行
  1. tar -xzf ldir-toolkit-v0.2.0.tar.gz
  2. cd ldir-toolkit-v0.2.0
  3. sudo ./ldir-collect.sh /tmp/ldir_output
  4. tar -czf ldir_result_$(hostname)_$(date +%Y%m%d_%H%M%S).tar.gz /tmp/ldir_output/

◆ パターン2: Windows経由でLinuxサーバへ転送
  1. [Windows] WinSCP (https://winscp.net/) でツールをアップロード
  2. [Linux] tar -xzf ldir-toolkit-v0.2.0.tar.gz
  3. [Linux] cd ldir-toolkit-v0.2.0
  4. [Linux] sudo ./ldir-collect.sh /tmp/ldir_output
  5. [Windows] WinSCPで結果をダウンロード

◆ パターン3: Live USB/外部メディアから実行
  1. Live USBでターゲットシステムをブート
  2. USBにldir-toolkit-v0.2.0をコピー済み
  3. sudo ./ldir-collect.sh /mnt/evidence/ldir_output
  4. 収集完了後、USBを物理的に取り外して証拠保全

【必要要件 Requirements】

  OS: Linux (Any distribution - see Supported Environments)
  権限: root or sudo
  ストレージ: 最低 10GB の空き容量推奨
  実行時間: 約 2〜5 分（システム規模により変動）

【収集データ Collected Data】

  ├─ system_info/       システム情報（uname, hostname, users, groups）
  ├─ logs/              ログファイル（syslog, auth.log, journal等）
  ├─ auth/              認証情報（sudoers, ssh設定、PAM設定）
  ├─ persistence/       永続化機構（cron, systemd units, init scripts）
  ├─ execution/         実行履歴（bash_history, プロセスリスト）
  ├─ network/           ネットワーク（接続、ルーティング、ファイアウォール）
  ├─ filesystem/        ファイルシステム（マウント、最近変更ファイル）
  ├─ web/               Webアーティファクト（ブラウザ履歴、Cookie）
  ├─ custom_environment/ カスタム環境情報（init system, package manager）
  ├─ cloud_metadata/    クラウドメタデータ（AWS/GCP/Azure識別情報） ★NEW
  └─ metadata/          証跡情報（manifest.txt, file_hashes.txt）

【証跡性の確認 Verification】

  実行後、以下のファイルで証跡性を確認できます：
  
  - metadata/manifest.txt      : 収集ファイル一覧
  - metadata/file_hashes.txt   : 各ファイルのSHA256ハッシュ
  - execution.log              : ツール実行ログ（タイムスタンプ付き）

【トラブルシューティング Troubleshooting】

Q: "Permission denied" エラーが発生する
A: sudo権限で実行してください: sudo ./ldir-collect.sh /output

Q: 特定のモジュールがスキップされる
A: 通常の動作です。環境によって存在しないパスは自動スキップされます。

Q: 収集に10分以上かかる
A: 大規模システムでは時間がかかる場合があります。--quick オプション実装予定。

Q: "command not found" エラー
A: 実行権限を確認: chmod +x ldir-collect.sh

Q: クラウド環境でメタデータが取得できない
A: IMDSv2トークン取得に失敗している可能性。ネットワーク設定を確認してください。

【SHA256ハッシュ検証 Hash Verification】

  配布パッケージの整合性確認:
  
  $ sha256sum -c ldir-toolkit-v0.2.0.tar.gz.sha256
  
  正常な場合: "ldir-toolkit-v0.2.0.tar.gz: OK" と表示されます

【変更履歴 Changelog】

v0.2.0 (2025-12-08)
  + 拡張ディストリビューション対応（Arch/openSUSE/Gentoo/Alpine/Raspberry Pi OS等）
  + カスタム環境検出モジュール追加（90_custom_environment.sh）
  + クラウドメタデータ収集モジュール追加（91_cloud_metadata.sh）
  + 高度なディストリビューション検出ロジック（detect_distro_advanced.sh）
  + systemd非依存環境への対応（OpenRC/runit/s6）
  + 最小構成環境への対応（busybox-based）

v0.1.0 (Initial Release)
  + 基本的な8モジュール実装
  + Ubuntu/Debian/Rocky Linux対応
  + Docker テスト環境構築

【サポート・問い合わせ Support】

  本ツールに関する詳細は、同梱の以下ドキュメントを参照してください：
  
  - PRODUCTION_DEPLOYMENT.md : 本番環境での展開方法
  - EXTENDED_SETUP_GUIDE.md  : Docker環境でのテスト方法

【ライセンス License】

  本ツールは教育・研究・正当なセキュリティ調査目的での使用を想定しています。
  不正アクセスや権限のないシステムへの使用は厳禁です。

================================================================================
  End of README - LDIR-Toolkit v0.2.0
================================================================================
