# LDIR-Toolkit 仕様書

対象バージョン: 0.3.0

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

## 2. 動作要件

| 項目 | 要件 |
|---|---|
| OS | Linux |
| シェル | bash 4.2 以上（Alpine など bash が無い環境では事前に導入が必要） |
| 権限 | root（`sudo` 可）。root でない場合は何も収集せず終了する |
| 必須コマンド | `find` `awk` `sort` `xargs` `sha256sum` `cp` `tar`（`--archive` 使用時） |
| 任意コマンド | 無ければ該当項目を飛ばす: `journalctl` `ss` `lsof` `bpftool` `getcap` `docker` `crictl` `curl` など |
| ネットワーク | 不要。クラウドメタデータ収集を有効にした場合のみ、リンクローカルの API へ接続する |
| 空き容量 | fast: 数十 MB〜数百 MB。full: ログ量とユーザーデータに依存し、GB 単位になり得る |

CI で実収集を確認している環境: Ubuntu 20.04 / 24.04、Debian 12、Rocky Linux 9、AlmaLinux 8、Fedora、Amazon Linux 2023、Arch Linux、openSUSE Leap 15、Alpine 3（BusyBox）。

**未確認の範囲**: CI はコンテナ内での実行です。systemd が稼働する実機、SELinux 有効環境、実際のクラウドインスタンス、稼働中の Docker / Kubernetes ノードでは自動検証していません。

## 3. コマンドライン

```
ldir-collect.sh [options] [output_directory]
```

| 引数 / オプション | 内容 |
|---|---|
| `output_directory` | 出力のベースディレクトリ。省略時は `/tmp/ldir_output` |
| `-m`, `--mode MODE` | `fast`（既定）または `full` |
| `-a`, `--archive` | 収集後に `tar.gz` と `.sha256` を作成する |
| `--no-redact` | 環境変数の秘匿値マスクを行わない |
| `-l`, `--list-modules` | モジュール一覧を表示して終了 |
| `-V`, `--version` | バージョンを表示して終了 |
| `-h`, `--help` | 使い方を表示して終了 |

### 3.1 環境変数

| 変数 | 既定値 | 内容 |
|---|---|---|
| `LDIR_MODE` | `fast` | `--mode` と同じ |
| `LDIR_ENABLE_WEB` | fast: `0` / full: `1` | ブラウザアーティファクトの収集 |
| `LDIR_ENABLE_CLOUD_METADATA` | fast: `0` / full: `1` | クラウドメタデータ API への問い合わせ |
| `LDIR_ARCHIVE` | `0` | `--archive` と同じ |
| `LDIR_REDACT_SECRETS` | `1` | 環境変数の秘匿値マスク。`0` で無効 |
| `LDIR_VERBOSE` | `0` | 「対象が存在しない」通知も画面に出す |
| `LDIR_CLOUD_METADATA_TIMEOUT` | `2` | メタデータ API 1 回あたりの待ち時間（秒） |
| `LDIR_CONTAINER_TIMEOUT` | `20` | コンテナランタイムへの問い合わせ 1 回あたりの待ち時間（秒） |
| `NO_COLOR` | 未設定 | 設定すると画面出力を着色しない |

`sudo` は既定で環境変数を引き継ぎません。変数で指定する場合は `sudo LDIR_MODE=full ./ldir-collect.sh ...` のように `sudo` の後ろに書きます。

### 3.2 終了コード

| コード | 意味 |
|---|---|
| `0` | すべてのモジュールが完了した |
| `1` | 引数の誤り、root でない、出力先を作れない等。何も収集していない |
| `2` | 収集は終わったが、失敗したモジュールがある、またはハッシュ一覧・アーカイブの作成に失敗した |

## 4. 収集モード

| | fast（既定） | full |
|---|---|---|
| 想定 | 初動。短時間・小容量 | 詳細調査。時間と容量がかかる |
| 変更ファイル・SUID・world-writable の探索 | 主要パスのみ | `/` 全体 |
| システムバイナリのハッシュ | 取らない | `/bin` `/sbin` `/usr/bin` `/usr/sbin` |
| file capabilities の探索 | 主要パスのみ | `/` 全体 |
| プロセスごとの環境変数・オープンファイル | 取らない | 取る |
| journal 全期間 | 取らない（直近 7 日と末尾 1000 行） | 取る |
| ユーザーの `~/.config` | 一覧のみ | 丸ごとコピー |
| コンテナのログ末尾・`top` | 取らない | 取る |
| ブラウザ / クラウドメタデータ | 無効 | 有効 |

## 5. 処理の流れ

