# LDIR-Toolkit 仕様書

対象バージョン: 0.4.0

この文書は、収集ツール `ldir-collect.sh` が「何を・どの順で・どこへ」出力するかを定めます。
実施の手順は [PROCEDURE.md](PROCEDURE.md) を参照してください。

---

## 1. 目的と範囲

LDIR-Toolkit は、インシデント対応の初動で Linux ホストから調査用のアーティファクトを収集するツールです。

| 項目 | 内容 |
|---|---|
| 行うこと | 稼働中ホストの状態・設定・ログを読み取り、1 つのディレクトリにまとめる。ハッシュ一覧を作る |
| 行わないこと | メモリダンプ、ディスクイメージ取得、収集物の解析、対象ホストの修復・封じ込め |
| 対象ホストへの変更 | 出力先への書き込みのみ。設定変更・パッケージ導入・サービス操作は行わない |

対象ホスト上でコマンドを実行する以上、ファイルのアクセス時刻（atime）やプロセス一覧など、状態への影響はゼロにはなりません。
これは稼働中収集の性質です。厳密な保全が必要な場合は、ディスクイメージの取得を別途検討してください。

管理デーモンへの問い合わせ（`docker info`、`virsh` 等）は、ソケット起動（socket activation）の環境ではデーモンを起動させることがあります。
設定ファイルを新たに作るコマンド（root で初めて動かす `VBoxManage`、LXD の `lxc` クライアント）は使いません（7.6 節）。

## 2. 動作要件

| 項目 | 要件 |
|---|---|
| OS | Linux |
| シェル | bash 4.2 以上（Alpine など bash が無い環境では事前に導入が必要） |
| 権限 | root（`sudo` 可）。root でない場合は何も収集せず終了する |
| 必須コマンド | `find` `awk` `sed` `sort` `stat` `head` `xargs` `sha256sum` `cp` `tar`（`--archive` 使用時） |
| 任意コマンド | 無ければ該当項目を飛ばす: `journalctl` `ausearch` `ss` `lsof` `bpftool` `getcap` `getent` `sshd` `docker` `crictl` `virsh` `qm` `pct` `curl` など |
| ネットワーク | 不要。クラウドメタデータ収集を有効にした場合のみ、リンクローカルの API へ接続する |
| 空き容量 | fast: 数十 MB〜数百 MB（ログは群ごとに既定 100 MB まで。4.1 節）。full: ログ量とユーザーデータに依存し、GB 単位になり得る |

CI で実収集を確認している環境: Ubuntu 20.04 / 24.04、Debian 12、Rocky Linux 9、AlmaLinux 8、Fedora、Amazon Linux 2023、Arch Linux、openSUSE Leap 15、Alpine 3（BusyBox）、および GitHub の実機ランナー（Ubuntu、systemd と Docker が稼働）。

**未確認の範囲**: SELinux 有効環境、実際のクラウドインスタンス、稼働中の Kubernetes ノード、ハイパーバイザのホスト（libvirt / Proxmox VE / LXD / Incus / VirtualBox / Xen）。仮想化モジュールのホスト側はモックによる単体テストのみで確認している。

## 3. コマンドライン

```
ldir-collect.sh [options] [output_directory]
```

| 引数 / オプション | 内容 |
|---|---|
| `output_directory` | 出力のベースディレクトリ。省略時は `/tmp/ldir_output` |
| `-m`, `--mode MODE` | `fast`（既定）または `full` |
| `-a`, `--archive` | 収集後に `tar.gz` と `.sha256` を作成する |
| `--log-days N` | ログの収集期間。`30`（既定）・`60`・`90` のみ。それ以外は終了コード 1 で終了する |
| `--log-max-mb N` | ログ群ごとの容量の上限（MB）。既定 `100`。`0` で上限なし |
| `--no-redact` | 環境変数・VM 定義・ハイパーバイザ設定の秘匿値マスクを行わない |
| `-l`, `--list-modules` | モジュール一覧を表示して終了 |
| `-V`, `--version` | バージョンを表示して終了 |
| `-h`, `--help` | 使い方を表示して終了 |

### 3.1 環境変数

| 変数 | 既定値 | 内容 |
|---|---|---|
| `LDIR_MODE` | `fast` | `--mode` と同じ |
| `LDIR_LOG_DAYS` | fast: `30` / full: 期間なし | `--log-days` と同じ。`30` `60` `90` のみ |
| `LDIR_LOG_MAX_MB` | fast: `100` / full: 上限なし | `--log-max-mb` と同じ |
| `LDIR_LOG_CMD_TIMEOUT` | fast: `120` / full: なし | `journalctl` `ausearch` 1 回あたりの時間上限（秒）。`0` で上限なし |
| `LDIR_ENABLE_WEB` | fast: `0` / full: `1` | ブラウザアーティファクトの収集 |
| `LDIR_ENABLE_CLOUD_METADATA` | fast: `0` / full: `1` | クラウドメタデータ API への問い合わせ |
| `LDIR_ARCHIVE` | `0` | `--archive` と同じ |
| `LDIR_REDACT_SECRETS` | `1` | 秘匿値マスク。`0` で無効（`--no-redact` と同じ） |
| `LDIR_VERBOSE` | `0` | 「対象が存在しない」通知も画面に出す |
| `LDIR_CLOUD_METADATA_TIMEOUT` | `2` | メタデータ API 1 回あたりの待ち時間（秒） |
| `LDIR_FAST_SCAN_BUDGET` | `60` | fast モードで SUID/SGID・world-writable の検索に使える時間（秒）。超えた分は打ち切り、WARN を出す |
| `LDIR_CONTAINER_TIMEOUT` | `20` | コンテナランタイムへの問い合わせ 1 回あたりの待ち時間（秒） |
| `LDIR_VIRT_TIMEOUT` | `20` | ハイパーバイザ管理コマンド（`virsh` `qm` 等）1 回あたりの待ち時間（秒） |
| `LDIR_VIRT_BUDGET` | fast: `60` / full: なし | VM ごとの詳細の問い合わせに使える合計時間（秒）。超えた分は打ち切り、WARN を出す |
| `NO_COLOR` | 未設定 | 設定すると画面出力を着色しない |

`sudo` は既定で環境変数を引き継ぎません。変数で指定する場合は `sudo LDIR_MODE=full ./ldir-collect.sh ...` のように `sudo` の後ろに書きます。

### 3.2 終了コード

| コード | 意味 |
|---|---|
| `0` | すべてのモジュールが完了した |
| `1` | 引数の誤り（`--log-days 45` 等）、root でない、出力先を作れない等。何も収集していない |
| `2` | 収集は終わったが、失敗したモジュールがある、またはハッシュ一覧・アーカイブの作成に失敗した |

## 4. 収集モード

