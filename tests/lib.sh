#!/bin/bash
# 最小限のテスト補助（外部依存なし）
# shellcheck disable=SC2034

TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "  ok   - $1"; }
fail() {
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL - $1"
    [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/         /'
    return 0
}

# check "説明" コマンド...   : コマンドが成功すれば ok
check() {
    local desc="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then pass "$desc"; else fail "$desc" "$out"; fi
}

# check_not "説明" コマンド... : コマンドが失敗すれば ok
check_not() {
    local desc="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then fail "$desc" "$out"; else pass "$desc"; fi
}

finish() {
    echo ""
    echo "${TESTS_RUN} checks, ${TESTS_FAILED} failed"
    [[ ${TESTS_FAILED} -eq 0 ]]
}
