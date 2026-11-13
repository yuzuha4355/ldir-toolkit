#!/bin/bash
# lib/ の単体テスト。root 不要、システムには触れない。
#   bash tests/test_unit.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="${HERE}/../ldir-toolkit"
# shellcheck source=tests/lib.sh
source "${HERE}/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

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
check_not "modules contain no unchecked '> file 2>&1' collection commands" \
    grep -nE '^[[:space:]]*[a-z][^|>]* > "\$\{[A-Z_]+\}/[^"]+" 2>&1$' "${TOOLKIT}"/modules/*.sh

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

echo "== command line =="
COLLECT="${TOOLKIT}/ldir-collect.sh"
check "--help exits 0" bash "${COLLECT}" --help
check "--version exits 0" bash "${COLLECT}" --version
check "--version prints the version" bash -c "bash '${COLLECT}' --version | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'"
check_not "unknown option is rejected" bash "${COLLECT}" --no-such-option
check_not "invalid mode is rejected" bash "${COLLECT}" --mode bogus "${WORK}/x"
check_not "unknown option creates no directory" test -e "${WORK}/--no-such-option"
check "--list-modules lists numbered modules" bash -c "bash '${COLLECT}' --list-modules | grep -q '^10_system_info.sh$'"
order="$(bash "${COLLECT}" --list-modules | tr '\n' ' ')"
check "volatile data first: execution and network run before logs and filesystem" \
    bash -c "[[ '${order}' == *execution*network*logs*filesystem* ]]"
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