| | fast（既定） | full |
|---|---|---|
| 想定 | 初動。短時間・小容量 | 詳細調査。時間と容量がかかる |
| ログの期間 | 30 日（`--log-days` で 60 / 90） | 全期間（`--log-days` を指定すればそれに従う） |
| ログの容量の上限 | ログ群ごとに 100 MB（`--log-max-mb`） | なし（`--log-max-mb` を指定すればそれに従う） |
| journal のテキスト出力 | 期間内（`journal_period.txt`） | 全期間（`journal_full.txt`） |
| 変更ファイル・SUID・world-writable の探索 | 主要パスのみ | `/` 全体 |
| システムバイナリのハッシュ | 取らない | `/bin` `/sbin` `/usr/bin` `/usr/sbin` |
| file capabilities の探索 | 主要パスのみ | `/` 全体 |
| プロセスごとの環境変数・オープンファイル | 取らない | 取る |
| ユーザーの `~/.config` | 一覧のみ | 丸ごとコピー |
| コンテナのログ末尾・`top` | 取らない | 取る |
| VM ごとの詳細 | 合計 60 秒まで | 時間の上限なし |
| ブラウザ / クラウドメタデータ | 無効 | 有効 |

### 4.1 ログの期間と容量の上限

ログに関する収集すべてに、同じ期間と上限を適用します（60_logs、35_virtualization のログ、ゲストエージェントのログ）。

**期間**

- ログファイル: 更新日時（mtime）が期間内のものを、ローテーション済み（`.1`、`.2.gz`、`-YYYYMMDD`）も含めて取る。圧縮されたものは展開せずにそのままコピーする
- journal: テキスト出力に `--since` を付ける（ユニット別・優先度別・認証の出力も同じ）。バイナリの journal ファイルは更新日時で選ぶ
- `ausearch`（監査ログからの抽出）: `--start` に期間の始まりを渡す
- 期間の始まりは収集開始時に 1 度だけ決め、すべてに同じ時刻を使う。`manifest.txt` の `Log Since` に記録する

更新日時で選ぶので、期間内に更新されたファイルが期間より古い行を含むことはあります（多く取る側）。
逆に、更新日時を古く書き換えられたファイルは取りません。そのファイルは `log_inventory.tsv` に `older_than_period` として残ります。

**容量の上限**

- 上限は**ログ群ごと**（認証ログ、syslog、Web サーバー、DB 等の種類ごと）に適用する
- 群の中では、更新日時の新しいファイルから順に取る。上限を超えるファイルに当たったら、それより古いファイルは（小さくて入るものでも）取らない。取れた範囲は「直近の連続した期間」になる
- 取らなかったファイルは `log_inventory.tsv` に `over_cap` として残し、WARN を出す
- 最も新しいファイル 1 つが上限を超える場合は、その群は何も取らない（WARN と `over_cap`）。現行のログを途中で切った写しは原本と一致しないため、切らずに取らない側を選ぶ
- journal のテキスト出力は、上限 MB × 5000 件（1 件 200 バイトの目安）で抑える。超えた場合は新しい側を残し、ファイルの先頭に `# PARTIAL RESULT` と書いて WARN を出す（systemd 255 で確認。古い systemd で `--since` と `-n` を併せたときに新しい側が残るかは未確認）。`ausearch` の出力は上限 MB で切り、同じく注記と WARN を出す

上限を群ごとにした理由: 全体で 1 つの上限にすると、量が多く調査上の優先度が低い群（Web サーバーのアクセスログ等）が上限を使い切り、認証ログが取れなくなります。新しい順に並べることが意味を持つのも、同じ種類のログの中だけです。
fast モードでのログの合計は、最大で「(群の数 + journal / `ausearch` のテキスト出力の数) × 上限」です（60_logs は 15 群と 9 出力。実際には大半は小さいか存在しません）。

**群ごとの結果の読み方**（`log_summary.txt`）

| 状態 | 意味 |
|---|---|
| `collected` | 期間内のファイルを取った |
| `capped` | 上限に達した。新しいファイルは取り、残りは取っていない |
| `none_in_period` | その種類のログはあるが、期間内に更新されたものが無い |
| `not_present` | その種類のログ自体がこのホストに無い |
| `symlink_only` | シンボリックリンクだけがあった（たどらない。例: `/dev/stdout` へのリンク） |
| `copy_failed` | 選んだファイルの一部をコピーできなかった（WARN） |

## 5. 処理の流れ

1. 引数を解析し、ログの期間・上限を検証し、root 権限を確認する
2. 出力ディレクトリ `<output_directory>/<ホスト名>_<YYYYMMDD_HHMMSS>/` を権限 `700` で作る（`umask 077`）
3. 環境を検出する（ディストリビューション、init、パッケージ管理、コンテナ種別、仮想化、SELinux / AppArmor）。ユーザーのホームディレクトリの一覧を作る
4. `metadata/manifest.txt` を書き始める
5. `modules/NN_*.sh` を番号順に 1 つずつ実行する。1 つが失敗しても次へ進む
6. 統計を manifest に追記する
7. `metadata/file_hashes.txt` を生成する（これ以降、収集ディレクトリ内のファイルは変更しない）
8. `--archive` 指定時は `tar.gz` と `.sha256` を作る
9. サマリーを画面に表示する

### 5.1 収集順（揮発性の高い順）

消えやすい情報から先に取ります。ログやファイル一覧の収集には時間がかかり、その間にプロセスや接続は変化するためです。

| 順 | モジュール | 出力先 | 内容 |
|---|---|---|---|
| 1 | `10_system_info.sh` | `system/` | OS・カーネル・ハードウェア・時刻・環境変数 |
| 2 | `15_execution.sh` | `execution/` | プロセス、`/proc` 詳細、コマンド履歴 |
| 3 | `20_network.sh` | `network/` | 接続、待ち受け、経路、ARP、ファイアウォール、DNS 設定 |
| 4 | `25_kernel.sh` | `kernel/` | カーネルモジュール、eBPF、`ld.so.preload`、capabilities、sysctl |
| 5 | `30_containers.sh` | `containers/` | Docker / Podman / CRI / Kubernetes ノード |
| 6 | `35_virtualization.sh` | `virtualization/` | このホストが VM か（ゲスト側）、VM・システムコンテナを動かしているか（ホスト側） |
| 7 | `40_auth.sh` | `config/` | ユーザー、sudoers、PAM、SSH 設定 |
| 8 | `50_persistence.sh` | `persistence/` | systemd、cron、at、init、自動起動、シェル初期化ファイル |
| 9 | `60_logs.sh` | `logs/` | journal、syslog、認証ログ、auditd、ログイン履歴、各種アプリログ |
| 10 | `70_filesystem.sh` | `filesystem/` | マウント、最近の変更、SUID/SGID、未パッケージのバイナリ |
| 11 | `80_web.sh` | `web/` | ブラウザの履歴・Cookie 等（fast では無効） |
| 12 | `90_custom_environment.sh` | `custom_environment/` | init / パッケージ管理 / SELinux / AppArmor の詳細 |
| 13 | `91_cloud_metadata.sh` | `cloud_metadata/` | AWS / Azure / GCP / OCI / DigitalOcean / Alibaba |

## 6. 出力仕様

### 6.1 ディレクトリ構成