1. 引数を解析し、root 権限を確認する
2. 出力ディレクトリ `<output_directory>/<ホスト名>_<YYYYMMDD_HHMMSS>/` を権限 `700` で作る（`umask 077`）
3. 環境を検出する（ディストリビューション、init、パッケージ管理、コンテナ種別、SELinux / AppArmor）
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
| 2 | `15_execution.sh` | `execution/` | プロセス、`/proc` 詳細、コマンド履歴、auditd |
| 3 | `20_network.sh` | `network/` | 接続、待ち受け、経路、ARP、ファイアウォール、DNS 設定 |
| 4 | `25_kernel.sh` | `kernel/` | カーネルモジュール、eBPF、`ld.so.preload`、capabilities、sysctl |
| 5 | `30_containers.sh` | `containers/` | Docker / Podman / CRI / Kubernetes ノード |
| 6 | `40_auth.sh` | `config/` | ユーザー、sudoers、PAM、SSH 設定 |
| 7 | `50_persistence.sh` | `persistence/` | systemd、cron、at、init、自動起動、シェル初期化ファイル |
| 8 | `60_logs.sh` | `logs/` | journal、syslog、認証ログ、ログイン履歴、各種アプリログ |
| 9 | `70_filesystem.sh` | `filesystem/` | マウント、最近の変更、SUID/SGID、未パッケージのバイナリ |
| 10 | `80_web.sh` | `web/` | ブラウザの履歴・Cookie 等（fast では無効） |
| 11 | `90_custom_environment.sh` | `custom_environment/` | init / パッケージ管理 / SELinux / AppArmor の詳細 |
| 12 | `91_cloud_metadata.sh` | `cloud_metadata/` | AWS / Azure / GCP / OCI / DigitalOcean / Alibaba |

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

### 6.2 manifest.txt

| セクション | 内容 |
|---|---|
| ヘッダ | ツールのバージョン、モード、マスクの有無、収集時刻（ローカルと UTC）、ホスト名 |
| System Information | ディストリビューション、カーネル、アーキテクチャ、init、パッケージ管理、コンテナ種別、SELinux、AppArmor |
| Collection Modules | モジュールごとに 1 行 |
| Collection Statistics | ファイル数、容量、成功 / 失敗モジュール数、所要秒数、終了時刻 |

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

`WARN` には「失敗」のほか「調査担当者に見てほしい所見」も含みます。現在の所見は次の 2 つです。

- `/etc/ld.so.preload` が存在する
- `/proc/modules` と `/sys/module` のモジュール一覧が食い違う

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

### 7.1 `system/`

`uname.txt` `hostname.txt` `collection_time.txt` `uptime.txt` `os-release` `kernel_version.txt` `kernel_cmdline.txt`
`cpu_info.txt` `memory_info.txt` `disk_usage.txt` `block_devices.txt` `ip_addresses.txt` `routing_table.txt` `timezone.txt`
`environment_variables.txt`（収集プロセス自身の環境変数。秘匿値はマスク）

### 7.2 `execution/`

| ファイル | 内容 |
|---|---|
| `running_processes.txt` `running_processes_tree.txt` `process_start_times.txt` | `ps` の各形式 |
| `process_tree.txt` `top_snapshot.txt` | `pstree`、`top` の 1 回分 |
| `proc_details/<PID>/` | `cmdline.txt` `exe.txt` `cwd.txt` `status.txt`。full では `environ.txt`（マスク対象）`open_files.txt` も |
| `bash_history_<ユーザー>` `zsh_history_<ユーザー>` | コマンド履歴 |
| `audit/` `audit_execve.txt` `audit_user_cmd.txt` | auditd のログと抽出 |
| `running_services.txt` `lsof_all.txt` `lsof_network.txt` | 稼働サービス、オープンファイル |

`exe.txt` が `(deleted)` で終わるプロセスは、実行ファイルが削除済みであることを示します。

### 7.3 `network/`

`ss_listening.txt` `ss_established.txt` `ss_all.txt` `netstat_*.txt` `arp_cache.txt` `ip_routes.txt` `ip_addresses.txt`
`iptables_*.txt` `nftables_ruleset.txt` `ufw_status.txt` `firewalld_config.txt`
`resolv.conf` `hosts` `nsswitch.conf` `tcp` `udp`（`/proc/net` の写し）`NetworkManager/` `systemd-network/`

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

このホストがコンテナを**動かす側**である場合の情報です。ランタイムが見つからなければ `no_container_runtime.txt` だけを残します。

