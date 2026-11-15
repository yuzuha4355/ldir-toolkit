#!/bin/bash
# 収集を実際に 1 回走らせ、出力の整合性を確認する。root 必須。
#   sudo bash tests/test_smoke.sh
# 使い捨ての環境（コンテナ/CI）での実行を想定。出力は一時ディレクトリに作り、終了時に消す。
# 残して調べたい場合: KEEP_OUTPUT=1
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${HERE}/../ldir-toolkit"
# shellcheck source=tests/lib.sh
source "${HERE}/lib.sh"

if [[ "${EUID}" -ne 0 ]]; then
    echo "SKIP: smoke test needs root"
    exit 0
fi

WORK="$(mktemp -d)"
# 収集の時間の上限（直っていない場合に、ホームに置いた FIFO の罠で永久に止まるのを防ぐ）
LIMIT=()
command -v timeout >/dev/null 2>&1 && LIMIT=(timeout 1800)
# 期間と容量の上限の確認用に、/var/log に Web サーバーのログを置く（終了時に消す）。
# 既に /var/log/lighttpd があるホストでは置かない（その場合は該当する確認を飛ばす）
PLANT_DIR=/var/log/lighttpd
PLANTED=0
# 一般ユーザーが自分のホームに置ける罠（検証レポートの指摘 1・2・7）。passwd に無いホーム
# （orphan）として調べられる。鍵と秘密のファイルは root しか読めない場所に置く（終了時に消す）
TRAP_HOME=/home/ldir-smoke-trap
TRAP_KEY=/root/.ldir-smoke-canary-key
TRAP_SECRET=/root/.ldir-smoke-canary-secret
PLANTED_TRAP=0
MOUNTED_SMALL=0
cleanup() {
    [[ ${PLANTED} -eq 1 ]] && rm -rf "${PLANT_DIR}"
    [[ ${PLANTED_TRAP} -eq 1 ]] && rm -rf "${TRAP_HOME}" "${TRAP_KEY}" "${TRAP_SECRET}"
    [[ ${MOUNTED_SMALL} -eq 1 ]] && umount "${WORK}/small"
    if [[ "${KEEP_OUTPUT:-0}" = "1" ]]; then
        echo "output kept in ${WORK}"
    else
        rm -rf "${WORK}"
    fi
}
trap cleanup EXIT
if [[ ! -e "${PLANT_DIR}" ]]; then
    mkdir -p "${PLANT_DIR}" && PLANTED=1
    head -c 614400 /dev/zero > "${PLANT_DIR}/ldir-smoke-access.log"
    head -c 614400 /dev/zero > "${PLANT_DIR}/ldir-smoke-access.log.1"
    echo old | gzip > "${PLANT_DIR}/ldir-smoke-access.log.2.gz"
    touch -t 201901010000 "${PLANT_DIR}/ldir-smoke-access.log.2.gz"
fi
KEY_CANARY="ldir-smoke-key-$$"
SECRET_CANARY="ldir-smoke-secret-$$"
if [[ -d /home && ! -e "${TRAP_HOME}" && ! -e "${TRAP_KEY}" && ! -e "${TRAP_SECRET}" && -d /root ]] \
    && mkdir -p "${TRAP_HOME}/.ssh" "${TRAP_HOME}/.config/autostart"; then
    PLANTED_TRAP=1
    printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n%s\n-----END OPENSSH PRIVATE KEY-----\n' "${KEY_CANARY}" > "${TRAP_KEY}"
    echo "${SECRET_CANARY}" > "${TRAP_SECRET}"
    chmod 600 "${TRAP_KEY}" "${TRAP_SECRET}"
    ln -s "${TRAP_KEY}" "${TRAP_HOME}/.ssh/known_hosts"
    ln -s "${TRAP_SECRET}" "${TRAP_HOME}/.bash_history"
    ln -s /dev/null "${TRAP_HOME}/.zsh_history"
    mkfifo "${TRAP_HOME}/.trap.fifo"
    ln -s "${TRAP_HOME}/.trap.fifo" "${TRAP_HOME}/.python_history"
    mkfifo "${TRAP_HOME}/.mysql_history"
    ln -s /dev/zero "${TRAP_HOME}/.lesshst"
    ln -s "${TRAP_KEY}" "${TRAP_HOME}/.config/autostart/evil.desktop"
    ln -s /root "${TRAP_HOME}/.local"
    echo "echo ldir-smoke-ok" > "${TRAP_HOME}/.ash_history"
    chown -R -h 4321:4321 "${TRAP_HOME}"
    # 別の持ち主のファイルへのハードリンク（chown の後に作る。同じファイルシステムのときだけ）
    ln "${TRAP_SECRET}" "${TRAP_HOME}/.viminfo" 2>/dev/null || true