```
<output_directory>/
├── <ホスト名>_<YYYYMMDD_HHMMSS>/          収集ディレクトリ（権限 700）
│   ├── system/
│   ├── execution/
│   ├── network/
│   ├── kernel/
│   ├── containers/
│   ├── virtualization/
│   ├── config/
│   ├── persistence/
│   ├── logs/
│   ├── filesystem/
│   ├── web/
│   ├── custom_environment/
│   ├── cloud_metadata/
│   └── metadata/
│       ├── manifest.txt                  環境の要約とモジュールごとの結果
│       ├── collection.log                実行ログ
│       ├── modules/<モジュール名>.log     モジュール別ログ
│       └── file_hashes.txt               全ファイルの SHA256
├── <ホスト名>_<YYYYMMDD_HHMMSS>.tar.gz     --archive 指定時
└── <ホスト名>_<YYYYMMDD_HHMMSS>.tar.gz.sha256
```

ホスト名に含まれる英数字・`.`・`_`・`-` 以外の文字は `_` に置き換えます。

収集物の中で共通に使う名前:

| ファイル | 意味 |
|---|---|
| `_symlinks.txt` | 単体のファイルがシンボリックリンクだった場合の記録（リンク先の内容をコピーした旨、または宙に浮いたリンク）。例: `/etc/resolv.conf -> ../run/systemd/resolve/stub-resolv.conf` |
| `excluded_files.txt` | 秘密鍵・認証情報として**コピーしなかった**ファイルと、たどらなかったシンボリックリンクの一覧（パスのみ） |
| `log_summary.txt` `log_inventory.tsv` | ログ群ごとの結果と、ファイルごとの判定（4.1 節） |
| `# PARTIAL RESULT` で始まる行 | 時間や容量の上限で打ち切られた出力。短い・空の内容を「該当なし」と読まないこと |

### 6.2 manifest.txt

| セクション | 内容 |
|---|---|
| ヘッダ | ツールのバージョン、モード、マスクの有無、ログの期間（`Log Days` `Log Since`）と上限（`Log Size Cap`）、収集時刻（ローカルと UTC）、ホスト名 |
| System Information | ディストリビューション、カーネル、アーキテクチャ、init、パッケージ管理、コンテナ種別、仮想化（`Virtualization`）、SELinux、AppArmor |
| Collection Modules | モジュールごとに 1 行 |
| Collection Statistics | ファイル数、容量、成功 / 失敗モジュール数、所要秒数、終了時刻 |

```
Log Days: 30
Log Since: 2026-10-14 10:15:00
Log Size Cap: 100 MB per log group
...
Virtualization: kvm (systemd-detect-virt)
```

`Log Days` は `30` `60` `90`、または `unlimited`（full モードで `--log-days` を指定しない場合）。
`Virtualization` は種別と判定の根拠です。種別は `systemd-detect-virt --vm` の語（`kvm` `vmware` `microsoft` `oracle` `xen` `amazon` 等）、`none`（VM でない）、`vm-unknown-hypervisor`（CPU の hypervisor フラグだけが根拠）、`unknown`（判定材料が無い）。

モジュール行の形式:

```
✓ 25_kernel.sh (warn=0, error=0, 2s)
✗ 60_logs.sh (exit=1, warn=1, error=1, 0s)
```

### 6.3 ログのレベル

| レベル | 意味 | 画面 | manifest の件数 |
|---|---|---|---|
| `INFO` / `SUCCESS` | 進行状況 | 出る | 数えない |
| `DEBUG` | 想定内の事象。対象ファイルがそのホストに存在しない等 | `LDIR_VERBOSE=1` のときだけ | 数えない |
| `WARN` | 取れるはずのものが取れなかった、または調査上の注意点 | 出る | `warn=` |
| `ERROR` | モジュールが続行できなかった | 出る | `error=` |

`WARN` には「失敗」のほか「調査担当者に見てほしい所見」も含みます。現在の所見は次のとおりです。

- `/etc/ld.so.preload` が存在する
- `ps` が BusyBox 等で、プロセス情報の一部が取れない
- fast モードの権限検索、`/etc` の検索、VM ごとの問い合わせが時間の上限に達し、結果が部分的である
- ログが容量の上限に達し、一部を取っていない（`over_cap`）。journal / `ausearch` の出力が上限で切れた
- `/proc/modules` と `/sys/module` のモジュール一覧が食い違う
- libvirt にも Proxmox VE にも管理されていない QEMU のプロセスが動いている（管理ツールの外で手動で起動された VM）

コンテナ内では、カーネルやファイアウォールの状態を読むコマンド（`dmesg` `iptables` `nft` `bpftool` 等）の失敗は WARN ではなく DEBUG にします（権限が無いのが普通のため）。出力ファイルには失敗の理由を残します。

### 6.4 file_hashes.txt と検証

- 形式は `sha256sum` の出力。パスは収集ディレクトリからの**相対パス**で、ソート済み
- 対象は `file_hashes.txt` 自身を除く全ファイル
- 収集ディレクトリを別のホスト・別のパスへ移しても検証できる

```bash
cd <ホスト名>_<YYYYMMDD_HHMMSS>
sha256sum -c metadata/file_hashes.txt | grep -v ': OK$'    # 不一致だけ表示。何も出なければ正常
```

`file_hashes.txt` 自身の SHA256 は、実行終了時に画面へ `Hash list SHA256:` として表示します。
この 1 行を記録しておけば、収集物全体が後から変更されていないことを示せます。

## 7. モジュール別の収集内容

主なものを挙げます。対象がホストに無い場合、その項目は出力されません。

**ユーザーごとの収集**（コマンド履歴、SSH、crontab 以外のユーザー単位の永続化、ブラウザ、`~/.config`）は、passwd（`getent passwd`、無ければ `/etc/passwd`）のホームディレクトリのうち実在するものと、`/root` `/home/*` のうちどの passwd 項目からも参照されていないもの（`orphan-home_<名前>`）を対象にします。
同じホームを共有するユーザーは 1 度だけ調べます。調べたホームの一覧は `config/user_homes.tsv` です。

### 7.1 `system/`

`uname.txt` `hostname.txt` `collection_time.txt` `uptime.txt` `os-release` `kernel_version.txt` `kernel_cmdline.txt`
`cpu_info.txt` `memory_info.txt` `disk_usage.txt` `block_devices.txt` `ip_addresses.txt` `routing_table.txt` `timezone.txt`
`environment_variables.txt`（収集プロセス自身の環境変数。秘匿値はマスク）

### 7.2 `execution/`

| ファイル | 内容 |
|---|---|
| `running_processes.txt` `running_processes_tree.txt` `process_start_times.txt` | `ps` の各形式 |
| `ps_limited.txt` | `ps` が procps でない場合（BusyBox 等）のみ。取れない列と読み替え方の説明。この場合ツリー表示とスケジューリング情報は出力されず、開始時刻は経過時間（etime）のみになる |
| `process_tree.txt` `top_snapshot.txt` | `pstree`、`top` の 1 回分 |
| `proc_details/<PID>/` | `cmdline.txt` `exe.txt` `cwd.txt` `status.txt`。full では `environ.txt`（マスク対象）`open_files.txt` も |
| `bash_history_<ユーザー>` `zsh_history_<ユーザー>` | bash / zsh の履歴（更新日時を保つ） |
| `user_history/<ユーザー>/` | その他の履歴: ash / sh / ksh / fish、`.python_history` `.mysql_history` `.psql_history` `.sqlite_history` `.rediscli_history` `.node_repl_history` `.irb_history` `.dbshell`、`.lesshst` `.viminfo` `.wget-hsts` |
| `recently_used_<ユーザー>.xbel` | デスクトップの最近使ったファイル |
| `running_services.txt` `lsof_all.txt` `lsof_network.txt` | 稼働サービス、オープンファイル |

