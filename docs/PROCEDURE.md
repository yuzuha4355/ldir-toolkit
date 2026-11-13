# LDIR-Toolkit 収集手順書

対象バージョン: 0.3.2

インシデント対応の初動で、対象ホストから収集を行い、収集物を引き渡すまでの手順です。
ツールの仕様は [SPECIFICATION.md](SPECIFICATION.md) を参照してください。

---

## 0. 全体の流れ

| 段階 | 行うこと | 目安 |
|---|---|---|
| 1. 準備 | ツールの入手と検証、出力先の用意、記録の開始 | 事前 |
| 2. 収集 | 対象ホストで実行 | fast: 1〜数分 / full: 数分〜数十分 |
| 3. 確認 | 結果の確認、ハッシュの記録 | 5 分 |
| 4. 持ち出し | 収集物の転送、転送後の検証 | 容量による |
| 5. 後始末 | 対象ホストからの削除、記録の締め | 5 分 |

## 1. 着手前の判断

収集を始める前に、次の 3 点を決めます。

### 1.1 ホストを止めるか、動かしたまま収集するか

本ツールは**動いているホスト**から情報を取ります。再起動や電源断を行うと、プロセス・接続・メモリ上の情報は失われます。

- 原則: 収集が終わるまで、再起動・シャットダウン・サービスの再起動をしない
- 被害の拡大が続いている場合: ネットワークからの隔離を優先する。隔離は電源断ではなく、スイッチ側やセキュリティグループで行う

### 1.2 どこへ出力するか

| 出力先 | 評価 |
|---|---|
| 外部媒体（USB 等）・別ボリューム | **推奨**。対象ディスクへの書き込みを避けられる |
| ネットワーク共有（NFS 等） | 可。対象ホストに新たな接続が発生することを記録する |
| 対象ホストの `/tmp` 等 | 最終手段。削除済みファイルの領域を上書きし得る |

対象ホストのディスクに書く場合も、収集ディレクトリ自身は探索結果に混入しません。

### 1.3 fast か full か

- **まず fast**。短時間で終わり、容量も小さい
- full は、fast の結果を見て必要と判断してから。ブラウザデータや `~/.config` 全体など、個人情報を多く含む

## 2. 準備

### 2.1 ツールの入手と検証

調査用の端末で行います。

```bash
sha256sum -c ldir-toolkit-v0.3.2.tar.gz.sha256
```

```bash
tar -xzf ldir-toolkit-v0.3.2.tar.gz
```

リポジトリから配布物を作る場合:

```bash
make dist
```

`dist/` に `tar.gz` と `.sha256` ができます。

### 2.2 記録の開始

次の項目を、作業前に記録します。様式は付録 A にあります。

- 作業者、立会者
- 対象ホスト（ホスト名、IP アドレス、設置場所または クラウドのインスタンス ID）
- 作業開始時刻（**調査端末の時計**で。対象ホストの時計は信用しない）
- 使用するツールのバージョンと、配布物の SHA256
- 出力先の媒体（識別番号など）

### 2.3 対象ホストへの持ち込み

**外部媒体を使う場合（推奨）**

```bash
sudo mkdir -p /mnt/ldir
```

```bash
sudo mount /dev/sdX1 /mnt/ldir
```

デバイス名は `lsblk` で確認してください。取り違えると別のディスクをマウントします。

**転送する場合**

```bash
scp ldir-toolkit-v0.3.2.tar.gz <ユーザー>@<対象ホスト>:/tmp/
```

対象ホスト上で展開します。

```bash
cd /tmp && tar -xzf ldir-toolkit-v0.3.2.tar.gz
```

SSH でログインすること自体が、認証ログとログイン履歴に記録されます。ログイン時刻を控えておきます。

### 2.4 空き容量の確認

```bash
df -h /mnt/ldir
```

fast で数百 MB、full で数 GB を見込みます。

