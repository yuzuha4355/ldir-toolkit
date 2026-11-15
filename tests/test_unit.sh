#!/bin/bash
# lib/ の単体テスト。root 不要、システムには触れない。
#   bash tests/test_unit.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${HERE}/../ldir-toolkit"
# shellcheck source=tests/lib.sh
source "${HERE}/lib.sh"

WORK="$(mktemp -d)"
# TD: root のときだけ使う、root しか書けない場所の作業ディレクトリ（safe_copy のリンクの確認用）
TD=""
trap 'rm -rf "${WORK}"; [[ -n "${TD}" ]] && rm -rf "${TD}"' EXIT
TAB=$'\t'
NL=$'\n'

OUTPUT_DIR="${WORK}/out"
mkdir -p "${OUTPUT_DIR}/metadata"
LDIR_MODULE_LOG="${WORK}/module.log"
# shellcheck source=ldir-toolkit/lib/common.sh
source "${TOOLKIT}/lib/common.sh"

echo "== safe_copy =="
mkdir -p "${WORK}/src/dir/sub"
echo a > "${WORK}/src/file"
echo b > "${WORK}/src/dir/one"
echo c > "${WORK}/src/dir/sub/two"

safe_copy "${WORK}/src/file" "${WORK}/d1/"
check "file -> dir/           lands inside dir" test -f "${WORK}/d1/file"

safe_copy "${WORK}/src/file" "${WORK}/d2/renamed"
check "file -> path           is renamed" test -f "${WORK}/d2/renamed"

safe_copy "${WORK}/src/dir/" "${WORK}/d3/dir/"
check "dir/ -> dst/           copies contents" test -f "${WORK}/d3/dir/one"
check "dir/ -> dst/           keeps subdirs" test -f "${WORK}/d3/dir/sub/two"
check_not "dir/ -> dst/           does not nest (dir/dir)" test -e "${WORK}/d3/dir/dir"

safe_copy "${WORK}/src/dir" "${WORK}/d4/"
check "dir -> dst/            keeps dir name" test -f "${WORK}/d4/dir/one"

safe_copy "${WORK}/src/dir" "${WORK}/d5/newname"
check "dir -> new path        is renamed" test -f "${WORK}/d5/newname/one"

check_not "missing source         returns non-zero" safe_copy "${WORK}/nope" "${WORK}/d6/"
check_not "missing source         is not a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"
check "missing source         is logged as DEBUG" grep -q '^\[DEBUG\].*nope' "${LDIR_MODULE_LOG}"

echo "== safe_copy: symbolic links =="
echo "real content" > "${WORK}/src/target.conf"
ln -s target.conf "${WORK}/src/link.conf"
ln -s missing.conf "${WORK}/src/dangling.conf"
mkdir -p "${WORK}/src/realdir"; echo inner > "${WORK}/src/realdir/inner.conf"
ln -s realdir "${WORK}/src/linkdir"
# WORK は /tmp の下にあり、root 以外も書ける。そこにあるリンクはたどらない
# （root しか書けない場所かを、パスの見た目ではなく所有者と権限で見る）
safe_copy "${WORK}/src/link.conf" "${WORK}/s1/"
check_not "a link in a directory others can write is not followed" test -e "${WORK}/s1/link.conf"
check "... and is recorded in _symlinks.txt" grep -q 'link.conf -> target.conf: not followed' "${WORK}/s1/_symlinks.txt"
safe_copy "${WORK}/src/linkdir/" "${WORK}/s1/linkdir/"
check_not "a directory link with a trailing / is not followed there either" test -e "${WORK}/s1/linkdir/inner.conf"
: > "${LDIR_MODULE_LOG}"
check_not "a dangling link returns non-zero" safe_copy "${WORK}/src/dangling.conf" "${WORK}/s1/"
check "a dangling link is recorded" grep -q 'dangling.conf -> missing.conf: dangling' "${WORK}/s1/_symlinks.txt"
check_not "a dangling link is not a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"
if [[ ${EUID} -eq 0 ]]; then
    # / と TD は root のもので、root 以外は書けない: ここにあるリンクはたどる（/etc/resolv.conf の形）
    TD="$(mktemp -d /.ldir-unit.XXXXXX)"
    echo "real content" > "${TD}/target.conf"
    ln -s target.conf "${TD}/link.conf"
    printf -- '-----BEGIN PRIVATE KEY-----\ncanary-linkedkey\n-----END PRIVATE KEY-----\n' > "${TD}/key.pem"
    ln -s key.pem "${TD}/keylink.conf"
    mkfifo "${TD}/pipe"; ln -s pipe "${TD}/pipelink.conf"
    ln -s /dev/null "${TD}/nulllink.conf"
    safe_copy "${TD}/link.conf" "${WORK}/s2/"
    check "root-only location: a symlinked file is copied as its content, not as a link" bash -c "[[ -f '${WORK}/s2/link.conf' && ! -L '${WORK}/s2/link.conf' ]]"
    check "root-only location: the copy holds the target's content" grep -qx "real content" "${WORK}/s2/link.conf"
    check "root-only location: the link is recorded in _symlinks.txt" grep -q "link.conf -> target.conf: copied the target's content" "${WORK}/s2/_symlinks.txt"
    safe_copy "${TD}/keylink.conf" "${WORK}/s2/"
    check_not "root-only location: a link to a private key is not copied" grep -rq canary-linkedkey "${WORK}/s2"
    rc=0; timeout 20 bash -c "source '${TOOLKIT}/lib/common.sh'; safe_copy '${TD}/pipelink.conf' '${WORK}/s2/'" || rc=$?
    check "root-only location: a link to a FIFO does not hang (exit ${rc})" test "${rc}" -ne 124
    check_not "root-only location: ... and nothing is copied" test -e "${WORK}/s2/pipelink.conf"
    : > "${LDIR_MODULE_LOG}"
    safe_copy "${TD}/nulllink.conf" "${WORK}/s2/"
    check "a link to /dev/null is a WARN (what is written there is discarded)" grep -q '^\[WARN\].*nulllink.conf.*/dev/null' "${LDIR_MODULE_LOG}"
else
    echo "  skip - following links in root-only locations (needs root)"
fi

echo "== logging =="
log_warn "something odd"
check "log_warn reaches module log" grep -q '^\[WARN\].*something odd' "${LDIR_MODULE_LOG}"
check "log_warn reaches collection.log" grep -q '^\[WARN\].*something odd' "${OUTPUT_DIR}/metadata/collection.log"
check_not "no colour codes when not a TTY" grep -q $'\033' <(log_info "plain")

echo "== save_command_output =="
save_command_output "echo hello" "${WORK}/cmd/out.txt"
check "writes output and creates parent dir" grep -qx hello "${WORK}/cmd/out.txt"
check_not "failing command returns non-zero" save_command_output "false" "${WORK}/cmd/fail.txt"

echo "== redact_env =="
red() { printf '%s\n' "$1" | redact_env; }
check "masks *_TOKEN values" test "$(red 'GH_TOKEN=abc123')" = 'GH_TOKEN=<redacted:6 chars>'
check "masks *_SECRET_ACCESS_KEY values" test "$(red 'AWS_SECRET_ACCESS_KEY=x y')" = 'AWS_SECRET_ACCESS_KEY=<redacted:3 chars>'
check "masks lower-case names" test "$(red 'db_password=hunter2')" = 'db_password=<redacted:7 chars>'
check "keeps ordinary variables" test "$(red 'LANG=C.UTF-8')" = 'LANG=C.UTF-8'
check "masks plural *_TOKENS" test "$(red 'GITHUB_TOKENS=abc')" = 'GITHUB_TOKENS=<redacted:3 chars>'
check "masks TOKENS in the middle of a name" test "$(red 'API_TOKENS_FILE=abc')" = 'API_TOKENS_FILE=<redacted:3 chars>'
check "keeps LDIR_REDACT_SECRETS" test "$(red 'LDIR_REDACT_SECRETS=1')" = 'LDIR_REDACT_SECRETS=1'
check "masks TOKEN in the middle of a name" test "$(red 'MY_TOKEN_VALUE=abc')" = 'MY_TOKEN_VALUE=<redacted:3 chars>'
check "masks plural *_SECRETS" test "$(red 'CLIENT_SECRETS=x')" = 'CLIENT_SECRETS=<redacted:1 chars>'
check "keeps PWD" test "$(red 'PWD=/root')" = 'PWD=/root'
check "keeps OLDPWD" test "$(red 'OLDPWD=/tmp')" = 'OLDPWD=/tmp'
check "keeps SSH_AUTH_SOCK" test "$(red 'SSH_AUTH_SOCK=/run/agent.sock')" = 'SSH_AUTH_SOCK=/run/agent.sock'
check "keeps XDG_SESSION_ID" test "$(red 'XDG_SESSION_ID=42')" = 'XDG_SESSION_ID=42'
check "keeps empty secret as-is" test "$(red 'MY_PASSWORD=')" = 'MY_PASSWORD='
check "masks credentials inside URLs" test "$(red 'HTTPS_PROXY=http://bob:hunter2@proxy:3128/')" = 'HTTPS_PROXY=http://bob:<redacted>@proxy:3128/'
check "keeps URLs without credentials" test "$(red 'HTTP_PROXY=http://proxy:3128/')" = 'HTTP_PROXY=http://proxy:3128/'
check "masks docker-inspect style Env entries" test "$(red '    "DB_PASSWORD=s3cret",')" = '    "DB_PASSWORD=<redacted:6 chars>",'
check "keeps non-secret Env entries" test "$(red '    "PATH=/bin"')" = '    "PATH=/bin"'
check "passes through non-assignment lines" test "$(red 'just some text')" = 'just some text'
check "LDIR_REDACT_SECRETS=0 disables masking" test "$(printf 'GH_TOKEN=abc\n' | LDIR_REDACT_SECRETS=0 redact_env)" = 'GH_TOKEN=abc'