| パス | 内容 |
|---|---|
| `docker/` `podman/` | `version.txt` `info.txt` `ps_all.txt` `images.txt` `networks.txt` `volumes.txt` `network_inspect.json` |
| `<cli>/inspect/<ID>.json` | コンテナの詳細。`Env` の秘匿値はマスク |
| `<cli>/inspect/<ID>.diff.txt` | イメージからのファイル変更点 |
| `<cli>/risk_summary.tsv` | 特権・PID / ネットワーク名前空間の共有・追加 capabilities・ホストのマウントを 1 行にまとめたもの |
| `<cli>/inspect/<ID>.top.txt` `<ID>.logs_tail.txt` | full のみ。プロセスとログ末尾 1000 行 |
| `config/` | `daemon.json`、`/etc/containers/`、containerd・CRI-O の設定 |
| `config/user_credential_files_present.txt` | `~/.docker/config.json` `~/.kube/config` の**存在のみ** |
| `privileged_groups.txt` `runtime_sockets.txt` | `docker` 等のグループ所属、ソケットの権限 |
| `cri/` | `crictl pods` / `ps -a` / `images`、`ctr namespaces list` |
| `kubernetes/static_pod_manifests/` | `/etc/kubernetes/manifests/` の写し |
| `kubernetes/kubelet_config.yaml` `kubelet_pods.txt` `kubelet_journal_tail.txt` `pki_certs/` | kubelet 設定、Pod 一覧、ログ末尾、証明書（`.crt` のみ） |
| `container_related_processes.txt` | ランタイム関連プロセス |

デーモンが応答しない場合は `info.txt` に結果を残し、それ以降の問い合わせを省略します。

### 7.6 `config/`

`passwd` `shadow` `group` `gshadow` `sudoers` `sudoers.d/` `pam.d/` `security/` `ssh/`
`user_ssh/<ユーザー>/`（`authorized_keys` `known_hosts` `config`）`who_all.txt` `last_full.txt`

### 7.7 `persistence/`

`systemd_unit_files.txt` `systemd_units_all.txt` `systemd_timers.txt` `systemd_system/` `systemd_usr_lib/` `systemd_user_<ユーザー>/`
`init.d/` `rc.local` `crontab` `cron.d/` `cron.daily/` ほか `user_crontabs/` `user_crontab_l/<ユーザー>.txt` `at_jobs/`
`autostart_system/` `autostart_user_<ユーザー>/` `ld_preload_references.txt` `shell_init/<ユーザー>/` `profile` `profile.d/`

### 7.8 `logs/`

`journal_tail.txt`（末尾 1000 行）`journal_7days.txt` `journal_errors.txt` `journal_ssh.txt` `journal_sshd.txt` `journal_cron.txt`
`journal_full.txt`（full のみ）`syslog` `messages` `auth.log` `secure` `kern.log` `wtmp` `btmp` `lastlog`
`last_logins.txt` `failed_logins.txt` `apt/` `dpkg.log` `dnf.log` `apache2/` `httpd/` `nginx/` `mysql/` `postgresql/` ほか

### 7.9 `filesystem/`

| ファイル | 内容 |
|---|---|
| `mount_points.txt` `proc_mounts.txt` `fstab.txt` `disk_usage_human.txt` | マウントと容量 |
| `modified_last_7days.txt` | 7 日以内に変更されたファイル |
| `tmp_files.txt` `var_tmp_files.txt` `hidden_files_sensitive.txt` `dev_shm_contents.txt` | 一時領域の内容 |
| `suid_sgid_files.txt` `world_writable_files.txt` | 権限の観点 |
| `unpackaged_binaries_dpkg.txt` / `_rpm.txt` | パッケージに属さない `/usr/bin` `/usr/sbin` `/usr/local/bin` `/usr/local/sbin` のファイル |
| `deleted_open_files.txt` | 削除済みだが開かれたままのファイル |
| `system_binaries_hashes.txt` | full のみ |
| `etc_file_list.txt` `directory_tree.txt` | 一覧 |

`unpackaged_binaries_*.txt` は**確認対象の候補**です。`update-alternatives` のリンクや手動導入したツールも載ります。
収集ディレクトリ自身は、すべての探索から除外します。

### 7.10 `web/` `custom_environment/` `cloud_metadata/`

- `web/`: Firefox / Chrome / Chromium / Brave / Edge / Opera の履歴・Cookie・ログインデータ（暗号化されたまま）。無効時は `disabled.txt` のみ
- `custom_environment/`: init 別のサービス一覧、パッケージ一覧と導入履歴、SELinux / AppArmor の状態、`/opt/*/conf` 等の設定、`~/.config` の一覧
- `cloud_metadata/`: インスタンス ID、種別、リージョン、ネットワーク、IAM ロール名、user-data。無効時は `disabled.txt`、検出なしは `no_cloud.txt`

## 8. 秘匿情報の扱い

収集物は調査担当者や外部へ渡ります。次の方針で扱います。

### 8.1 既定でマスクするもの

環境変数の**値**のうち、名前が秘匿情報らしいもの。名前は残し、値は文字数だけ残します。

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