`exe.txt` が `(deleted)` で終わるプロセスは、実行ファイルが削除済みであることを示します。
auditd のログと `ausearch` の抽出は 0.4.0 で `logs/` に移りました（7.9 節）。

### 7.3 `network/`

`ss_listening.txt` `ss_established.txt` `ss_all.txt` `netstat_*.txt` `arp_cache.txt` `ip_routes.txt` `ip_addresses.txt`
`iptables_*.txt` `nftables_ruleset.txt` `ufw_status.txt` `firewalld_config.txt`
`resolv.conf` `hosts` `hosts.allow` `hosts.deny` `nsswitch.conf` `tcp` `udp`（`/proc/net` の写し）`NetworkManager/` `systemd-network/`

### 7.4 `kernel/`

| ファイル | 内容 | 見るべき点 |
|---|---|---|
| `proc_modules.txt` `lsmod.txt` | ロード済みモジュール | 見覚えのない名前 |
| `sys_module_details.tsv` | モジュールごとの taint と srcversion | taint に `O`（ツリー外）`E`（署名なし） |
| `modules_in_sysfs_not_in_proc.txt` `modules_in_proc_not_in_sysfs.txt` | 2 つの一覧の差分 | **空でなければ要調査** |
| `tainted.txt` | カーネル全体の taint 値 | `0` 以外 |
| `out_of_tree_modules.txt` | `extra/` `updates/` `dkms/` 配下のモジュールファイル | 導入した覚えのないもの |
| `etc_modules` `modules-load.d/` `modprobe.d/` | 起動時ロードの設定 | 永続化 |
| `ld.so.preload` または `ld.so.preload.absent.txt` | 動的リンカへの差し込み | **存在すれば要調査**（通常は無い） |
| `ld.so.conf` `ld.so.conf.d/` | ライブラリ検索パス | 一時ディレクトリ等の追加 |
| `bpf_progs.txt` `bpf_maps.txt` `bpf_links.txt` `bpf_net.txt` `bpf_cgroup_tree.txt` | eBPF（`bpftool` が必要） | 由来不明のプログラム |
| `bpf_pinned.txt` `bpf_fds.txt` | pin された BPF、BPF の fd を持つプロセス | `bpftool` が無い場合の手がかり |
| `file_capabilities.txt` | capabilities を持つファイル（`getcap` が必要） | `cap_setuid` `cap_sys_admin` `cap_dac_override` 等 |
| `security_sysctls.txt` `sysctl_all.txt` | カーネル設定 | `core_pattern` や `modprobe` の書き換え |
| `lsm.txt` `lockdown.txt` `secure_boot.txt` `dmesg.txt` | LSM、lockdown、Secure Boot、カーネルログ | |

隠しモジュールの照合は簡易的なものです。両方の一覧から自身を消す rootkit は検出できません。空であることは安全の証明になりません。

### 7.5 `containers/`

このホストが**アプリケーションコンテナを動かす側**である場合の情報です。ランタイムが見つからなければ `no_container_runtime.txt` だけを残します。
LXC / LXD / Incus / Proxmox VE のコンテナは `virtualization/` が扱います（7.6 節）。

| パス | 内容 |
|---|---|
| `docker/` `podman/` | `version.txt` `info.txt` `ps_all.txt` `images.txt` `networks.txt` `volumes.txt` `network_inspect.json` |
| `<cli>/inspect/<ID>.json` | コンテナの詳細。`Env` の秘匿値はマスク。取得に失敗した場合は `.json` を作らず `<ID>.inspect_failed.txt` を残す |
| `<cli>/inspect/<ID>.diff.txt` | イメージからのファイル変更点 |
| `<cli>/risk_summary.tsv` | 特権・PID / ネットワーク名前空間の共有・追加 capabilities・ホストのマウントを 1 行にまとめたもの |
| `<cli>/inspect/<ID>.top.txt` `<ID>.logs_tail.txt` | full のみ。プロセスとログ末尾 1000 行 |
| `config/` | `daemon.json`、`/etc/containers/`（`auth.json` を除く）、containerd・CRI-O の設定 |
| `config/user_credential_files_present.txt` | `~/.docker/config.json` `~/.kube/config` の**存在のみ** |
| `privileged_groups.txt` `runtime_sockets.txt` | `docker` `podman` グループの所属、ソケットの権限 |
| `cri/` | `crictl pods` / `ps -a` / `images`、`ctr namespaces list` |
| `kubernetes/static_pod_manifests/` | `/etc/kubernetes/manifests/` の写し |
| `kubernetes/kubelet_config.yaml` `kubelet_pods.txt` `kubelet_journal_tail.txt` `pki_certs/` | kubelet 設定、Pod 一覧、ログ末尾、証明書（`.crt` のみ） |
| `container_related_processes.txt` | ランタイム関連プロセス |

デーモンが応答しない場合は `info.txt` に結果を残し、それ以降の問い合わせを省略します。
`inspect` `diff` `logs` の失敗は、コンテナごとではなく種類ごとに 1 件の WARN にまとめます。

### 7.6 `virtualization/`

**ゲスト側**（このホスト自身が VM か）

| パス | 内容 |
|---|---|
| `guest/virt_detection.txt` | 判定結果と根拠: `systemd-detect-virt`、DMI（`/sys/class/dmi/id` の製品名・ベンダー・シリアル・UUID）、`/proc/cpuinfo` の hypervisor フラグ、`/sys/hypervisor`、`/proc/xen`、`virt-what`（あれば） |
| `guest/guest_agents.tsv` | ゲストエージェント・クラウドエージェントの有無と稼働状況: qemu-guest-agent、open-vm-tools、VirtualBox Guest Additions、Hyper-V daemons、xe-guest-utilities、Parallels Tools、spice-vdagent、amazon-ssm-agent、google-guest-agent、Azure Linux Agent。それぞれが「外からこのゲストでコマンドを実行する経路」になり得るかを併記 |
| `guest/agent_config/` | エージェントの設定（どの操作を許しているか。秘匿値はマスク） |
| `guest/agent_logs/` | エージェントのログ（4.1 節の期間と上限） |
| `virt_kernel_modules.txt` | 仮想化に関係するロード済みモジュール（virtio、vmw_*、hv_*、kvm、vhost、vfio 等） |

判定の順序: `systemd-detect-virt --vm` → DMI → `/sys/hypervisor/type` → CPU の hypervisor フラグ。どれも無い環境でも止まらず `unknown` を記録します。結果は `manifest.txt` の `Virtualization` にも入ります。

**ホスト側**（このホストが VM・システムコンテナを動かしているか）