echo "== redact_config =="
rc_() { printf '%s\n' "$1" | redact_config; }
check "XML passwd attribute is masked" test "$(rc_ "<graphics type='vnc' passwd='s3cret' port='5900'/>")" = "<graphics type='vnc' passwd='<redacted:6 chars>' port='5900'/>"
check "XML password element is masked" test "$(rc_ '<password>hunter2</password>')" = '<password><redacted:7 chars></password>'
check "key = value is masked" test "$(rc_ 'vnc_password = "abc"')" = 'vnc_password = <redacted:5 chars>'
check "commented key = value is masked too" test "$(rc_ '#spice_password = "abc"')" = '#spice_password = <redacted:5 chars>'
# shellcheck disable=SC2016  # $5$ はパスワードハッシュの文字列
check "key: value (Proxmox cipassword) is masked" test "$(rc_ 'cipassword: $5$x$y')" = 'cipassword: <redacted:6 chars>'
check "public SSH keys are kept" test "$(rc_ 'sshkeys: ssh-rsa%20AAAA')" = 'sshkeys: ssh-rsa%20AAAA'
check "Proxmox user.cfg token lines are kept" test "$(rc_ 'token:root@pam!t1::0:')" = 'token:root@pam!t1::0:'
check "QEMU secret data= is masked" test "$(rc_ "<qemu:arg value='secret,id=s0,data=c2VjcmV0'/>")" = "<qemu:arg value='secret,id=s0,data=<redacted>'/>"
check "URL credentials are masked" test "$(rc_ 'source = rbd://admin:pw@mon/pool')" = 'source = rbd://admin:<redacted>@mon/pool'
check "JSON string value is masked" test "$(rc_ '"core.trust_password":"abc",')" = '"core.trust_password":"<redacted:3 chars>",'
check "JSON cloud-init user-data is masked" test "$(rc_ '"cloud-init.user-data":"#cloud-config\npassword: x",')" = '"cloud-init.user-data":"<redacted:26 chars>",'
check "JSON environment.* is masked" test "$(rc_ '"environment.FOO":"bar"}')" = '"environment.FOO":"<redacted:3 chars>"}'
check "ordinary values are kept" test "$(rc_ 'name: vm1')" = 'name: vm1'
out="$(printf 'user.user-data: |\n  #cloud-config\n  password: foo\nnext: kept\n' | redact_config)"
check "a YAML block under a secret key is masked as a whole" test "${out}" = "$(printf 'user.user-data: <redacted>\nnext: kept')"
out="$(printf '{"name":"c1","config":{"user.user-data":"x","limits.cpu":"2"}}' | ldir_json_split | redact_config | tr -d '\n')"
check "one-line JSON is split and masked" test "${out}" = '{"name":"c1","config":{"user.user-data":"<redacted:1 chars>","limits.cpu":"2"}}'
check "LDIR_REDACT_SECRETS=0 disables config masking" test "$(printf 'password = x\n' | LDIR_REDACT_SECRETS=0 redact_config)" = 'password = x'
# 名前と値が別の属性・値の中にある形（検証レポートの指摘 4）
check "XML name/value pair: qemu:env with a secret name is masked" \
    test "$(rc_ "<qemu:env name='DB_PASSWORD' value='s3cret'/>")" = "<qemu:env name='DB_PASSWORD' value='<redacted:6 chars>'/>"
check "XML name/value pair: an ordinary name is kept" \
    test "$(rc_ "<qemu:env name='LANG' value='C.UTF-8'/>")" = "<qemu:env name='LANG' value='C.UTF-8'/>"
check "XML name/value pair: the text of <initenv name=...> is masked" \
    test "$(rc_ "<initenv name='API_TOKEN'>abc</initenv>")" = "<initenv name='API_TOKEN'><redacted:3 chars></initenv>"
check "lxc.environment = NAME=value is masked by NAME" \
    test "$(rc_ 'lxc.environment = DB_PASSWORD=s3cret')" = 'lxc.environment = DB_PASSWORD=<redacted:6 chars>'
check "lxc.environment: NAME=value (Proxmox) is masked by NAME" \
    test "$(rc_ 'lxc.environment: DB_PASSWORD=s3cret')" = 'lxc.environment: DB_PASSWORD=<redacted:6 chars>'
check "lxc.environment with an ordinary NAME is kept" test "$(rc_ 'lxc.environment = TZ=UTC')" = 'lxc.environment = TZ=UTC'
check "the libvirt SASL database passwd.db is excluded by name" ldir_is_secret_path "etc/libvirt/passwd.db"
# ネットワークの設定（NetworkManager の psk=、WireGuard の PrivateKey= / PresharedKey=）
check "psk= is masked" test "$(rc_ 'psk=wifi-secret')" = 'psk=<redacted:11 chars>'
check "WireGuard PrivateKey= is masked" test "$(rc_ 'PrivateKey=abcd')" = 'PrivateKey=<redacted:4 chars>'
check "WireGuard PresharedKey= is masked" test "$(rc_ 'PresharedKey=abcd')" = 'PresharedKey=<redacted:4 chars>'

echo "== copy_config_tree: secrets are never written =="
T1="${WORK}/etc_ssh"; mkdir -p "${T1}/sshd_config.d" "${T1}/secrets"
echo "Port 22" > "${T1}/sshd_config"
echo "PasswordAuthentication no" > "${T1}/sshd_config.d/10.conf"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n' > "${T1}/ssh_host_ed25519_key"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nBBBB\n-----END OPENSSH PRIVATE KEY-----\n' > "${T1}/custom_hostkey"
echo "ssh-ed25519 AAAA" > "${T1}/ssh_host_ed25519_key.pub"
echo "c2VjcmV0" > "${T1}/secrets/abc.base64"
echo "<graphics passwd='pw'/>" > "${T1}/vm.xml"
ln -s sshd_config "${T1}/link"
printf -- '-----BEGIN PGP PRIVATE KEY BLOCK-----\nCCCC\n-----END PGP PRIVATE KEY BLOCK-----\n' > "${T1}/backup_signing.asc"
copy_config_tree "${T1}" "${WORK}/ct" "${WORK}/ct_excluded.txt" 1
check_not "a PGP private key block is not written (finding 12)" test -e "${WORK}/ct/backup_signing.asc"
check "config files are copied (sshd_config.d included)" test -f "${WORK}/ct/sshd_config.d/10.conf"
check "public keys are copied" test -f "${WORK}/ct/ssh_host_ed25519_key.pub"
check_not "a key named ssh_host_*_key is not written" test -e "${WORK}/ct/ssh_host_ed25519_key"
check_not "a private key with any other name is not written (content check)" test -e "${WORK}/ct/custom_hostkey"
check_not "secrets/ is not written" test -e "${WORK}/ct/secrets"
check "excluded files are listed" bash -c "grep -q 'custom_hostkey' '${WORK}/ct_excluded.txt' && grep -q 'abc.base64' '${WORK}/ct_excluded.txt'"
check "symlinks are recorded, not followed" grep -q $'^symlink\t.*link -> sshd_config' "${WORK}/ct_excluded.txt"
check "redact=1 masks values in copied files" grep -q "passwd='<redacted:2 chars>'" "${WORK}/ct/vm.xml"
check_not "no private key material anywhere in the copy" grep -rq 'PRIVATE KEY' "${WORK}/ct"