## 3. 収集

### 3.1 実行（fast・アーカイブ付き）

```bash
cd /mnt/ldir/ldir-toolkit-v0.3.2
```

```bash
sudo ./ldir-collect.sh --archive /mnt/ldir/evidence
```

実行中は画面に進行が出ます。モジュールは、プロセス → ネットワーク → カーネル → コンテナ → 設定 → ログ → ファイルシステムの順に動きます。

### 3.2 実行（full）

fast の結果を確認し、必要な場合のみ。

```bash
sudo ./ldir-collect.sh --mode full --archive /mnt/ldir/evidence
```

### 3.3 状況に応じた指定

| 状況 | 指定 |
|---|---|
| fast のままブラウザデータも取りたい | `sudo LDIR_ENABLE_WEB=1 ./ldir-collect.sh ...` |
| クラウドのインスタンスである | `sudo LDIR_ENABLE_CLOUD_METADATA=1 ./ldir-collect.sh ...` |
| full だがメタデータ API には接続したくない | `sudo LDIR_ENABLE_CLOUD_METADATA=0 ./ldir-collect.sh --mode full ...` |
| 環境変数の値を伏せずに残したい | `--no-redact` を付ける |

`--no-redact` を使うと、収集物にトークンやパスワードが平文で入ります。使った場合は記録に残し、収集物の取り扱いを一段厳しくしてください。

### 3.4 実行中にしてはいけないこと

- `Ctrl+C` で止める。止めた場合、ハッシュ一覧が作られません。その収集ディレクトリは破棄せず残し、記録したうえで再実行します
- 同じホストで別の調査コマンドを並行して流す（プロセス一覧や接続一覧に自分の操作が混ざります）
- 出力先の媒体を抜く

## 4. 結果の確認

### 4.1 終了時の表示

```
=== Collection Summary ===
Output:             /mnt/ldir/evidence/web01_20261112_101500
Hash list SHA256:   5a87a651...
Archive:            /mnt/ldir/evidence/web01_20261112_101500.tar.gz
Archive SHA256:     9c1f03be...
Successful Modules: 12/12
Failed Modules:     0/12
```

**`Hash list SHA256` と `Archive SHA256` を記録に書き写します。** この 2 つが、収集物が後から変更されていないことの根拠になります。

### 4.2 終了コード

```bash
echo $?
```

| 値 | 対応 |
|---|---|
| `0` | 次へ進む |
| `1` | 何も収集されていない。画面のエラーを確認する（5 章） |
| `2` | 収集は終わったが失敗がある。4.3 で内容を確認する |

### 4.3 manifest の確認

```bash
cat /mnt/ldir/evidence/<ホスト名>_<日時>/metadata/manifest.txt
```

見る点:

- `✗` の付いたモジュールが無いか
- `warn=` が 0 でないモジュール。内容は次で確認できます

```bash
grep -h '^\[WARN\]' /mnt/ldir/evidence/<ホスト名>_<日時>/metadata/modules/*.log
```

WARN の読み方:

| メッセージ | 意味 | 対応 |
|---|---|---|
| `Command failed (exit N): <コマンド> -> <ファイル>` | コマンドがそのホストで失敗した。出力ファイルにはエラー文が入っている | 多くは権限やコンテナ環境の制約。**その項目は取れていない**ものとして記録する |
| `ps is not procps (BusyBox?)` | `ps` が簡易版で、開始時刻・CPU 使用率・ツリー表示が取れない | `execution/ps_limited.txt` の読み替え方に従う。親子関係は `ppid` 列と `proc_details/` で追う |
| `Command failed or timed out: docker info` | Docker は入っているがデーモンが応答しない | 停止中なら正常。想定外なら調査対象 |
| `/etc/ld.so.preload exists` | 全プロセスにライブラリが注入される設定がある | **優先して調査**。`kernel/ld.so.preload` の内容を確認 |
| `Module lists in /proc/modules and /sys/module differ` | カーネルモジュールの一覧が食い違う | **優先して調査**。`kernel/modules_in_*.txt` を確認 |
| `... search stopped at the 60s budget; lists are partial` | fast モードの権限検索が時間切れになった（`/opt` 等が大きい） | `filesystem/scan_incomplete.txt` で未走査の場所を確認。必要なら full で再収集 |
| `LD_PRELOAD scan of /etc hit the 60s limit` | `/etc` の検索が時間切れになった | 結果は部分的。`kernel/ld.so.preload*` は別途確認済みなので、そちらを優先して見る |
| `Unknown init system` | init を判別できなかった | コンテナ内では通常 |