| パス | 内容 |
|---|---|
| `hypervisor_processes.tsv` | 稼働中の QEMU / KVM、VirtualBox、VMware、Firecracker、Cloud Hypervisor、crosvm、Xen、libvirt・Proxmox・LXD・Incus・LXC のデーモンのプロセス（PID、UID、コマンドライン） |
| `kvm_device.txt` | `/dev/kvm` の有無と nested の設定（KVM を**使える**ことを示すだけで、VM を動かしている根拠にはしない） |
| `privileged_groups.txt` | `libvirt` `kvm` `lxd` `incus` `vboxusers` 等のグループの所属（`libvirt` `lxd` `incus` は実質 root） |
| `host/libvirt/` | `virsh` の `version` `uri` `nodeinfo`、VM（`list --all`）、ネットワーク、ストレージプール、`secret-list`（UUID と用途のみ）。VM ごとに `domains/<UUID>/`（`dominfo` `domain.xml` `domblklist` `domiflist`、スナップショットの一覧と定義）。ネットワークごとの定義と DHCP リース、プールごとの定義とボリューム一覧。`/etc/libvirt` の写し、`disk_images.txt`（ディスクイメージのパス・存在・サイズ）、`image_and_state_files.txt`（イメージ・保存状態・NVRAM の置き場の一覧）、`logs/`（`/var/log/libvirt`。4.1 節） |
| `host/proxmox/` | `pveversion -v`、`qm list`、`pct list`、`pvesm status`、`pvecm status`、`/etc/pve` の写し（VM・コンテナの定義、スナップショット、ストレージ・ユーザー・ファイアウォールの設定）、`image_and_backup_files.txt`、`tasks/`（タスクログ）、`pveproxy/`（Web UI / API のアクセスログ） |
| `host/lxc/` | `lxc-ls --fancy`、`/etc/lxc` の写し、コンテナごとの `config`、`/var/lib/lxc` の一覧 |
| `host/lxd/` `host/incus/` | API（UNIX ソケット）から直接読んだ JSON: サーバー情報、インスタンス（全プロジェクト）、プロファイル、ネットワーク、ストレージプール、**信頼されたクライアント証明書**、プロジェクト。ログ（4.1 節） |
| `host/virtualbox/` | `VBoxManage list vms` / `runningvms`、VM ごとの `showvminfo`。ユーザーごとの VM 登録（`VirtualBox.xml`）と `VirtualBox VMs` の一覧 |
| `host/xen/` | dom0 の場合のみ: `xl info` `xl list` `xl list -l`、`/etc/xen` の写し、ログ |
| `no_hypervisor_detected.txt` | ホスト側で何も見つからなかった場合のみ。調べた対象の一覧 |
| `scan_incomplete.txt` | VM ごとの問い合わせが時間の上限（`LDIR_VIRT_BUDGET`）で打ち切られた場合のみ |

方針:

- 管理コマンド（`virsh` `qm` `pct` `pvesm` `xl` `VBoxManage` `curl`）はすべて `LDIR_VIRT_TIMEOUT` 秒で区切る。デーモンが応答しない場合は WARN を出し、以降の問い合わせを省く
- libvirt のソケットが無ければ `virsh` は使わない（クライアントだけが入っているホスト）
- `/etc/pve` は FUSE（pmxcfs）なので、10 秒以内に応答しなければコピーしない（WARN）
- VM のディスクイメージ、メモリのスナップショット、保存状態（`*.save`）の中身は取らない。パス・存在・サイズのみ
- ゲストの中のログは取らない。ゲストごとに本ツールを実行する
- LXD / Incus は `lxc` / `incus` クライアントを使わない（root で初めて動かすと設定ディレクトリを作るため）。API を `curl --unix-socket` で読む
- `VBoxManage` は root に VirtualBox の設定が既にある場合だけ使う（無い場合に動かすと設定ファイルを作り、VBoxSVC を起動するため）。ユーザーごとの VM は登録ファイルから読む
- QEMU のプロセスのコマンドラインに libvirt / Proxmox の管理下のパスが無い場合、手動で起動された VM として WARN を出す
- ESXi は対象外（bash が前提のため）

### 7.7 `config/`

`passwd` `shadow` `group` `gshadow` `getent_passwd.txt` `getent_group.txt`（LDAP / SSSD 等を含む NSS 経由の一覧）`user_homes.tsv`
`sudoers` `sudoers.d/` `sudo.conf` `doas.conf` `pam.d/` `security/`
`ssh/`（`/etc/ssh` の写し。`sshd_config.d/` を含み、秘密鍵を除く）`sshd_effective_config.txt`（`sshd -T` の出力。Include を反映した実効値）
`user_ssh/<ユーザー>/`（`authorized_keys` `authorized_keys2` `known_hosts` `config` `rc` `environment`、`ssh_dir_listing.txt`、`AuthorizedKeysFile` が既定以外を指す場合はその鍵ファイル `authorized_keys_file__<パス>`）
`who_all.txt` `last_full.txt` `excluded_files.txt`

`AuthorizedKeysFile` は `sshd -T` から読みます（`%h` `%u` `%%` `~` を展開し、相対パスはホームからの相対）。`sshd -T` が使えない・失敗した場合（ソケット起動で `/run/sshd` が無い等）は設定ファイルを直接読み、その旨を `sshd_effective_config.txt` の末尾に書きます（WARN にはしない）。

### 7.8 `persistence/`

`systemd_unit_files.txt` `systemd_units_all.txt` `systemd_timers.txt`
`systemd_system/`（`/etc/systemd/system`）`systemd_usr_lib/` `systemd_lib/` `systemd_usr_local_lib/`（`/usr/local/lib/systemd/system`）
`systemd_transient/`（`systemd-run` で作られた一時的なユニット）`systemd_run_system/` `systemd_etc_user/` `systemd_user_<ユーザー>/`
`generators_*/`（`/etc` と `/usr/local` の generator）`systemd_generators_listing.txt`（パッケージ由来の generator の一覧）
`init.d/` `rc.local` `crontab` `anacrontab` `cron.allow` `cron.deny` `cron.d/` `cron.daily/` ほか `user_crontabs/` `user_crontab_l/<ユーザー>.txt` `at_jobs/`
`autostart_system/` `autostart_user_<ユーザー>/` `ld_preload_references.txt`
`shell_init/<ユーザー>/`（`.bashrc` `.bash_profile` `.bash_login` `.bash_logout` `.profile` `.zshrc` `.zshenv` `.zprofile` `.zlogin` `.cshrc` fish の `config.fish`、`.xprofile` `.xinitrc` `.xsession` `.pam_environment` 等）
`profile` `profile.d/` `bash.bashrc` `bashrc`（RHEL 系）`zshrc` `zsh/` `csh.cshrc` `environment`

### 7.9 `logs/`

期間と容量の上限は 4.1 節。結果は `log_summary.txt`（群ごと）と `log_inventory.tsv`（ファイルごと）。