echo "== user home directories =="
H="${WORK}/homes"; mkdir -p "${H}/root" "${H}/home/alice" "${H}/home/ghost" "${H}/srv/svc"
{
    # ラベルはホームのディレクトリの持ち主のアカウント（指摘 10）。テストではディレクトリの持ち主が
    # 実行ユーザーなので、root と svc の uid をそれに合わせる
    echo "root:x:$(id -u):0:root:${H}/root:/bin/bash"
    echo "operator:x:11:0:operator:${H}/root:/sbin/nologin"
    echo "alice:x:1000:1000::${H}/home/alice/:/bin/bash"
    echo "svc:x:$(id -u):999::${H}/srv/svc:/usr/sbin/nologin"
    echo "nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin"
} > "${WORK}/passwd"
homes="$(ldir_compute_user_homes "${WORK}/passwd" "${H}/root" "${H}/home/alice" "${H}/home/ghost")"
check "service account home outside /home is included" grep -q $'^svc\t'"${H}/srv/svc"$'\tpasswd\tsvc$' <<< "${homes}"
check "a shared home is listed once" test "$(grep -c "${H}/root" <<< "${homes}")" -eq 1
check "... under the first user" grep -q $'^root\t'"${H}/root"$'\t' <<< "${homes}"
check "a trailing slash in passwd does not duplicate the home" test "$(grep -c "${H}/home/alice" <<< "${homes}")" -eq 1
check "a home without a passwd entry is marked orphan" grep -q $'^orphan-home_ghost\t'"${H}/home/ghost"$'\torphan\t$' <<< "${homes}"
check "the accounts sharing a home are listed (root and operator share /root)" grep -q $'^root\t'"${H}/root"$'\tpasswd\troot,operator$' <<< "${homes}"
check_not "a non-existent home is skipped" grep -q nonexistent <<< "${homes}"
check "LDIR_USER_HOMES is used when set" test "$(LDIR_USER_HOMES=$'x\t/y\tpasswd' ldir_user_homes)" = $'x\t/y\tpasswd'
# ホームが / のように、どのアカウントの持ち物でもないホームを複数のアカウントが共有している場合、
# passwd で先に出てくる名前をラベルにすると、別の利用者の履歴に名前が付く（指摘 10）
mkdir -p "${WORK}/sharedhome"
{
    echo "svc-a:x:60001:60001::${WORK}/sharedhome:/usr/sbin/nologin"
    echo "svc-b:x:60002:60002::${WORK}/sharedhome:/usr/sbin/nologin"
} > "${WORK}/passwd_shared"
homes="$(ldir_compute_user_homes "${WORK}/passwd_shared" "${WORK}/no-such-dir")"
check_not "a home owned by none of its accounts is not labelled after the first account (finding 10)" grep -q $'^svc-a\t' <<< "${homes}"

echo "== log period and size cap: settings =="
NOW=1800000000
settings() {
    (
        LDIR_MODE="$1" LDIR_LOG_DAYS="$2" LDIR_LOG_MAX_MB="$3" LDIR_LOG_CMD_TIMEOUT=""
        if ldir_resolve_log_settings "${NOW}"; then
            echo "${LDIR_LOG_DAYS} ${LDIR_LOG_SINCE_EPOCH} ${LDIR_LOG_MAX_MB}"
        else
            echo "ERR ${LDIR_SETTINGS_ERROR}"
        fi
    )
}
check "fast default: 30 days, 100 MB" test "$(settings fast "" "")" = "30 $((NOW - 30 * 86400)) 100"
for d in 30 60 90; do
    check "accepts --log-days ${d}" test "$(settings fast "${d}" "")" = "${d} $((NOW - d * 86400)) 100"
done
for d in 7 45 120 0 -30 abc 30d " 30" 030; do
    out="$(settings fast "${d}" "")"
    check "rejects --log-days '${d}'" test "${out#ERR }" != "${out}"
done
check "full default: no period, no cap" test "$(settings full "" "")" = "unlimited 0 0"
check "full with --log-days follows it" test "$(settings full 60 "")" = "60 $((NOW - 60 * 86400)) 0"
check "full with --log-max-mb follows it" test "$(settings full "" 50)" = "unlimited 0 50"
check "--log-max-mb 0 means no cap" test "$(settings fast "" 0)" = "30 $((NOW - 30 * 86400)) 0"
for m in abc -1 1.5 99999999; do
    out="$(settings fast "" "${m}")"
    check "rejects --log-max-mb '${m}'" test "${out#ERR }" != "${out}"
done
# バイナリの journal は journald の既定で 1 ファイル 128 MB まで育つ。ログ群の既定 100 MB では
# 最新のファイルが必ず超えるので、別の上限を持つ（指摘 5）
jset() {
    (
        LDIR_MODE="$1" LDIR_JOURNAL_MAX_MB="$2" LDIR_LOG_DAYS="" LDIR_LOG_MAX_MB="" LDIR_LOG_CMD_TIMEOUT=""
        if ldir_resolve_log_settings "${NOW}"; then echo "${LDIR_JOURNAL_MAX_MB:-unset}"; else echo ERR; fi
    )
}
check "binary journal has its own cap: fast default 256 MB" test "$(jset fast "")" = 256
check "binary journal cap: full default is no cap" test "$(jset full "")" = 0
check "binary journal cap: an explicit value is used" test "$(jset fast 50)" = 50
check "binary journal cap: a non-number is rejected" test "$(jset fast abc)" = ERR

echo "== log period and size cap: collection =="
# 期間の始まりを 2020-06-01 に固定し、更新日時は touch -t で与える（date -d に依存しない）
LG="${WORK}/varlog"; mkdir -p "${LG}/nginx" "${LG}/old_only"
head -c 409600 /dev/zero > "${LG}/nginx/access.log";      touch -t 202101050000 "${LG}/nginx/access.log"
head -c 409600 /dev/zero > "${LG}/nginx/access.log.1";    touch -t 202101040000 "${LG}/nginx/access.log.1"
head -c 409600 /dev/zero > "${LG}/nginx/access.log.2.gz"; touch -t 202101030000 "${LG}/nginx/access.log.2.gz"
head -c 102400 /dev/zero > "${LG}/nginx/access.log.3.gz"; touch -t 202101020000 "${LG}/nginx/access.log.3.gz"
head -c 1000   /dev/zero > "${LG}/nginx/access.log.4.gz"; touch -t 202001010000 "${LG}/nginx/access.log.4.gz"
echo old > "${LG}/old_only/auth.log.9.gz";                touch -t 201901010000 "${LG}/old_only/auth.log.9.gz"
printf 'gz-bytes\001\002' > "${LG}/nginx/x.gz";           touch -t 202101060000 "${LG}/nginx/x.gz"
ln -s /dev/stdout "${LG}/nginx/error.log"
# 改行を含むファイル名（指摘 11）、/dev/null へのリンク（ログを捨てている）
echo "odd" > "${LG}/nginx/evil${NL}name.log";            touch -t 202101060000 "${LG}/nginx/evil${NL}name.log"
ln -s /dev/null "${LG}/nginx/discard.log"
# 最新のファイルが上限を超える群（指摘 5）
mkdir -p "${LG}/apache2"
head -c 2097152 /dev/zero > "${LG}/apache2/access.log";  touch -t 202101050000 "${LG}/apache2/access.log"
echo small > "${LG}/apache2/error.log.1";                 touch -t 202101040000 "${LG}/apache2/error.log.1"
# root 以外も書ける場所にあるディレクトリへのリンク（/var/log/mysql -> /root の形）
mkdir -p "${WORK}/outside_logs"; echo canary-linkedlog > "${WORK}/outside_logs/x.log"
ln -s "${WORK}/outside_logs" "${LG}/mysql"
LDST="${WORK}/logs_out"
: > "${LDIR_MODULE_LOG}"
(
    LDIR_LOG_SINCE_EPOCH=1590969600 LDIR_LOG_DAYS=30 LDIR_LOG_SINCE="2020-06-01 00:00:00" LDIR_LOG_MAX_MB=1
    collect_log_group web "${LG}" "${LDST}" "${LDST}" 'nginx'
    collect_log_group auth "${LG}" "${LDST}" "${LDST}" 'old_only/auth.log*'
    collect_log_group mail "${LG}" "${LDST}" "${LDST}" 'mail.log*'
    collect_log_group web_apache "${LG}" "${LDST}" "${LDST}" 'apache2'
    collect_log_group db_mysql "${LG}" "${LDST}" "${LDST}" 'mysql'
)
check "a file name with a newline is collected whole (finding 11)" test -f "${LDST}/nginx/evil${NL}name.log"
check "... its inventory line is not split (the newline is written as \\n)" grep -q $'\tcollected\t.*evil\\\\nname.log$' "${LDST}/log_inventory.tsv"
check_not "... and it is not reported as copy_failed" grep -q $'\tcopy_failed\t' "${LDST}/log_inventory.tsv"
check "a log linked to /dev/null is a WARN" grep -q '^\[WARN\].*\[web\].*discard.log.*/dev/null' "${LDIR_MODULE_LOG}"
check "newest file over the cap: status newest_over_cap, not capped (finding 5)" grep -qE '^web_apache +newest_over_cap ' "${LDST}/log_summary.txt"
check "... the WARN says that nothing of the group was collected" grep -q '^\[WARN\].*\[web_apache\].*newest file.*nothing' "${LDIR_MODULE_LOG}"
check_not "a directory link in a location others can write is not followed" test -e "${LDST}/mysql/x.log"
check "... it is listed as a symlink that was not followed" grep -q $'^db_mysql\tsymlink_not_followed\t.*mysql -> ' "${LDST}/log_inventory.tsv"
INV="${LDST}/log_inventory.tsv"; SUM="${LDST}/log_summary.txt"
check "newest file is collected" test -f "${LDST}/nginx/access.log"
check "rotated file within the cap is collected" test -f "${LDST}/nginx/access.log.1"
# cmp は diffutils に入っていて、最小構成のイメージには無い。sha256sum は必須コマンド
check "compressed file is copied as-is (same bytes, not expanded)" \
    test "$(sha256sum < "${LG}/nginx/x.gz")" = "$(sha256sum < "${LDST}/nginx/x.gz" 2>/dev/null)"