fi
# journal のテキスト出力が新しい側を残すことの確認用（検証レポートの指摘 3）。
# journald が動いているホストでだけ、収集の直前に印を書く
JOURNAL_MARK=""
if [[ -d /run/systemd/system ]] && command -v logger >/dev/null 2>&1 && command -v journalctl >/dev/null 2>&1; then
    JOURNAL_MARK="ldir-smoke-journal-mark-$$"
    logger -t ldir-smoke "${JOURNAL_MARK}"
fi

echo "== run (fast mode, with archive) =="
rc=0
# 秘匿値マスクの確認用に、トークンに見える環境変数を持たせて実行する
CANARY="ldir-canary-$$-do-not-leak"
SMOKE_TEST_API_TOKEN="${CANARY}" LDIR_MODE=fast "${LIMIT[@]}" bash "${TOOLKIT}/ldir-collect.sh" --archive "${WORK}/out" > "${WORK}/stdout.txt" 2> "${WORK}/stderr.txt" || rc=$?
if [[ ${rc} -ne 0 ]]; then
    fail "collector exits 0 (got ${rc})" "$(tail -30 "${WORK}/stdout.txt" "${WORK}/stderr.txt")"
    finish; exit 1
fi
pass "collector exits 0"

D="$(find "${WORK}/out" -mindepth 1 -maxdepth 1 -type d | head -1)"
check "collection directory exists" test -d "${D}"
M="${D}/metadata/manifest.txt"

echo "== manifest =="
ver="$(bash "${TOOLKIT}/ldir-collect.sh" --version | awk '{print $2}')"
check "records the collector's own version (${ver})" grep -qx "Collector Version: ${ver}" "${M}"
check "records the mode" grep -qx "Collection Mode: fast" "${M}"
check "records the default log period (30 days)" grep -qx "Log Days: 30" "${M}"
check "records the default log size cap" grep -qx "Log Size Cap: 100 MB per log group" "${M}"
check "records whether this host is a VM" grep -qE '^Virtualization: [^ ]+ \(' "${M}"
check_not "no failed modules" grep -q '^✗' "${M}"
expected="$(bash "${TOOLKIT}/ldir-collect.sh" --list-modules | wc -l)"
actual="$(grep -c '^✓' "${M}")"
check "all ${expected} modules succeeded (got ${actual})" test "${expected}" -eq "${actual}"
check "each module has its own log" test "$(find "${D}/metadata/modules" -name '*.log' | wc -l)" -eq "${expected}"

echo "== integrity =="
check "every file verifies against file_hashes.txt" bash -c "cd '${D}' && sha256sum -c metadata/file_hashes.txt >/dev/null"
check_not "hash list uses relative paths" grep -q "  /" "${D}/metadata/file_hashes.txt"
listed="$(wc -l < "${D}/metadata/file_hashes.txt")"
present="$(find "${D}" -type f ! -name file_hashes.txt | wc -l)"
check "hash list covers every file (${listed}/${present})" test "${listed}" -eq "${present}"

