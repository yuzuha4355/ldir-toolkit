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
cleanup() {
    if [[ "${KEEP_OUTPUT:-0}" = "1" ]]; then
        echo "output kept in ${WORK}"
    else
        rm -rf "${WORK}"
    fi
}
trap cleanup EXIT

echo "== run (fast mode, with archive) =="
rc=0
LDIR_MODE=fast bash "${TOOLKIT}/ldir-collect.sh" --archive "${WORK}/out" > "${WORK}/stdout.txt" 2> "${WORK}/stderr.txt" || rc=$?
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
         filesystem/etc_file_list.txt metadata/collection.log; do
    check "has ${f}" test -s "${D}/${f}"
done
check "fast mode leaves web module disabled" test -f "${D}/web/disabled.txt"
check "fast mode leaves cloud metadata disabled" test -f "${D}/cloud_metadata/disabled.txt"

echo "== hygiene =="
check_not "collection does not list itself" grep -rqF "${D}" "${D}/filesystem"
nested="$(find "${D}" -type d | awk -F/ 'NF>1 && $NF==$(NF-1)' | head -5)"
check "no doubled directories (x/x)" test -z "${nested}"
check_not "no SSH host private keys" bash -c "find '${D}' -name 'ssh_host_*_key' | grep -q ."
check "output is not world/group readable" test "$(stat -c '%a' "${D}")" = "700"
check_not "stderr has no shell errors" grep -Eq 'unbound variable|syntax error|command not found|No such file or directory' "${WORK}/stderr.txt"

finish