check_not "file that would exceed the cap is not collected" test -e "${LDST}/nginx/access.log.2.gz"
check_not "older files after the cut are not collected either (contiguous range)" test -e "${LDST}/nginx/access.log.3.gz"
check "over-cap files are listed in the inventory" grep -q $'\tover_cap\t.*access.log.2.gz' "${INV}"
check "... all of them" grep -q $'\tover_cap\t.*access.log.3.gz' "${INV}"
check "reaching the cap is a WARN" grep -q '^\[WARN\].*\[web\] log size cap of 1 MB reached: 2 older file' "${LDIR_MODULE_LOG}"
check "the summary says capped" grep -qE '^web +capped ' "${SUM}"
check_not "a file older than the period is not collected" test -e "${LDST}/nginx/access.log.4.gz"
check "it is listed as older_than_period" grep -q $'\tolder_than_period\t.*access.log.4.gz' "${INV}"
check "mtime is preserved on copy" test "$(stat -c %Y "${LDST}/nginx/access.log")" = "$(stat -c %Y "${LG}/nginx/access.log")"
check_not "symlinks (-> /dev/stdout) are not followed" test -e "${LDST}/nginx/error.log"
check "symlinks are listed" grep -q $'\tsymlink_not_followed\t.*error.log -> /dev/stdout' "${INV}"
check "logs that exist only outside the period: none_in_period" grep -qE '^auth +none_in_period ' "${SUM}"
check "logs that do not exist at all: not_present" grep -qE '^mail +not_present ' "${SUM}"
check "not_present is also in the inventory" grep -q $'^mail\tnot_present\t' "${INV}"
check_not "none_in_period / not_present are not WARNs" grep -qE '^\[WARN\].*\[(auth|mail)\]' "${LDIR_MODULE_LOG}"
check "the summary states the period" grep -q '^Log period : last 30 days' "${SUM}"
check "the summary states the cap" grep -q '^Size cap   : 1 MB per log group' "${SUM}"
check_not "no temporary files are left behind" bash -c "ls -A '${LDST}' | grep -q 'loggroup.tmp'"
(
    LDIR_LOG_SINCE_EPOCH=0 LDIR_LOG_MAX_MB=0
    collect_log_group web "${LG}" "${WORK}/logs_all" "${WORK}/logs_all" 'nginx'
)
check "no period and no cap: every file is collected" test "$(find "${WORK}/logs_all/nginx" -type f -exec printf x \; | wc -c)" -eq 7