| ログ群 | 対象（`/var/log` からの相対。ローテーション分を含む） | 出力先 |
|---|---|---|
| `journal` `journal_runtime` | `journal/`（永続）、`/run/log/journal/`（揮発）のバイナリ | `journal/` `run_log/journal/` |
| `auth` | `auth.log*` `secure*` | 元の名前のまま |
| `syslog` | `syslog*` `messages*` | 〃 |
| `kern` | `kern.log*` | 〃 |
| `cron` | `cron` `cron.*` `cron-*`（RHEL 系） | 〃 |
| `boot` | `boot.log*` `dmesg*` | 〃 |
| `audit` | `audit/audit.log*` | `audit/` |
| `login` | `wtmp*` `btmp*` | 元の名前のまま |
| `packages` | `apt/history.log*` `apt/term.log*` `dpkg.log*` `yum.log*` `dnf.log*` `dnf.rpm.log*` `pacman.log*` `zypp/history*` `apk.log*` `emerge.log*` | 〃 |
| `web` | `apache2/` `httpd/` `nginx/` `lighttpd/` | 同名のディレクトリ |
| `db` | `mysql/` `mysqld.log*` `mariadb/` `postgresql/` `mongodb/` `redis/` | 〃 |
| `db_pgsql` | `/var/lib/pgsql/data/log` 等（RHEL 系の PostgreSQL） | `pgsql/` |
| `mail` | `mail.log*` `mail.err*` `mail.warn*` `mail.info*` `maillog*` | 元の名前のまま |
| `firewall` | `ufw.log*` `firewalld*` | 〃 |

journal のテキスト出力（4.1 節の期間と件数の上限）:

| ファイル | 内容 |
|---|---|
| `journal_tail.txt` | 末尾 1000 行（解説付き） |
| `journal_period.txt` | 期間内の全体（0.3.2 までの `journal_7days.txt`）。期間なし（full）の場合は `journal_full.txt` |
| `journal_auth.txt` | 認証（syslog facility の auth / authpriv）。rsyslog の無いホストでは認証の記録はここにしかない |
| `journal_errors.txt` | 優先度 err 以上 |
| `journal_ssh.txt` `journal_sshd.txt` `journal_cron.txt` | ユニット別（`journal_cron.txt` は `cron` と `crond`） |

その他:

| ファイル | 内容 |
|---|---|
| `audit_execve.txt` `audit_user_cmd.txt` `audit_recent.txt` | `ausearch` による抽出（期間内。0.3.2 までは `execution/`） |
| `lastlog` `faillog` | データベース形式のファイル（期間・上限の対象外） |
| `last_logins.txt` `failed_logins.txt` `lastlog.txt` `current_users*.txt` | テキスト形式のログイン記録（現行の wtmp / btmp のみ） |
| `var_log_listing.txt` | `/var/log` の 3 階層までの一覧。上の群に入らないアプリケーションのログは取らないが、何があったかはここで分かる |

### 7.10 `filesystem/`

| ファイル | 内容 |
|---|---|
| `mount_points.txt` `proc_mounts.txt` `fstab.txt` `disk_usage_human.txt` | マウントと容量 |
| `modified_last_7days.txt` | 7 日以内に変更されたファイル（ログの期間とは独立） |
| `tmp_files.txt` `var_tmp_files.txt` `hidden_files_sensitive.txt` `dev_shm_contents.txt` | 一時領域の内容 |
| `suid_sgid_files.txt` `world_writable_files.txt` | 権限の観点。fast では `/tmp` `/var/tmp` `/dev/shm` `/etc` `/usr/bin` `/usr/sbin` `/bin` `/sbin`（`/usr` へのリンクでない場合）`/usr/libexec` `/usr/local` `/opt` の順に、合計 60 秒まで |
| `scan_incomplete.txt` | 上の検索が時間の上限で打ち切られた場合のみ。見られなかった場所の一覧。このとき 2 つの一覧の先頭にも `# PARTIAL RESULT` の注記が入る（空の一覧を「該当なし」と読み違えないため） |
| `unpackaged_binaries_dpkg.txt` / `_rpm.txt` | パッケージに属さない `/usr/bin` `/usr/sbin` `/usr/local/bin` `/usr/local/sbin` のファイル |
| `deleted_open_files.txt` | 削除済みだが開かれたままのファイル |
| `system_binaries_hashes.txt` | full のみ |
| `etc_file_list.txt` `directory_tree.txt` | 一覧 |

`unpackaged_binaries_*.txt` は**確認対象の候補**です。`update-alternatives` のリンクや手動導入したツールも載ります。
収集ディレクトリ自身は、すべての探索から除外します。

### 7.11 `web/` `custom_environment/` `cloud_metadata/`

- `web/`: Firefox / Chrome / Chromium / Brave / Edge / Opera の履歴・Cookie・ログインデータ（暗号化されたまま）。無効時は `disabled.txt` のみ
- `custom_environment/`: init 別のサービス一覧、パッケージ一覧、SELinux / AppArmor の状態、`/opt/*/conf` 等の設定、`~/.config` の一覧。パッケージ管理のログは 0.4.0 から `logs/` のみ
- `cloud_metadata/`: インスタンス ID、種別、リージョン、ネットワーク、IAM ロール名、user-data。無効時は `disabled.txt`、検出なしは `no_cloud.txt`

## 8. 秘匿情報の扱い

収集物は調査担当者や外部へ渡ります。次の方針で扱います。迷う場合は伏せる側に倒します（伏せすぎは `--no-redact` で取り戻せるが、漏れは取り戻せない）。

### 8.1 既定でマスクするもの

**環境変数**: 名前が秘匿情報らしい変数の**値**。名前は残し、値は文字数だけ残します。

```
GH_TOKEN=<redacted:40 chars>
HTTPS_PROXY=http://user:<redacted>@proxy:3128/
```

| 対象 | 出力先 |
|---|---|
| 収集プロセス自身の環境変数 | `system/environment_variables.txt` |
| 各プロセスの環境変数（full） | `execution/proc_details/<PID>/environ.txt` |
| コンテナ内 PID 1 の環境変数 | `custom_environment/container/docker_env.txt` |
| コンテナ定義の `Env` | `containers/<cli>/inspect/<ID>.json` |

判定に使う名前（大文字小文字は区別しない。複数形 `TOKENS` `SECRETS` も含む）: `TOKEN` `SECRET` `PASSW` `CREDENTIAL` `API_KEY` `ACCESS_KEY` `PRIVATE_KEY` `COOKIE` `BEARER` `JWT` `SIGNATURE` `AUTHORIZATION` を含むもの、`_KEY` `_PWD` `_AUTH` で終わるもの。
あわせて、値に含まれる URL の `ユーザー:パスワード@` 部分。

`MAX_TOKENS` のように秘匿値でない変数も、名前が一致すれば伏せます。

**VM 定義・ハイパーバイザの設定**（0.4.0）: 上と同じ名前の規則に、`user-data` `vendor-data`（cloud-init）と `environment.*`（LXD / Incus のコンテナに渡す環境変数）を加えて、次の形の値を伏せます。

| 形式 | 例 | 結果 |
|---|---|---|
| `key = value` / `key=value` / `key: value`（行頭の `#` `;` を含む） | `vnc_password = "x"`、`cipassword: $5$...` | `vnc_password = <redacted:3 chars>` |
| YAML のブロック（`key: \|` の後の字下げされた行） | `user.user-data: \|` 以下 | ブロック全体を `<redacted>` |
| JSON の文字列 | `"cloud-init.user-data":"#cloud-config..."` | `"cloud-init.user-data":"<redacted:N chars>"` |
| XML の属性・要素 | `<graphics passwd='x'/>`、`<password>x</password>` | 値を `<redacted:N chars>` |
| QEMU の secret オブジェクト | `secret,id=s0,data=...` | `data=<redacted>` |
| URL の認証情報 | `rbd://admin:pw@mon/` | `rbd://admin:<redacted>@mon/` |