判定に使う名前: `TOKEN` `SECRET` `PASSW` `CREDENTIAL` `API_KEY` `ACCESS_KEY` `PRIVATE_KEY` `COOKIE` `BEARER` `JWT` `SIGNATURE` `AUTHORIZATION` を含むもの、`_KEY` `_PWD` `_AUTH` で終わるもの。
あわせて、値に含まれる URL の `ユーザー:パスワード@` 部分。

判定は名前に基づきます。**無関係な名前の変数に入った秘匿値は伏せられません。**
攻撃者が設定した環境変数そのものを証拠として残したい場合は `--no-redact` を使います。

### 8.2 収集しないもの

- SSH の秘密鍵（ユーザーの鍵、ホスト鍵 `ssh_host_*_key`）
- `~/.docker/config.json`、`~/.kube/config`、`/etc/containers/auth.json`
- Kubernetes の秘密鍵と kubeconfig（`/etc/kubernetes/pki/*.key`、`/etc/kubernetes/*.conf`）

### 8.3 マスクされずに含まれるもの

収集物そのものが機微情報です。次のものは調査に必要なため、そのまま含みます。

- `/etc/shadow`、`/etc/gshadow`（パスワードハッシュ）
- コマンド履歴（コマンドラインに書かれたパスワードを含み得る）
- 各種ログ、プロセスのコマンドライン
- full / Web 有効時: ブラウザの履歴・Cookie、`~/.config` 全体
- クラウドの user-data（起動スクリプトに認証情報が書かれていることがある）

収集ディレクトリは権限 `700` で作りますが、**保管と受け渡しの管理は利用者の責任**です。

## 9. 構成と拡張

```
ldir-toolkit/
├── ldir-collect.sh              本体
├── lib/
│   ├── common.sh                ログ、コピー、マスク等の共通関数
│   └── detect_distro_advanced.sh  環境検出
└── modules/NN_<名前>.sh          収集モジュール
```

### 9.1 モジュールの規約

- ファイル名は `NN_<名前>.sh`。`NN` の昇順に実行される。**番号は揮発性の順を表す**ので、追加時は適切な位置の番号を選ぶ
- 第 1 引数で収集ディレクトリを受け取り、`<収集ディレクトリ>/<名前>/` に出力する
- `lib/common.sh` を `source` する
- 対象が無いことは失敗ではない。`exit 0` で終える。続行できない場合のみ非 0
- `modules/` に置けば自動で実行対象になる。本体の編集は不要
- 仕様書（本書 5.1 節）に 1 行追加する。単体テストがこれを確認する

### 9.2 共通関数

| 関数 | 用途 |
|---|---|
| `log_info` `log_warn` `log_error` `log_success` `log_debug` | ログ出力（6.3 節） |
| `safe_copy <src> <dst>` | 属性を保ったコピー。対象が無ければ DEBUG を残して戻る |
| `save_command_output <cmd> <file>` | コマンド出力を保存。失敗は WARN |
| `redact_env` | 標準入力の `NAME=VALUE` 行から秘匿値を伏せるフィルタ |
| `run_limited <秒> <cmd...>` | 時間制限付きで実行 |
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

### 9.3 テスト

| コマンド | 内容 | root |
|---|---|---|
| `make lint` | shellcheck | 不要 |
| `make test` | 共通関数、環境検出、引数、マスク規則の単体テスト | 不要 |
| `sudo make smoke` | 実際に収集し、manifest・ハッシュ・アーカイブ・マスク・出力の整合性を確認 | 必要 |
| `make dist` | 配布用アーカイブを `dist/` に作る | 不要 |

`make smoke` は実ホストの情報を一時ディレクトリに収集します。コンテナか検証機で実行してください。
CI（`.github/workflows/ci.yml`）は push と pull request のたびに、lint・単体テスト・10 環境での実収集を行います。

## 10. 既知の制約

- 稼働中のホストから収集するため、カーネルレベルで隠蔽された情報は取れない。rootkit が疑われる場合、収集結果は改ざんされている前提で扱い、メモリ・ディスクの取得を検討する
- 対象ホスト上のコマンド（`ps` `ss` `find` 等）を使う。これらが置き換えられている場合、出力は信用できない
- メモリダンプ、ディスクイメージ、ネットワークキャプチャは取らない
- コンテナ内部のファイルシステムとログ本体は収集しない（full でログ末尾 1000 行のみ）
- Kubernetes はノード上のファイルのみ。API サーバーへの問い合わせ（`kubectl`）は行わない
- `/home` 以外にホームディレクトリを持つユーザーの履歴・設定は収集されない
- 収集時刻は対象ホストの時計に基づく。時計のずれは `system/timezone.txt` と手元の記録で確認する