echo "== capture =="
capture "${WORK}/cap/ok.txt" echo captured
check "saves output and creates parent dir" grep -qx captured "${WORK}/cap/ok.txt"
: > "${LDIR_MODULE_LOG}"
capture "${WORK}/cap/fail.txt" sh -c 'echo oops >&2; exit 3'
check "failing command is a WARN with its exit code" grep -q '^\[WARN\].*exit 3' "${LDIR_MODULE_LOG}"
check "failing command's stderr is kept in the file" grep -qx oops "${WORK}/cap/fail.txt"
: > "${LDIR_MODULE_LOG}"
capture "${WORK}/cap/missing.txt" ldir-no-such-command-xyz
check_not "missing command is not a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"
check "missing command is noted in the file" grep -q 'not available' "${WORK}/cap/missing.txt"
: > "${LDIR_MODULE_LOG}"
capture_try "${WORK}/cap/try.txt" false || capture "${WORK}/cap/try.txt" echo fallback
check "capture_try failure is silent when a fallback follows" test ! -s "${LDIR_MODULE_LOG}"
check "fallback output wins" grep -qx fallback "${WORK}/cap/try.txt"
# 直書きの「> 収集先 2>&1」（末尾の || true を含む）は失敗が manifest に現れない。
# 失敗を記録しないのが正しい箇所は、行末に # ldir:allow を付けて理由をコメントする
unchecked="$(grep -nE '> "\$\{[A-Za-z_]+\}/[^"]*" 2>&1' "${TOOLKIT}"/modules/*.sh | grep -v 'ldir:allow')"
check "modules contain no unchecked '> file 2>&1' collection commands" test -z "${unchecked}"
[[ -z "${unchecked}" ]] || echo "${unchecked}" | sed 's/^/         /'
: > "${LDIR_MODULE_LOG}"
capture "${WORK}/cap/slow.txt" run_limited 1 sleep 5
check "a timed-out capture says so in the WARN" grep -q '^\[WARN\].*timed out after 1s' "${LDIR_MODULE_LOG}"
check "run_limited 0 means no time limit" run_limited 0 true
rc=0; run_limited 1 sleep 5 || rc=$?
check "run_limited reports a timeout as 124 (GNU and BusyBox timeout alike; got ${rc})" test "${rc}" -eq 124
: > "${LDIR_MODULE_LOG}"
capture_partial "${WORK}/cap/partial.txt" sh -c 'echo some; exit 1'
check_not "capture_partial: failure with output is not a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"
capture_partial "${WORK}/cap/partial2.txt" sh -c 'exit 1'
check "capture_partial: failure without output is a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"
: > "${LDIR_MODULE_LOG}"
CONTAINER_TYPE=docker capture_host "${WORK}/cap/host.txt" sh -c 'echo denied; exit 1'
check_not "capture_host: failure inside a container is not a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"
check "capture_host: the file says why" grep -q 'inside a container' "${WORK}/cap/host.txt"
CONTAINER_TYPE=none capture_host "${WORK}/cap/host2.txt" sh -c 'exit 1'
check "capture_host: failure on a host is a WARN" grep -q '^\[WARN\]' "${LDIR_MODULE_LOG}"

echo "== run_limited =="
check "runs a command" run_limited 5 true
check_not "propagates failure" run_limited 5 false

echo "== distro detection =="
# shellcheck source=ldir-toolkit/lib/detect_distro_advanced.sh
source "${TOOLKIT}/lib/detect_distro_advanced.sh"

# Arch 相当: VERSION_ID が無い。Ubuntu 相当: VERSION を定義している。
printf 'NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling\n' > "${WORK}/os-arch"
printf 'NAME="Ubuntu"\nVERSION="24.04 LTS (Noble)"\nID=ubuntu\nVERSION_ID="24.04"\n' > "${WORK}/os-ubuntu"

VERSION="keep-me"
NAME="keep-me-too"
LDIR_OS_RELEASE="${WORK}/os-ubuntu" detect_distribution_advanced
check "does not clobber caller's VERSION" test "${VERSION}" = "keep-me"
check "does not clobber caller's NAME" test "${NAME}" = "keep-me-too"
check "reads NAME" test "${DISTRO_NAME}" = "Ubuntu"
check "reads VERSION_ID" test "${DISTRO_VERSION}" = "24.04"

out="$(set -euo pipefail; LDIR_OS_RELEASE="${WORK}/os-arch" detect_distribution_advanced; echo "${DISTRO_VERSION}")"
check "missing VERSION_ID survives set -u (falls back to BUILD_ID)" test "${out}" = "rolling"

out="$(set -euo pipefail; LDIR_OS_RELEASE="${WORK}/does-not-exist" detect_distribution_advanced; echo "${DISTRO_NAME}")"
check "missing os-release survives set -e" test -n "${out}"

check "detect_all runs under set -euo pipefail" bash -c "set -euo pipefail; source '${TOOLKIT}/lib/common.sh'; source '${TOOLKIT}/lib/detect_distro_advanced.sh'; detect_all"

echo "== virtualization detection =="
vdetect() {
    (
        LDIR_VIRT_ROOT="$1"
        detect_virtualization
        echo "${VIRT_TYPE}|${VIRT_SOURCE}"
    )
}
mkvroot() {   # mkvroot <dir> <sys_vendor|-> <product_name|-> <cpuinfo flags|->
    mkdir -p "$1/proc"
    if [[ "$2" != "-" ]]; then
        mkdir -p "$1/sys/class/dmi/id"
        echo "$2" > "$1/sys/class/dmi/id/sys_vendor"
        echo "$3" > "$1/sys/class/dmi/id/product_name"
    fi
    [[ "$4" != "-" ]] && printf 'processor\t: 0\nflags\t\t: %s\n' "$4" > "$1/proc/cpuinfo"
    return 0
}
mkvroot "${WORK}/vr_qemu" QEMU "Standard PC (Q35 + ICH9, 2009)" "fpu vme hypervisor sse"
check "DMI QEMU -> qemu" test "$(vdetect "${WORK}/vr_qemu")" = "qemu|dmi: QEMU / Standard PC (Q35 + ICH9, 2009)"
mkvroot "${WORK}/vr_vmw" "VMware, Inc." "VMware Virtual Platform" -
check "DMI VMware -> vmware" test "$(vdetect "${WORK}/vr_vmw" | cut -d'|' -f1)" = "vmware"
mkvroot "${WORK}/vr_flag" - - "fpu vme hypervisor sse"
check "only the cpuinfo flag -> a VM of unknown type" test "$(vdetect "${WORK}/vr_flag" | cut -d'|' -f1)" = "vm-unknown-hypervisor"
mkvroot "${WORK}/vr_metal" "Dell Inc." "PowerEdge R640" "fpu vme sse"
check "physical DMI and no hypervisor flag -> none" test "$(vdetect "${WORK}/vr_metal" | cut -d'|' -f1)" = "none"
mkvroot "${WORK}/vr_ec2metal" "Amazon EC2" "m5.metal" "fpu vme sse"
check "EC2 bare metal -> none" test "$(vdetect "${WORK}/vr_ec2metal" | cut -d'|' -f1)" = "none"
mkvroot "${WORK}/vr_ec2" "Amazon EC2" "m5.large" "fpu hypervisor"
check "EC2 instance -> amazon" test "$(vdetect "${WORK}/vr_ec2" | cut -d'|' -f1)" = "amazon"
mkdir -p "${WORK}/vr_empty"
check "no detection source -> unknown (does not fail)" test "$(vdetect "${WORK}/vr_empty")" = "unknown|no usable detection source"

echo "== 35_virtualization module =="
# 必要最小限のコマンドだけを置いた PATH で動かす（virsh 等が手元に入っていても影響されない）
MINBIN="${WORK}/minbin"; mkdir -p "${MINBIN}"
for c in bash sh cat sort grep awk sed find stat ls mkdir cp rm mv touch date tr head tail wc \
         readlink dirname basename timeout env cut uniq comm xargs sleep id; do
    p="$(command -v "$c" 2>/dev/null)" && [[ "$p" = /* ]] && ln -sf "$p" "${MINBIN}/$c"
done
VMOD="${TOOLKIT}/modules/35_virtualization.sh"
# run_virt <ルート> <出力> [追加の PATH] [環境変数...]
run_virt() {
    local root="$1" out="$2" xpath="${3:-}"
    shift 3
    mkdir -p "${out}/metadata"
    env -i PATH="${xpath}${xpath:+:}${MINBIN}" LDIR_VIRT_ROOT="${root}" LDIR_MODE=fast \
        LDIR_MODULE_LOG="${out}/module.log" "$@" "${MINBIN}/bash" "${VMOD}" "${out}" > "${out}/stdout.txt" 2>&1
}

rc=0; run_virt "${WORK}/vr_empty" "${WORK}/vo_empty" "" || rc=$?
check "nothing to find: the module exits 0" test "${rc}" -eq 0
check "nothing to find: no_hypervisor_detected.txt says so" grep -q 'No hypervisor' "${WORK}/vo_empty/virtualization/no_hypervisor_detected.txt"
check "nothing to find: guest detection is still recorded" grep -q '^Result: unknown' "${WORK}/vo_empty/virtualization/guest/virt_detection.txt"
check_not "nothing to find: no WARN" grep -q '^\[WARN\]' "${WORK}/vo_empty/module.log"
check_not "nothing to find: no host/ directory" test -e "${WORK}/vo_empty/virtualization/host"

# libvirt のモック: 設定ファイル、鍵、ソケット、ログ、ディスクイメージ、virsh
VL="${WORK}/vr_libvirt"
mkdir -p "${VL}/etc/libvirt/qemu" "${VL}/etc/libvirt/secrets" "${VL}/run/libvirt" \
         "${VL}/var/log/libvirt/qemu" "${VL}/var/lib/libvirt/images" "${VL}/proc"
echo "<domain><name>vm1</name><graphics type='vnc' passwd='canary-vncpw'/></domain>" > "${VL}/etc/libvirt/qemu/vm1.xml"
# 指摘 4: 環境変数の秘匿値（名前と値が別の属性）、LXC の lxc.environment、SASL のパスワード DB
echo "  <qemu:env name='DB_PASSWORD' value='canary-qemuenv'/>" >> "${VL}/etc/libvirt/qemu/vm1.xml"
printf 'canary-saslpw' > "${VL}/etc/libvirt/passwd.db"
mkdir -p "${VL}/var/lib/lxc/web1"
echo "lxc.environment = DB_PASSWORD=canary-lxcenv" > "${VL}/var/lib/lxc/web1/config"
echo 'vnc_password = "canary-globalpw"' > "${VL}/etc/libvirt/qemu.conf"
echo "canary-secretvalue" > "${VL}/etc/libvirt/secrets/0f0f.base64"
: > "${VL}/run/libvirt/libvirt-sock"
echo "qemu log line" > "${VL}/var/log/libvirt/qemu/vm1.log"
head -c 4096 /dev/zero > "${VL}/var/lib/libvirt/images/vm1.qcow2"
MOCK="${WORK}/mockbin"; mkdir -p "${MOCK}"
cat > "${MOCK}/virsh" << 'MOCKEOF'
#!/bin/sh
case "$1" in
    version)  [ -n "$MOCK_HANG" ] && sleep 10; echo "Compiled against library: libvirt 9.0.0" ;;
    uri)      echo "qemu:///system" ;;
    nodeinfo) echo "CPU(s): 4" ;;
    list)     case "$*" in *--uuid*) echo "11111111-2222-3333-4444-555555555555"; echo "" ;;
                               *) echo " Id   Name   State"; echo " 1    vm1    running" ;; esac ;;
    net-list) case "$*" in *--name*) echo "default" ;; *) echo " default active" ;; esac ;;
    # libvirt 9.0 は --name の出力の後ろに空白を詰める（指摘 8）
    pool-list) case "$*" in *--name*) echo "images              " ;; *) echo " images active" ;; esac ;;
    secret-list) echo " 0f0f  volume /var/lib/libvirt/images/vm1.qcow2" ;;
    dominfo)  echo "Name: vm1" ;;
    dumpxml)  echo "<domain><graphics type='spice' passwd='canary-livepw'/><qemu:env name='API_TOKEN' value='canary-liveenv'/></domain>" ;;
    domblklist) printf ' Type   Device   Target   Source\n------------------------------------\n file   disk     vda      /var/lib/libvirt/images/vm1.qcow2\n file   cdrom    sda      -\n' ;;
    domiflist) echo " vnet0 network default virtio" ;;
    snapshot-list) case "$*" in *--name*) echo "before upgrade" ;; *) echo " before upgrade  2026-01-01" ;; esac ;;
    snapshot-dumpxml) echo "<domainsnapshot><domain><graphics passwd='canary-snappw'/></domain></domainsnapshot>" ;;
    net-dumpxml) echo "<network><name>default</name></network>" ;;
    net-dhcp-leases) echo " 52:54:00:00:00:01 192.168.122.10" ;;
    pool-dumpxml) [ "$2" = images ] || { echo "error: Storage pool not found: $2" >&2; exit 1; }; echo "<pool type='dir'/>" ;;
    pool-info) echo "State:          running" ;;
    vol-list) [ "$2" = images ] && [ -z "$MOCK_VOLFAIL" ] || { echo "error: failed to get pool $2" >&2; exit 1; }; echo " vm1.qcow2" ;;
    *) echo "mock virsh: unknown $1" >&2; exit 1 ;;
esac
MOCKEOF
chmod +x "${MOCK}/virsh"
rc=0; run_virt "${VL}" "${WORK}/vo_lv" "${MOCK}" || rc=$?
LV="${WORK}/vo_lv/virtualization/host/libvirt"
UUID=11111111-2222-3333-4444-555555555555
check "libvirt (mock): the module exits 0" test "${rc}" -eq 0
check "libvirt (mock): persistent VM definitions are copied" test -f "${LV}/etc_libvirt/qemu/vm1.xml"
check "libvirt (mock): VNC password in a definition is masked" grep -q "passwd='<redacted:12 chars>'" "${LV}/etc_libvirt/qemu/vm1.xml"
check "libvirt (mock): qemu.conf password is masked" grep -q '^vnc_password = <redacted' "${LV}/etc_libvirt/qemu.conf"
check_not "libvirt (mock): /etc/libvirt/secrets is not copied" test -e "${LV}/etc_libvirt/secrets"
check "libvirt (mock): the excluded secret is listed" grep -q '0f0f.base64' "${WORK}/vo_lv/virtualization/excluded_files.txt"
check "libvirt (mock): live domain XML is saved" test -f "${LV}/domains/${UUID}/domain.xml"
check "libvirt (mock): a snapshot name with a space is kept whole" test -f "${LV}/domains/${UUID}/snapshot_before_upgrade.xml"
check "libvirt (mock): disk image path and size, not content" grep -q "4096 .*vm1.qcow2" "${LV}/disk_images.txt"
check_not "libvirt (mock): disk image content is not copied" bash -c "find '${WORK}/vo_lv' -name vm1.qcow2 | grep -q ."
check "libvirt (mock): network DHCP leases" grep -q 192.168.122.10 "${LV}/networks/default.dhcp_leases.txt"
check "libvirt (mock): libvirt logs follow the log rules" test -f "${LV}/logs/qemu/vm1.log"
check "libvirt (mock): ... and appear in the log summary" grep -qE '^libvirt +collected ' "${WORK}/vo_lv/virtualization/log_summary.txt"
check_not "libvirt (mock): no secret value anywhere in the output" grep -rqE 'canary-(vncpw|globalpw|secretvalue|livepw|snappw|qemuenv|liveenv|saslpw|lxcenv)' "${WORK}/vo_lv/virtualization"
check_not "libvirt (mock): no WARN" grep -q '^\[WARN\]' "${WORK}/vo_lv/module.log"
check "libvirt (mock): a pool name padded with spaces is trimmed (finding 8)" test -s "${LV}/storage_pools/images.xml"
check "libvirt (mock): ... and its volume list is collected" grep -q vm1.qcow2 "${LV}/storage_pools/images.volumes.txt"
rc=0; run_virt "${VL}" "${WORK}/vo_volfail" "${MOCK}" MOCK_VOLFAIL=1 || rc=$?
check "libvirt (mock): a failing vol-list on a running pool is a WARN (finding 8)" grep -q '^\[WARN\].*vol-list' "${WORK}/vo_volfail/module.log"
check "libvirt (mock): LXC lxc.environment secret is masked in the container config (finding 4)" \
    grep -q '^lxc.environment = DB_PASSWORD=<redacted' "${LV%/libvirt}/lxc/containers/web1.config"
check_not "libvirt (mock): no_hypervisor_detected.txt is not written" test -e "${WORK}/vo_lv/virtualization/no_hypervisor_detected.txt"

start=${SECONDS}
rc=0; run_virt "${VL}" "${WORK}/vo_hang" "${MOCK}" MOCK_HANG=1 LDIR_VIRT_TIMEOUT=1 || rc=$?
check "libvirt (hanging virsh): the module exits 0" test "${rc}" -eq 0
check "libvirt (hanging virsh): finishes within the timeout, not after 10s" test $(( SECONDS - start )) -lt 8
check "libvirt (hanging virsh): it is a WARN" grep -q '^\[WARN\].*timed out after 1s: virsh version' "${WORK}/vo_hang/module.log"
check "libvirt (hanging virsh): files are still copied" test -f "${WORK}/vo_hang/virtualization/host/libvirt/etc_libvirt/qemu/vm1.xml"

# Proxmox VE のモック: /etc/pve（priv/ と *.key を含む）、タスクログ、アクセスログ
VP="${WORK}/vr_pve"
mkdir -p "${VP}/etc/pve/priv" "${VP}/etc/pve/nodes/n1/qemu-server" "${VP}/var/log/pve/tasks/A" "${VP}/var/log/pveproxy" "${VP}/proc"
echo "canary-authkey" > "${VP}/etc/pve/priv/authkey.key"
echo "root:canary-shadow" > "${VP}/etc/pve/priv/shadow.cfg"
printf -- '-----BEGIN PRIVATE KEY-----\ncanary-sslkey\n-----END PRIVATE KEY-----\n' > "${VP}/etc/pve/nodes/n1/pve-ssl.key"
printf -- '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n' > "${VP}/etc/pve/nodes/n1/pve-ssl.pem"
printf 'name: vm100\ncipassword: canary-cipw\nsshkeys: ssh-ed25519%%20AAAA\n\n[snap1]\ncipassword: canary-cipw-snap\n' \
    > "${VP}/etc/pve/nodes/n1/qemu-server/100.conf"
mkdir -p "${VP}/etc/pve/nodes/n1/lxc"
echo "lxc.environment: DB_PASSWORD=canary-pveenv" > "${VP}/etc/pve/nodes/n1/lxc/101.conf"
ln -s nodes/n1/qemu-server "${VP}/etc/pve/qemu-server"
echo "task log" > "${VP}/var/log/pve/tasks/A/UPID:n1:0000:0000:65000000:qmstart:100:root@pam:"
echo "GET /api2/json" > "${VP}/var/log/pveproxy/access.log"
printf '#!/bin/sh\necho "VMID NAME STATUS"\necho " 100 vm100 running"\n' > "${MOCK}/qm"
chmod +x "${MOCK}/qm"
rc=0; run_virt "${VP}" "${WORK}/vo_pve" "${MOCK}" || rc=$?
PV="${WORK}/vo_pve/virtualization/host/proxmox"
check "Proxmox (mock): the module exits 0" test "${rc}" -eq 0
check "Proxmox (mock): VM definitions are copied" test -f "${PV}/etc_pve/nodes/n1/qemu-server/100.conf"
check "Proxmox (mock): cipassword is masked (snapshots too)" test "$(grep -c '^cipassword: <redacted' "${PV}/etc_pve/nodes/n1/qemu-server/100.conf")" -eq 2
check "Proxmox (mock): public SSH keys are kept" grep -q '^sshkeys: ssh-ed25519' "${PV}/etc_pve/nodes/n1/qemu-server/100.conf"
check_not "Proxmox (mock): priv/ is not copied" test -e "${PV}/etc_pve/priv"
check_not "Proxmox (mock): the node's TLS private key is not copied" test -e "${PV}/etc_pve/nodes/n1/pve-ssl.key"
check "Proxmox (mock): the node's certificate is copied" test -f "${PV}/etc_pve/nodes/n1/pve-ssl.pem"
check "Proxmox (mock): qm list" grep -q vm100 "${PV}/qm_list.txt"
check "Proxmox (mock): task logs" test -f "${PV}/tasks/A/UPID:n1:0000:0000:65000000:qmstart:100:root@pam:"
check "Proxmox (mock): API access log" test -f "${PV}/pveproxy/access.log"
check_not "Proxmox (mock): no secret value anywhere in the output" grep -rqE 'canary-(authkey|shadow|sslkey|cipw|pveenv)' "${WORK}/vo_pve/virtualization"

# Incus のモック: API ソケットと curl。user-data と environment.* を伏せる
VI="${WORK}/vr_incus"
mkdir -p "${VI}/var/lib/incus" "${VI}/proc"
: > "${VI}/var/lib/incus/unix.socket"
cat > "${MOCK}/curl" << 'MOCKEOF'
#!/bin/sh
for a; do url="$a"; done
case "$url" in
    */1.0) echo '{"type":"sync","metadata":{"config":{"core.trust_password":true},"api_version":"1.0"}}' ;;
    */1.0/instances*) echo '{"type":"sync","metadata":[{"name":"c1","config":{"cloud-init.user-data":"#cloud-config\npassword: canary-ud","environment.DB_PASS":"canary-env","security.privileged":"true"}}]}' ;;
    *) echo '{"type":"sync","metadata":[]}' ;;