echo "== archive =="
A="$(find "${WORK}/out" -maxdepth 1 -name '*.tar.gz' | head -1)"
check "archive was created" test -s "${A}"
check "archive checksum verifies" bash -c "cd '${WORK}/out' && sha256sum -c *.tar.gz.sha256 >/dev/null"
mkdir -p "${WORK}/moved"
tar -xzf "${A}" -C "${WORK}/moved"
check "extracted archive verifies from another path" bash -c "cd '${WORK}/moved'/* && sha256sum -c metadata/file_hashes.txt >/dev/null"

echo "== content =="
for f in system/uname.txt system/kernel_version.txt config/passwd config/group \
         execution/running_processes.txt filesystem/proc_mounts.txt \
         filesystem/etc_file_list.txt metadata/collection.log \
         kernel/security_sysctls.txt system/environment_variables.txt; do
    check "has ${f}" test -s "${D}/${f}"
done
check "kernel module records ld.so.preload state" bash -c "ls '${D}'/kernel/ld.so.preload* >/dev/null"
check "containers module produced output" test -n "$(ls -A "${D}/containers")"
check "virtualization: guest-side detection is recorded" grep -q '^Result: ' "${D}/virtualization/guest/virt_detection.txt"
check "virtualization: host side found something or says it found nothing" \
    bash -c "[[ -e '${D}/virtualization/no_hypervisor_detected.txt' || -d '${D}/virtualization/host' || -e '${D}/virtualization/hypervisor_processes.tsv' ]]"
check "logs: per-group summary exists" test -s "${D}/logs/log_summary.txt"
check "logs: per-file inventory exists" test -s "${D}/logs/log_inventory.tsv"
bad_status="$(awk 'f && NF { if ($2 !~ /^(collected|capped|newest_over_cap|none_in_period|not_present|symlink_only|copy_failed)$/) print } /^GROUP/ { f = 1 }' "${D}/logs/log_summary.txt")"
check "logs: every group has a known status" test -z "${bad_status}"
check_not "logs: journal_7days.txt is gone (renamed to journal_period.txt)" test -e "${D}/logs/journal_7days.txt"
if [[ -e "${D}/logs/journal_tail.txt" ]]; then
    check "logs: journal period export exists" test -e "${D}/logs/journal_period.txt"
fi
check "the list of examined home directories is kept" grep -q $'^root\t/root\t' "${D}/config/user_homes.tsv"
check "fast mode leaves web module disabled" test -f "${D}/web/disabled.txt"
check "fast mode leaves cloud metadata disabled" test -f "${D}/cloud_metadata/disabled.txt"

echo "== secret redaction =="
check "variable name is still recorded" grep -q '^SMOKE_TEST_API_TOKEN=<redacted:' "${D}/system/environment_variables.txt"
check_not "secret value appears nowhere in the collection" grep -rqF "${CANARY}" "${D}"
check "manifest records that redaction was on" grep -qx "Secret Redaction: 1" "${M}"

echo "== fast-mode scan budget, --log-days 90, --log-max-mb 1 =="
# 2 回目の収集で、時間の上限と、ログの期間・容量の指定をまとめて確かめる
rc=0
LDIR_FAST_SCAN_BUDGET=0 LDIR_JOURNAL_TEXT_MAX_LINES=500 "${LIMIT[@]}" bash "${TOOLKIT}/ldir-collect.sh" --log-days 90 --log-max-mb 1 "${WORK}/budget" > /dev/null 2>&1 || rc=$?
B="$(find "${WORK}/budget" -mindepth 1 -maxdepth 1 -type d | head -1)"
check "exhausted budget still exits 0" test "${rc}" -eq 0
check "records --log-days 90" grep -qx "Log Days: 90" "${B}/metadata/manifest.txt"
check "records --log-max-mb 1" grep -qx "Log Size Cap: 1 MB per log group" "${B}/metadata/manifest.txt"
if [[ ${PLANTED} -eq 1 ]]; then
    BI="${B}/logs/log_inventory.tsv"
    check "planted log: the newest file is collected" test -f "${B}/logs/lighttpd/ldir-smoke-access.log"
    check "planted log: the file over the 1 MB cap is not" test ! -e "${B}/logs/lighttpd/ldir-smoke-access.log.1"
    check "planted log: it is listed as over_cap" grep -q $'\tover_cap\t.*ldir-smoke-access.log.1$' "${BI}"
    check "planted log: the 2019 rotation is outside the period" grep -q $'\tolder_than_period\t.*ldir-smoke-access.log.2.gz$' "${BI}"
    check "planted log: the cap is a WARN" grep -q '^\[WARN\].*\[web_lighttpd\] log size cap of 1 MB reached' "${B}/metadata/modules/60_logs.sh.log"
    check "planted log: the summary says capped" grep -qE '^web_lighttpd +capped ' "${B}/logs/log_summary.txt"
    check "planted log (default run): both files fit under 100 MB" test -f "${D}/logs/lighttpd/ldir-smoke-access.log.1"