項目ごとの扱い（仮想化）:

| 項目 | 扱い | 理由 |
|---|---|---|
| VNC / SPICE のパスワード（libvirt の `passwd=`、`qemu.conf` の `*_password`、Xen の `vncpasswd`） | **伏せる** | VM のコンソールへの直接のアクセス手段 |
| cloud-init の user-data / vendor-data（LXD / Incus の `cloud-init.*` `user.user-data`） | **伏せる** | 初期パスワードやトークンが平文で書かれることが多い。調査に要る場合は `--no-redact` |
| Proxmox の `cipassword`（cloud-init のパスワードハッシュ） | **伏せる** | `/etc/shadow` と異なり、侵害の調査に要ることが少ない |
| LXD / Incus の `environment.*` | **伏せる** | コンテナに渡す環境変数（トークンが入りやすい） |
| QEMU の `-object secret,data=` | **伏せる** | 鍵の値そのもの |
| ディスク暗号化・Ceph 等の鍵への**参照**（`<secret uuid=...>`、`secret-list` の UUID と用途） | そのまま含む | 値ではなく参照。どの鍵がどこで使われているかは調査に要る |
| `sshkeys:`（Proxmox）、`ssh_authorized_keys` の**公開鍵** | そのまま含む | 公開情報。追加された鍵は侵害の痕跡 |
| LXD / Incus の信頼済み証明書 | そのまま含む | 公開証明書。遠隔操作できる相手の一覧として要る |
| QEMU / libvirt のログ、稼働中の QEMU のコマンドライン | そのまま含む | 各種ログ・プロセスのコマンドラインと同じ扱い（8.3 節） |
| `qm:args` 等、自由形式の引数に書かれた値 | **伏せられない** | 名前で判定できない |

### 8.2 収集しないもの

ファイル単位で収集しません。コピーした後に消すのではなく、**出力先に一度も書きません**（消した鍵が出力先の媒体に残るため）。除外したファイルのパスは各モジュールの `excluded_files.txt` に残します。

- 中身に `-----BEGIN ... PRIVATE KEY-----` または PuTTY の鍵形式を含むファイル（`/etc/ssh`、`/etc/containers`、`/etc/libvirt`、`/etc/pve`、`/etc/lxc`、`/etc/xen`、エージェントの設定）。名前に依らない（`HostKey` で別名を付けたホスト鍵も含む）
- 名前で判定するもの: `secrets/` `priv/` の配下、`*.key` `*.pw` `*.keyring` `*.p12` `*.pfx` `*.jks` `*.base64` `authkey` `auth.json` `ssh_host_*_key` `master-key.aes`
- 具体的には: `/etc/libvirt/secrets/`（libvirt の鍵の値）、`/etc/pve/priv/`（Proxmox のクラスタ鍵、パスワードハッシュ、API トークン、ストレージのパスワード）、`/etc/pve/**/*.key`（Web UI の TLS 秘密鍵）、`/etc/containers/auth.json`
- ユーザーの SSH 秘密鍵（`~/.ssh` は公開鍵と設定の決まった名前だけをコピーする。ファイル名の一覧は残る）
- `~/.docker/config.json`、`~/.kube/config`（存在のみ記録）
- Kubernetes の秘密鍵と kubeconfig（`/etc/kubernetes/pki/*.key`、`/etc/kubernetes/*.conf`）
- `virsh secret-get-value` は実行しない。`/var/lib/libvirt/qemu/domain-*/master-key.aes` はコピー対象の範囲外
- VM のディスクイメージ、メモリの保存状態の中身

### 8.3 マスクされずに含まれるもの

収集物そのものが機微情報です。次のものは調査に必要なため、そのまま含みます。

- `/etc/shadow`、`/etc/gshadow`（パスワードハッシュ）
- コマンド履歴（コマンドラインに書かれたパスワードを含み得る。`.mysql_history` `.psql_history` は SQL の `IDENTIFIED BY` 等を含み得る）
- 各種ログ、プロセスのコマンドライン（libvirt / QEMU のログと QEMU のコマンドラインを含む）
- full / Web 有効時: ブラウザの履歴・Cookie、`~/.config` 全体
- クラウドの user-data（起動スクリプトに認証情報が書かれていることがある）

収集ディレクトリは権限 `700` で作りますが、**保管と受け渡しの管理は利用者の責任**です。

## 9. 構成と拡張

```
ldir-toolkit/
├── ldir-collect.sh              本体
├── lib/
│   ├── common.sh                ログ、コピー、マスク、ログの期間と上限等の共通関数
│   └── detect_distro_advanced.sh  環境検出（仮想化の判定を含む）
└── modules/NN_<名前>.sh          収集モジュール
```

### 9.1 モジュールの規約

- ファイル名は `NN_<名前>.sh`。`NN` の昇順に実行される。**番号は揮発性の順を表す**ので、追加時は適切な位置の番号を選ぶ
- 第 1 引数で収集ディレクトリを受け取り、`<収集ディレクトリ>/<名前>/` に出力する
- `lib/common.sh` を `source` する
- 対象が無いことは失敗ではない。`exit 0` で終える。続行できない場合のみ非 0
- `modules/` に置けば自動で実行対象になる。本体の編集は不要
- 仕様書（本書 5.1 節）に 1 行追加する。単体テストがこれを確認する
- ユーザーごとの収集は `ldir_user_homes` を使う（`/root /home/*` を直接回さない）
- ログを取る場合は `collect_log_group` を使う（期間と上限、結果の記録が揃う）
- 時間が対象のサイズに比例する処理には上限を付け、打ち切った結果は WARN と収集物の中の注記で示す

### 9.2 共通関数