esac
MOCKEOF
chmod +x "${MOCK}/curl"
rc=0; run_virt "${VI}" "${WORK}/vo_incus" "${MOCK}" || rc=$?
IV="${WORK}/vo_incus/virtualization/host/incus"
check "Incus (mock): the module exits 0" test "${rc}" -eq 0
check "Incus (mock): instances are listed" grep -q '"name":"c1"' "${IV}/instances.json"
check "Incus (mock): security settings are kept" grep -q '"security.privileged":"true"' "${IV}/instances.json"
check_not "Incus (mock): user-data and environment values are masked" grep -rqE 'canary-(ud|env)' "${WORK}/vo_incus/virtualization"
check "Incus (mock): trusted certificates are listed" test -f "${IV}/certificates.json"

echo "== user homes: links, FIFOs and devices are not followed (findings 1, 2, 7) =="
# 対象ホストの一般ユーザーは、自分のホームに何でも置ける。root で動く収集がそれをたどると、
# 読めないはずのファイルが収集物に入り、FIFO で止まり、/dev/zero で出力先が埋まる。
# モジュールは 60 秒とファイルサイズ 40 MB の上限を付けて動かす（直っていないと永久に止まる・埋まるため）
TR="${WORK}/trap"
mkdir -p "${TR}/outside" "${TR}/home/bob/.ssh" "${TR}/home/bob/.config/autostart" "${TR}/home/bob/.VirtualBox" "${TR}/home/carol"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\ncanary-userkey\n-----END OPENSSH PRIVATE KEY-----\n' > "${TR}/outside/id_ed25519"
echo "canary-rootonly" > "${TR}/outside/root_only.txt"
echo "canary-rootonly-ak" > "${TR}/outside/authorized_keys"
mkfifo "${TR}/outside/x.fifo"
B="${TR}/home/bob"
ln -s ../../../outside/id_ed25519 "${B}/.ssh/known_hosts"
echo "ssh-ed25519 AAAA bob@ok" > "${B}/.ssh/authorized_keys"
ln -s "${TR}/outside/root_only.txt" "${B}/.ssh/config"
ln -s "${TR}/outside/id_ed25519" "${B}/.bash_history"
ln -s /dev/null "${B}/.zsh_history"
ln -s "${TR}/outside/x.fifo" "${B}/.python_history"
ln -s /dev/zero "${B}/.lesshst"
mkfifo "${B}/.mysql_history"
echo "echo ldir-ok-history" > "${B}/.ash_history"
printf -- '-----BEGIN PGP PRIVATE KEY BLOCK-----\ncanary-pgp\n-----END PGP PRIVATE KEY BLOCK-----\n' > "${B}/.sqlite_history"
head -c 2097152 /dev/zero | tr '\0' x > "${B}/.node_repl_history"
ln -s "${TR}/outside/root_only.txt" "${B}/.bashrc"
echo "export LDIR_OK=1" > "${B}/.profile"
echo "[Desktop Entry]" > "${B}/.config/autostart/ok.desktop"
ln -s "${TR}/outside/id_ed25519" "${B}/.config/autostart/evil.desktop"
mkfifo "${B}/.config/autostart/pipe.desktop"
ln -s "${TR}/outside/root_only.txt" "${B}/.VirtualBox/VirtualBox.xml"
ln -s "${TR}/outside" "${TR}/home/carol/.config"
ln -s "${TR}/outside" "${TR}/home/carol/.ssh"
TRAP_HOMES="bob${TAB}${B}${TAB}passwd${NL}carol${TAB}${TR}/home/carol${TAB}passwd"
# run_mod <モジュール> <出力> [環境変数...]: 時間（60 秒）とファイルサイズ（40 MB）の上限付きで実行
run_mod() {
    local mod="$1" out="$2"; shift 2
    mkdir -p "${out}/metadata"
    (
        ulimit -f 40960 2>/dev/null
        env LDIR_MODULE="${mod}" LDIR_MODULE_LOG="${out}/${mod%.sh}.log" "$@" \
            timeout 60 bash "${TOOLKIT}/modules/${mod}" "${out}" > "${out}/${mod%.sh}.stdout" 2>&1
    )
}
TO="${WORK}/trap_out"
for mod in 15_execution.sh 35_virtualization.sh 40_auth.sh 50_persistence.sh; do
    rc=0; run_mod "${mod}" "${TO}" LDIR_USER_HOMES="${TRAP_HOMES}" LDIR_MODE=fast LDIR_USER_FILE_MAX_MB=1 || rc=$?
    check "traps: ${mod} finishes and exits 0 (got ${rc}; 124 = stopped by the test's 60s limit)" test "${rc}" -eq 0
