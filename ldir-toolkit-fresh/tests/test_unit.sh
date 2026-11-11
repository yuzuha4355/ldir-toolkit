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

echo "== version consistency =="
ver="$(bash "${COLLECT}" --version | awk '{print $2}')"
check "CHANGELOG has an entry for ${ver}" grep -q "^## \[${ver}\]" "${HERE}/../CHANGELOG.md"
check "README badge matches ${ver}" grep -q "version-${ver}-" "${HERE}/../README.md"

finish