### 4.4 その場での検証

```bash
cd /mnt/ldir/evidence/<ホスト名>_<日時>
```

```bash
sha256sum -c metadata/file_hashes.txt | grep -v ': OK$'
```

何も表示されなければ正常です。

## 5. うまくいかないとき

| 症状 | 原因と対応 |
|---|---|
| `This script must be run as root` | `sudo` を付ける |
| `bash: not found` / `bad interpreter` | bash が無い。Alpine では `apk add bash`。導入できない場合、その旨を記録して手作業の収集に切り替える |
| `Permission denied` で起動できない | 媒体が `noexec` でマウントされている。`sudo bash ./ldir-collect.sh ...` で実行する |
| `No space left on device` | 出力先を変える。途中までの収集ディレクトリは消さずに残す |
| 途中で止まって見える | full の `/` 全体探索は時間がかかる。別の端末から `tail -f <収集ディレクトリ>/metadata/collection.log` で進行を確認する |
| `sudo` で環境変数が効かない | `sudo LDIR_MODE=full ./ldir-collect.sh` のように `sudo` の後ろに書く。または `--mode` を使う |
| SELinux が Enforcing で一部が取れない | WARN として記録される。モードは変更しない。欠けた項目を記録する |

対象ホストの設定を変えて収集を通そうとしないでください。取れなかった事実を記録するほうが、証拠としての価値を保てます。

## 6. 持ち出し

### 6.1 転送

外部媒体に出力した場合は、アンマウントして取り外します。

```bash
cd / && sudo umount /mnt/ldir
```

対象ホストのディスクに出力した場合は、調査端末から取得します。

```bash
scp <ユーザー>@<対象ホスト>:/tmp/ldir_output/<ホスト名>_<日時>.tar.gz* ./
```

### 6.2 転送後の検証（調査端末で）

```bash
sha256sum -c <ホスト名>_<日時>.tar.gz.sha256
```

表示されたハッシュが、4.1 で記録した `Archive SHA256` と一致することも目で確認します。`.sha256` ファイルは収集物と一緒に運ばれるため、それだけでは改ざんの検出になりません。

展開後、中身も検証します。

```bash
tar -xzf <ホスト名>_<日時>.tar.gz && cd <ホスト名>_<日時>
```

```bash
sha256sum metadata/file_hashes.txt
```

この値が、記録した `Hash list SHA256` と一致することを確認します。

```bash
sha256sum -c metadata/file_hashes.txt | grep -v ': OK$'
```

### 6.3 保管

- 原本（アーカイブ）は書き込み禁止の場所に保管し、解析は複製に対して行う
- 収集物には `/etc/shadow`、コマンド履歴、ログが含まれる。アクセスできる人を限定する
- 外部へ渡す場合は暗号化する。例:

```bash
gpg --symmetric --cipher-algo AES256 <ホスト名>_<日時>.tar.gz
```

パスフレーズは収集物と別の経路で伝えます。

## 7. 後始末

対象ホストのディスクにツールや収集物を置いた場合は、持ち出しと検証が済んでから削除します。

```bash
sudo rm -rf /tmp/ldir_output /tmp/ldir-toolkit-v0.3.2 /tmp/ldir-toolkit-v0.3.2.tar.gz
```