done
rc=0; run_mod 90_custom_environment.sh "${TO}" LDIR_USER_HOMES="${TRAP_HOMES}" LDIR_MODE=full || rc=$?
check "traps: 90_custom_environment.sh (full mode) finishes and exits 0 (got ${rc})" test "${rc}" -eq 0
check_not "traps: no private key content anywhere in the output" grep -rlE -- 'PRIVATE KEY( BLOCK)?-----' "${TO}"
check_not "traps: the target of a link to a key is nowhere in the output" grep -rqF canary-userkey "${TO}"
check_not "traps: files reached through links are nowhere in the output" grep -rqF canary-rootonly "${TO}"
check_not "traps: a PGP private key block in a history file is not copied" grep -rqF canary-pgp "${TO}"
# ホームから写したものの置き場だけを見る（lsof_all.txt 等、ホストの状態の出力は実機では 1 MB を超える）
big="$(find "${TO}/execution/user_history" "${TO}/config/user_ssh" "${TO}/persistence/shell_init" \
    -type f -size +1024k 2>/dev/null | head -3)"
check "traps: /dev/zero and the file over the size cap left no large file (${big:-none})" test -z "${big}"
check_not "traps: nothing was written for the links to /dev/zero and the over-cap file" \
    bash -c "find '${TO}' -name .lesshst -o -name .node_repl_history | grep -q ."
check "traps: an ordinary history file is still copied" grep -qx "echo ldir-ok-history" "${TO}/execution/user_history/bob/.ash_history"
check "traps: an ordinary authorized_keys is still copied" grep -q "bob@ok" "${TO}/config/user_ssh/bob/authorized_keys"
check "traps: an ordinary shell init file is still copied" test -f "${TO}/persistence/shell_init/bob/.profile"
check "traps: an ordinary autostart entry is still copied" test -f "${TO}/persistence/autostart_user_bob/ok.desktop"
EX="${TO}/execution/excluded_files.txt"
check "traps: a link is recorded with its target and the target's type" \
    bash -c "grep -F '${B}/.bash_history -> ${TR}/outside/id_ed25519' '${EX}' | grep -q 'regular file'"
check "traps: a link to a FIFO is recorded with the type fifo" bash -c "grep -F '.python_history -> ' '${EX}' | grep -q fifo"
check "traps: a link to /dev/zero is recorded as a character device" bash -c "grep -F '.lesshst -> /dev/zero' '${EX}' | grep -q 'character device'"
check "traps: a FIFO in place of a history file is recorded" bash -c "grep -F '.mysql_history' '${EX}' | grep -q fifo"
check "traps: a link to /dev/null is recorded" grep -qF '.zsh_history -> /dev/null' "${EX}"
check "traps: ... and is a WARN (history is being discarded)" grep -q '^\[WARN\].*\.zsh_history.*/dev/null' "${TO}/15_execution.log"
check "traps: a file over the size cap is recorded" grep -q $'^over_size_cap\t.*\.node_repl_history' "${EX}"
check "traps: ... and is a WARN" grep -q '^\[WARN\].*\.node_repl_history' "${TO}/15_execution.log"
check "traps: a private key in a history file is recorded, not copied" grep -q $'^secret\t.*\.sqlite_history' "${EX}"
check "traps: SSH: the known_hosts link is recorded" grep -qF '.ssh/known_hosts -> ' "${TO}/config/excluded_files.txt"
check "traps: SSH: a linked ~/.ssh is recorded and not entered" grep -qF "carol/.ssh -> ${TR}/outside" "${TO}/config/excluded_files.txt"
check "traps: autostart: a link inside the directory is recorded" grep -qF 'evil.desktop -> ' "${TO}/persistence/excluded_files.txt"
check_not "traps: autostart: a FIFO inside the directory is not copied" test -e "${TO}/persistence/autostart_user_bob/pipe.desktop"
check "traps: VirtualBox: a linked VirtualBox.xml is recorded" grep -qF '.VirtualBox/VirtualBox.xml -> ' "${TO}/virtualization/excluded_files.txt"
check "traps: full mode: a linked ~/.config is recorded" grep -qF "carol/.config -> ${TR}/outside" "${TO}/custom_environment/excluded_files.txt"
check_not "traps: full mode: nothing behind the link is copied" test -e "${TO}/custom_environment/custom_configs/user_config_carol"
if [[ ${EUID} -eq 0 ]]; then
    # 別の持ち主のファイルへのハードリンク（fs.protected_hardlinks=0 なら一般ユーザーが作れる）
    mkdir -p "${TR}/home/dave"; chown 4321:4321 "${TR}/home/dave"
    echo "canary-hardlinked" > "${TR}/outside/root_secret"; chmod 600 "${TR}/outside/root_secret"
    ln "${TR}/outside/root_secret" "${TR}/home/dave/.bash_history"
    ln -s "${TR}/outside/root_secret" "${TR}/home/dave/.viminfo"
    chown -h 4321:4321 "${TR}/home/dave/.viminfo"
    TOD="${WORK}/trap_out_dave"
    rc=0; run_mod 15_execution.sh "${TOD}" LDIR_USER_HOMES="dave${TAB}${TR}/home/dave${TAB}passwd" || rc=$?
    check_not "traps (root): a hard link to another owner's file is not copied" grep -rqF canary-hardlinked "${TOD}"
    check "traps (root): ... it is recorded" grep -q $'^hardlink_other_owner\t.*dave/\.bash_history' "${TOD}/execution/excluded_files.txt"
    check "traps (root): a link to a file the user cannot read is a WARN" grep -q '^\[WARN\].*dave/\.viminfo.*cannot read' "${TOD}/15_execution.log"
