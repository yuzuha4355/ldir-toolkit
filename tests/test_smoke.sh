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
# 期間と容量の上限の確認用に、/var/log に Web サーバーのログを置く（終了時に消す）。
# 既に /var/log/lighttpd があるホストでは置かない（その場合は該当する確認を飛ばす）
PLANT_DIR=/var/log/lighttpd
PLANTED=0
cleanup() {
    [[ ${PLANTED} -eq 1 ]] && rm -rf "${PLANT_DIR}"
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

echo "== run (fast mode, with archive) =="
rc=0
# 秘匿値マスクの確認用に、トークンに見える環境変数を持たせて実行する
CANARY="ldir-canary-$$-do-not-leak"
SMOKE_TEST_API_TOKEN="${CANARY}" LDIR_MODE=fast bash "${TOOLKIT}/ldir-collect.sh" --archive "${WORK}/out" > "${WORK}/stdout.txt" 2> "${WORK}/stderr.txt" || rc=$?
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
bad_status="$(awk 'f && NF { if ($2 !~ /^(collected|capped|none_in_period|not_present|symlink_only|copy_failed)$/) print } /^GROUP/ { f = 1 }' "${D}/logs/log_summary.txt")"
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
LDIR_FAST_SCAN_BUDGET=0 bash "${TOOLKIT}/ldir-collect.sh" --log-days 90 --log-max-mb 1 "${WORK}/budget" > /dev/null 2>&1 || rc=$?
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
    check "planted log: the cap is a WARN" grep -q '^\[WARN\].*\[web\] log size cap of 1 MB reached' "${B}/metadata/modules/60_logs.sh.log"
    check "planted log: the summary says capped" grep -qE '^web +capped ' "${B}/logs/log_summary.txt"
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
check_not "no private key material in copied configuration" \
    grep -rlE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "${D}/config" "${D}/containers" "${D}/virtualization" "${D}/kernel" "${D}/network"
check "output is not world/group readable" test "$(stat -c '%a' "${D}")" = "700"
check_not "stderr has no shell errors" grep -Eq 'unbound variable|syntax error|command not found|No such file or directory' "${WORK}/stderr.txt"

finish