| 関数 | 用途 |
|---|---|
| `log_info` `log_warn` `log_error` `log_success` `log_debug` | ログ出力（6.3 節） |
| `safe_copy <src> <dst>` | 属性を保ったコピー。対象が無ければ DEBUG を残して戻る。単体のシンボリックリンクはリンク先の内容をコピーし、`_symlinks.txt` に記録する |
| `capture <file> <cmd> [引数...]` | コマンド出力を保存。非 0 終了は WARN（`run_limited` の打ち切りは「timed out」と書く）、コマンドが無ければファイルにその旨を記録。**モジュールでは `cmd > file 2>&1` を直接書かず、これを使う** |
| `capture_try <file> <cmd> [引数...]` | 同上だが失敗しても WARN を出さない。`capture_try f A \|\| capture f B` のように代替がある場合や、終了コードを呼び出し側で判断する場合に使う |
| `capture_partial <file> <cmd> [引数...]` | 一部が読めなくても出力を続けるコマンド用（`sysctl -a`、`ls -R`）。出力があれば DEBUG、出力が空なら WARN |
| `capture_host <file> <cmd> [引数...]` | カーネル・ネットワークの状態を読むコマンド用。ホストでは `capture` と同じ、コンテナ内では失敗を DEBUG にして理由をファイルに残す |
| `mark_partial <file> <説明>...` | 打ち切られた出力の先頭に `# PARTIAL RESULT:` の注記を入れる |
| `save_command_output <cmd> <file>` | パイプを含むコマンド文字列を保存。失敗は WARN |
| `redact_env` | 標準入力の `NAME=VALUE` 行から秘匿値を伏せるフィルタ |
| `redact_config` `ldir_json_split` | 設定ファイル・VM 定義・JSON の秘匿値を伏せるフィルタ（8.1 節）。1 行の JSON は `ldir_json_split` で項目ごとに分けてから通す |
| `copy_config_tree <src> <dst> <記録> [redact]` | ディレクトリのコピー。秘密鍵・認証情報（8.2 節）は書かずに記録し、シンボリックリンクはたどらずに記録する。`redact=1` で `redact_config` を通す |
| `copy_config_file <src> <dst> <記録>` | 1 ファイルを `redact_config` を通してコピーする（秘密鍵なら書かずに記録） |
| `ldir_user_homes` | ユーザーとホームの一覧（`ラベル<TAB>ホーム<TAB>由来`）。7 章冒頭の規則 |
| `collect_log_group <群> <基点> <コピー先> <記録先> <パターン>...` | ログファイルを期間と上限に従って集め、`log_summary.txt` と `log_inventory.tsv` に記録する（4.1 節） |
| `ldir_resolve_log_settings` | `--log-days` / `--log-max-mb` の検証と、期間の始まりの計算 |
| `run_limited <秒> <cmd...>` | 時間制限付きで実行。打ち切りは終了コード 124（BusyBox の `timeout` の 143 も 124 に揃える）。`0` 秒は制限なし |
| `have_cmd <名前>` | コマンドの有無 |
| `ensure_dir <dir>` | ディレクトリ作成 |
| `"${LDIR_FIND_PRUNE[@]}"` | `find` から収集ディレクトリを除外する指定 |
| `"${LDIR_FIND_LS[@]}"` | `find -ls` 相当（BusyBox では `ls -ld` に切り替わる） |

`safe_copy` のコピー先は rsync と同じ規則です。

| 呼び出し | 結果 |
|---|---|
| `safe_copy /etc/passwd DST/` | `DST/passwd` |
| `safe_copy /etc/passwd DST/pw` | `DST/pw` |
| `safe_copy /etc/pam.d/ DST/pam.d/` | `DST/pam.d/<中身>`（コピー元の末尾 `/` は「中身」の意味） |
| `safe_copy /etc/s6 DST/` | `DST/s6/<中身>` |

モジュールの中で、失敗を記録しないのが正しい直書きの `> file 2>&1`（収集中に終了し得るプロセスの `/proc` の読み取り等）には、行末に `# ldir:allow` を付けて理由をコメントします。単体テストはそれ以外の直書きを拒否します。

### 9.3 テスト

| コマンド | 内容 | root |
|---|---|---|
| `make lint` | shellcheck | 不要 |
| `make test` | 共通関数、環境検出、仮想化の判定、引数、マスク規則、ログの期間と上限、仮想化モジュール（モック）の単体テスト | 不要 |
| `sudo make smoke` | 実際に収集し、manifest・ハッシュ・アーカイブ・マスク・出力の整合性、ログの期間と上限を確認 | 必要 |
| `make dist` | 配布用アーカイブを `dist/` に作る | 不要 |

これらはリポジトリにあります。**配布アーカイブには `Makefile`・`tests/`・CI 設定は含まれません。** 実行するにはリポジトリを取得してください。

`make smoke` は実ホストの情報を一時ディレクトリに収集します。確認用のログを `/var/log/lighttpd/` に一時的に置きます（既に存在するホストでは置かず、終了時に消します）。コンテナか検証機で実行してください。
CI（`.github/workflows/ci.yml`）は push と pull request のたびに、lint・単体テスト・10 環境での実収集・実機ランナーでの実収集を行います。

## 10. 既知の制約

- 稼働中のホストから収集するため、カーネルレベルで隠蔽された情報は取れない。rootkit が疑われる場合、収集結果は改ざんされている前提で扱い、メモリ・ディスクの取得を検討する
- 対象ホスト上のコマンド（`ps` `ss` `find` 等）を使う。これらが置き換えられている場合、出力は信用できない
- メモリダンプ、ディスクイメージ、ネットワークキャプチャは取らない
- コンテナ内部のファイルシステムとログ本体は収集しない（full でログ末尾 1000 行のみ）。VM のゲストの中も同様（ゲストごとに実行する）
- Kubernetes はノード上のファイルのみ。API サーバーへの問い合わせ（`kubectl`）は行わない
- BusyBox の `ps`（Alpine 等）では、プロセスの開始時刻・CPU / メモリ使用率・ツリー表示が取れない。WARN と `execution/ps_limited.txt` で明示する
- コマンドが「オプションを無視して正常終了する」形で劣化した場合は検出できない。検出できるのは、コマンドが非 0 で終了した場合（WARN）と、存在しない場合（出力ファイルにその旨を記録）
- fast モードの時間上限は `timeout` コマンドで実現している。`timeout` が無い環境では走査を途中で止められず、上限は場所の切れ目でしか効かない（WARN を出す）
- 収集時刻は対象ホストの時計に基づく。時計のずれは `system/timezone.txt` と手元の記録で確認する
- **ログの期間は更新日時で判定する**。更新日時を古く書き換えられたログは取らない（`log_inventory.tsv` に `older_than_period` として残る）。また、上の群に入らないアプリケーションのログ（`/var/log/<独自のアプリ>` 等）は取らない（`logs/var_log_listing.txt` に一覧のみ）
- ログの容量の上限は厳密に適用する。最も新しいファイル 1 つが上限を超える群は、何も取らない（WARN と `over_cap`）。必要なら `--log-max-mb` を上げるか `0`（上限なし）で再収集する
- journal のテキスト出力の上限は件数による目安。1 件が長いログでは上限 MB を超え得る
- テキスト形式のログイン記録（`last_logins.txt` 等）は現行の wtmp / btmp のみ。ローテーション分はバイナリでコピーするので、解析端末で `last -f` で読む
- `modified_last_7days.txt` は 7 日固定（ログの期間に連動しない）
- fast モードの SUID/SGID 検索は `/usr/lib` を見ない（ファイル数が多く、60 秒の上限を使い切るため）。`/usr/lib` 配下の SUID は full モードで取る
- SSH の `AuthorizedKeysFile` は、`sshd_config` の `Match` ブロックの中の指定を評価しない。`AuthorizedKeysCommand`（LDAP 等から鍵を引く）の結果は取らない（設定は `sshd_effective_config.txt` に残る）
- `getent passwd` は 15 秒で打ち切る（応答しないディレクトリサーバー対策）。その場合は `/etc/passwd` のユーザーだけになる
- VirtualBox の VM は、root に VirtualBox の設定が無い場合は `VBoxManage` で問い合わせない。ユーザーごとの VM は登録ファイル（`VirtualBox.xml`）と `VirtualBox VMs` の一覧のみ
- libvirt のユーザーセッション（`qemu:///session`）の VM は問い合わせない（稼働中なら `hypervisor_processes.tsv` には出る）
- 仮想化の判定はゲストから見える情報（DMI、CPUID）による。ハイパーバイザが隠している場合は `none` になり得る
- 秘匿値のマスクは名前に基づく。無関係な名前の変数・項目に入った秘匿値（`qm` の `args:` 等の自由形式の引数を含む）は伏せられない