fi
check "scan_incomplete.txt lists what was skipped" test -s "${B}/filesystem/scan_incomplete.txt"
check "SUID list says it is partial instead of being empty" grep -q '^# PARTIAL RESULT' "${B}/filesystem/suid_sgid_files.txt"
check "world-writable list says it is partial" grep -q '^# PARTIAL RESULT' "${B}/filesystem/world_writable_files.txt"
check "manifest counts the cut-off as a warning" grep -Eq '70_filesystem.sh \(warn=[1-9]' "${B}/metadata/manifest.txt"
# 通常実行の側: 注記の有無は scan_incomplete.txt の有無と一致していなければならない。
# （/opt が巨大なホストでは通常実行でも上限に達するので、「必ず注記なし」とは言えない）
if [[ -s "${D}/filesystem/scan_incomplete.txt" ]]; then
    check "normal run hit the budget: its list is marked partial too" grep -q '^# PARTIAL RESULT' "${D}/filesystem/suid_sgid_files.txt"
else
    check_not "a complete scan carries no partial marker" grep -q '^# PARTIAL RESULT' "${D}/filesystem/suid_sgid_files.txt"
fi

echo "== hygiene =="
check_not "collection does not list itself" grep -rqF "${D}" "${D}/filesystem"
nested="$(find "${D}" -type d | awk -F/ 'NF>1 && $NF==$(NF-1)' | head -5)"
check "no doubled directories (x/x)" test -z "${nested}"
check_not "no SSH host private keys" bash -c "find '${D}' -name 'ssh_host_*_key' | grep -q ."
# 収集物全体を見る（特定のディレクトリに絞ると、漏れた先を見逃す。検証レポートの指摘 14）
check_not "no private key content anywhere in the collection" grep -rlE -- 'PRIVATE KEY( BLOCK)?-----' "${D}"
check_not "no private key content anywhere in the second collection" grep -rlE -- 'PRIVATE KEY( BLOCK)?-----' "${B}"
check "output is not world/group readable" test "$(stat -c '%a' "${D}")" = "700"
check_not "stderr has no shell errors" grep -Eq 'unbound variable|syntax error|command not found|No such file or directory' "${WORK}/stderr.txt"