削除したパスと時刻を記録します。作業終了時刻を記録し、記録を締めます。

## 8. 収集物の最初の見どころ

解析の出発点です。網羅的な手順ではありません。

| 見るもの | ファイル | 着眼点 |
|---|---|---|
| 所見の有無 | `metadata/modules/*.log` の WARN | `ld.so.preload`、モジュール一覧の食い違い |
| 実行ファイルが消されたプロセス | `execution/proc_details/*/exe.txt` | 末尾が `(deleted)` |
| 一時領域から動くプロセス | `execution/proc_details/*/exe.txt` `cwd.txt` | `/tmp` `/dev/shm` `/var/tmp` |
| 待ち受けと外向き接続 | `network/ss_listening.txt` `ss_established.txt` | 見覚えのないポート、宛先 |
| ログイン | `logs/last_logins.txt` `failed_logins.txt` `auth.log` | 時間帯、接続元、失敗の連続 |
| 鍵の追加 | `config/user_ssh/*/authorized_keys` | 覚えのない公開鍵 |
| 権限 | `config/sudoers` `sudoers.d/` `passwd` | UID 0 の追加、`NOPASSWD` |
| 永続化 | `persistence/` | 最近作られたユニット、cron、シェル初期化ファイルの追記 |
| 最近の変更 | `filesystem/modified_last_7days.txt` | 侵害が疑われる時刻の前後 |
| 権限昇格の足場 | `filesystem/suid_sgid_files.txt` `kernel/file_capabilities.txt` | 標準でないパスのファイル |
| 由来不明のバイナリ | `filesystem/unpackaged_binaries_*.txt` | 候補の一覧。1 件ずつ由来を確認 |
| カーネル | `kernel/sys_module_details.tsv` `bpf_progs.txt` | taint 付きモジュール、由来不明の eBPF |
| コンテナ | `containers/*/risk_summary.tsv` | `privileged=true`、`pid=host`、ホストの `/` や docker.sock のマウント |
| 操作の痕跡 | `execution/bash_history_*` | ダウンロード、権限変更、ログ削除 |

rootkit が疑われる場合、このツールの出力は対象ホストのコマンドに依存しているため、改ざんされている可能性があります。メモリとディスクの取得を検討してください。

---

## 付録 A. 作業記録の様式

```
【収集作業記録】

案件番号        :
作業者          :
立会者          :

対象ホスト名    :
IP アドレス     :
設置場所 / インスタンス ID :

ツール          : LDIR-Toolkit v
配布物 SHA256   :

作業開始        : YYYY-MM-DD hh:mm （調査端末の時計、タイムゾーン）
対象ホストの時刻: YYYY-MM-DD hh:mm （date コマンドの表示。ずれ:     ）
ログイン方法    : コンソール / SSH（接続元:          ）

実行コマンド    :
モード          : fast / full
マスク          : 有 / 無（--no-redact）
出力先          :
出力媒体の識別  :

終了コード      :
失敗モジュール  :
WARN の所見     :

Hash list SHA256:
Archive SHA256  :

持ち出し方法    :
転送後の検証    : 一致 / 不一致
対象ホストからの削除: 済（hh:mm）/ 該当なし
保管場所        :

作業終了        : YYYY-MM-DD hh:mm
特記事項        :
```

## 付録 B. 早見表

```bash
# 収集（fast、アーカイブ付き）
sudo ./ldir-collect.sh --archive /mnt/ldir/evidence

# 収集（full）
sudo ./ldir-collect.sh --mode full --archive /mnt/ldir/evidence

# WARN の確認
grep -h '^\[WARN\]' <収集ディレクトリ>/metadata/modules/*.log

# 検証（不一致だけ表示）
cd <収集ディレクトリ> && sha256sum -c metadata/file_hashes.txt | grep -v ': OK$'
```