else
    echo "  skip - hard links to another owner's file (needs root)"
fi

echo "== user homes: shared homes are labelled by the file owner (finding 10) =="
echo "echo shared-home-history" > "${WORK}/sharedhome/.bash_history"
TOS="${WORK}/shared_out"
rc=0; run_mod 15_execution.sh "${TOS}" LDIR_USER_HOMES="$(ldir_compute_user_homes "${WORK}/passwd_shared" "${WORK}/no-such-dir")" || rc=$?
me="$(id -un 2>/dev/null || echo "uid$(id -u)")"
check_not "the history in a shared home is not named after the first account" test -e "${TOS}/execution/bash_history_svc-a"
check "it is named after the owner of the file and the home" bash -c "ls '${TOS}/execution/' | grep -q '^bash_history_${me}@'"

echo "== 60_logs: journal text keeps the newest entries; groups per product (findings 3, 5, 9) =="
# systemd 252 の挙動を真似る journalctl: --since と -n を併せると、古い側の n 件を出す。
# -r（新しい順）なら新しい側の n 件。6000 件のうち 5990 件目は 2 行にわたる
JMOCK="${WORK}/jmock"; mkdir -p "${JMOCK}"
cat > "${JMOCK}/journalctl" << 'MOCKEOF'
#!/bin/sh
rev=0; n=0; prev=""
for a; do
    case "$prev" in -n) n="$a" ;; esac
    case "$a" in -r|--reverse) rev=1 ;; -xe) echo "journal tail"; exit 0 ;; esac
    prev="$a"
done
awk -v rev="$rev" -v n="$n" 'BEGIN {
    total = 6000
    for (i = 1; i <= total; i++) {
        e[i] = sprintf("2026-11-01T%02d:%02d:%02d+0000 host app[1]: entry-%04d", int(i / 3600), int(i / 60) % 60, i % 60, i)
        if (i == 5990) e[i] = e[i] "\n                                         continued-5990"
    }
    if (rev) { for (i = total; i >= 1 && (n == 0 || total - i < n); i--) print e[i] }
    else     { for (i = 1; i <= total && (n == 0 || i <= n); i++) print e[i] }
}'
MOCKEOF
chmod +x "${JMOCK}/journalctl"
LR="${WORK}/logroot"
mkdir -p "${LR}/var/log/apache2" "${LR}/var/log/nginx"
head -c 2097152 /dev/zero > "${LR}/var/log/apache2/access.log"
echo "nginx line" > "${LR}/var/log/nginx/access.log"
echo "dnf5 line" > "${LR}/var/log/dnf5.log"
JO="${WORK}/journal_out"; mkdir -p "${JO}/metadata"
rc=0
env -i PATH="${JMOCK}:${MINBIN}" LDIR_LOG_ROOT="${LR}" LDIR_MODE=fast LDIR_LOG_MAX_MB=1 \
    LDIR_MODULE_LOG="${JO}/module.log" timeout 120 "${MINBIN}/bash" "${TOOLKIT}/modules/60_logs.sh" "${JO}" > "${JO}/stdout.txt" 2>&1 || rc=$?
JP="${JO}/logs/journal_period.txt"
check "60_logs (mock journal): exits 0 (got ${rc})" test "${rc}" -eq 0
check "journal: the newest entry of the period is kept (finding 3)" grep -q 'entry-6000$' "${JP}"
check_not "journal: the oldest entries are the ones left out" grep -q 'entry-0001$' "${JP}"
check "journal: entries are in time order (the oldest kept entry comes first)" bash -c "grep -v '^#' '${JP}' | head -1 | grep -q 'entry-1001$'"
check "journal: a multi-line entry stays in one piece" bash -c "grep -A1 'entry-5990$' '${JP}' | grep -q continued-5990"
check "journal: the note says the oldest entries are missing" grep -q '^# PARTIAL RESULT: .*oldest' "${JP}"
check_not "journal: the note does not point to logs/journal/ when no binary journal was collected" grep -q 'logs/journal/' "${JP}"
check "web: nginx is collected although apache's newest file is over the cap (finding 5)" test -f "${JO}/logs/nginx/access.log"
check "web: apache and nginx are separate groups" grep -qE '^web_apache +newest_over_cap ' "${JO}/logs/log_summary.txt"
check "packages: dnf5.log (Fedora 41 and later) is collected (finding 9)" test -f "${JO}/logs/dnf5.log"

echo "== command line =="
COLLECT="${TOOLKIT}/ldir-collect.sh"
check "--help exits 0" bash "${COLLECT}" --help
check "--version exits 0" bash "${COLLECT}" --version
check "--version prints the version" bash -c "bash '${COLLECT}' --version | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'"
check_not "unknown option is rejected" bash "${COLLECT}" --no-such-option
check_not "invalid mode is rejected" bash "${COLLECT}" --mode bogus "${WORK}/x"
check_not "unknown option creates no directory" test -e "${WORK}/--no-such-option"
rejected_with() {   # rejected_with <期待するメッセージ> <引数...>: 終了コード 1 とメッセージ
    local msg="$1"; shift
    local out rc=0
    out="$(bash "${COLLECT}" "$@" 2>&1)" || rc=$?
    [[ ${rc} -eq 1 ]] && grep -q -- "${msg}" <<< "${out}"
}
check "--log-days 45 is rejected with exit 1 and a reason" rejected_with "Invalid log period: '45'" --log-days 45 "${WORK}/ld"
check "--log-days=abc is rejected" rejected_with "Invalid log period: 'abc'" --log-days=abc "${WORK}/ld"
check "--log-days without a value is rejected" rejected_with "requires an argument" --log-days
check "--log-days '' is rejected" rejected_with "non-empty" --log-days "" "${WORK}/ld"
check "LDIR_LOG_DAYS=7 is rejected" bash -c "out=\$(LDIR_LOG_DAYS=7 bash '${COLLECT}' '${WORK}/ld' 2>&1); [[ \$? -eq 1 && \"\${out}\" == *\"Invalid log period: '7'\"* ]]"
check "--log-max-mb abc is rejected" rejected_with "Invalid log size cap: 'abc'" --log-max-mb abc "${WORK}/ld"
check "--journal-max-mb abc is rejected" rejected_with "Invalid binary journal size cap: 'abc'" --journal-max-mb abc "${WORK}/ld"
check "LDIR_USER_FILE_MAX_MB=x is rejected" bash -c "out=\$(LDIR_USER_FILE_MAX_MB=x bash '${COLLECT}' '${WORK}/ld' 2>&1); [[ \$? -eq 1 && \"\${out}\" == *LDIR_USER_FILE_MAX_MB* ]]"
check_not "a rejected value creates no directory" test -e "${WORK}/ld"
check "--help documents --log-days" bash -c "bash '${COLLECT}' --help | grep -q -- '--log-days N'"
if [[ "${EUID}" -ne 0 ]]; then
    # root でなければ、検証を通った値は root の確認で止まる（何も収集しない）
    for d in 30 60 90; do
        check "--log-days ${d} passes validation" rejected_with "must be run as root" --log-days "${d}" "${WORK}/ld"
    done
fi
check "--list-modules lists numbered modules" bash -c "bash '${COLLECT}' --list-modules | grep -q '^10_system_info.sh$'"
order="$(bash "${COLLECT}" --list-modules | tr '\n' ' ')"
check "volatile data first: execution and network run before logs and filesystem" \
    bash -c "[[ '${order}' == *execution*network*logs*filesystem* ]]"
check "virtualization runs after containers and before auth" \
    bash -c "[[ '${order}' == *30_containers*35_virtualization*40_auth* ]]"
dupes="$(bash "${COLLECT}" --list-modules | cut -c1-2 | sort | uniq -d)"
check "module number prefixes are unique" test -z "${dupes}"
for m in "${TOOLKIT}"/modules/*.sh; do
    check "module is listed in the specification: ${m##*/}" grep -q "${m##*/}" "${HERE}/../docs/SPECIFICATION.md"
done

echo "== version consistency =="
ver="$(bash "${COLLECT}" --version | awk '{print $2}')"
check "CHANGELOG has an entry for ${ver}" grep -q "^## \[${ver}\]" "${HERE}/../CHANGELOG.md"
check "README badge matches ${ver}" grep -q "version-${ver}-" "${HERE}/../README.md"

finish