echo "== traps in a user's home (review findings 1, 2, 7) =="
if [[ ${PLANTED_TRAP} -eq 1 ]]; then
    TL="orphan-home_ldir-smoke-trap"
    E15="${D}/metadata/modules/15_execution.sh.log"
    check_not "the key behind a link is nowhere in the collection" grep -rqF "${KEY_CANARY}" "${D}"
    check_not "a root-only file behind a link or a hard link is nowhere in the collection" grep -rqF "${SECRET_CANARY}" "${D}"
    check "the user's ordinary history file is collected" grep -qx "echo ldir-smoke-ok" "${D}/execution/user_history/${TL}/.ash_history"
    check "the links are recorded with their targets" grep -qF "${TRAP_HOME}/.bash_history -> ${TRAP_SECRET}" "${D}/execution/excluded_files.txt"
    check "a history file linked to /dev/null is a WARN" grep -q "^\[WARN\].*${TRAP_HOME}/\.zsh_history.*/dev/null" "${E15}"
    check "a link to a file the user cannot read is a WARN" grep -q "^\[WARN\].*${TRAP_HOME}/\.bash_history.*cannot read" "${E15}"
    check "nothing was read from /dev/zero" test -z "$(find "${D}" -name '.lesshst' -size +1k)"
    check "the FIFO and the link to it are recorded" bash -c "grep -F '${TRAP_HOME}/.python_history' '${D}/execution/excluded_files.txt' | grep -q fifo"
    check "a linked ~/.local is recorded" grep -qF "${TRAP_HOME}/.local -> /root" "${D}/execution/excluded_files.txt"
    check "SSH: the known_hosts link is recorded, not followed" grep -qF "${TRAP_HOME}/.ssh/known_hosts -> ${TRAP_KEY}" "${D}/config/excluded_files.txt"
else
    echo "  skip - could not plant the trap home (${TRAP_HOME} or a canary file already exists)"
fi

echo "== journal text export keeps the newest entries (review finding 3) =="
if [[ -n "${JOURNAL_MARK}" && -e "${B}/logs/journal_period.txt" ]]; then
    check "a message logged just before the run is in the capped export (500 entries)" grep -qF "${JOURNAL_MARK}" "${B}/logs/journal_period.txt"
    if grep -q '^# PARTIAL RESULT' "${B}/logs/journal_period.txt"; then
        check "the note says the oldest entries are the ones missing" grep -q '^# PARTIAL RESULT: .*oldest' "${B}/logs/journal_period.txt"
    fi
else
    echo "  skip - journald is not running here"
fi

echo "== output device fills up (review finding 6) =="
# 小さいファイルシステムに出力して満杯にする。LDIR_SMOKE_SMALL_DIR で既存の場所を渡すか、
# root で tmpfs をマウントできる環境（実機・VM）で行う
SMALL="${LDIR_SMOKE_SMALL_DIR:-}"
if [[ -z "${SMALL}" ]] && mkdir -p "${WORK}/small" && mount -t tmpfs -o size=5m tmpfs "${WORK}/small" 2>/dev/null; then
    MOUNTED_SMALL=1
    SMALL="${WORK}/small"
fi
if [[ -n "${SMALL}" ]]; then
    # 小さいホスト（最小構成のコンテナ）でも確実に満杯になるよう、3 MB のログを足す
    [[ ${PLANTED} -eq 1 ]] && head -c 3145728 /dev/zero > "${PLANT_DIR}/ldir-smoke-fill.log"
    rc=0
    "${LIMIT[@]}" bash "${TOOLKIT}/ldir-collect.sh" --log-max-mb 10 "${SMALL}/out" > "${WORK}/full_stdout.txt" 2>&1 || rc=$?
    F="$(find "${SMALL}/out" -mindepth 1 -maxdepth 1 -type d | head -1)"
    check "full device: exit status 2, not 1 (got ${rc})" test "${rc}" -eq 2
    check "full device: the output says so" grep -q 'output device is full' "${WORK}/full_stdout.txt"
    check "full device: the hash list was written" test -s "${F}/metadata/file_hashes.txt"
    check "full device: what was collected verifies" bash -c "cd '${F}' && sha256sum -c metadata/file_hashes.txt >/dev/null"
    listed="$(wc -l < "${F}/metadata/file_hashes.txt" 2>/dev/null || echo 0)"
    present="$(find "${F}" -type f ! -name file_hashes.txt | wc -l)"
    check "full device: the hash list covers every file (${listed}/${present})" test "${listed}" -eq "${present}"
    check "full device: the manifest lists the modules that were not run" grep -q 'not run: output device full' "${F}/metadata/manifest.txt"
else
    echo "  skip - no small file system to fill (needs root and tmpfs, or LDIR_SMOKE_SMALL_DIR)"
fi

finish
