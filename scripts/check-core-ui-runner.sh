#!/bin/bash
# Selector and reporting regression checks for the built runner (run build-core-ui-runner.sh first).
set -uo pipefail

RUNNER="$(cd "$(dirname "$0")/.." && pwd)/dist/CoreUIRunner/CoreUIRunner"
[ -x "$RUNNER" ] || { echo "Build the runner first: bash scripts/build-core-ui-runner.sh"; exit 3; }
failed=0

expect_exit() {
    local want="$1" label="$2"; shift 2
    "$RUNNER" "$@" >/dev/null 2>&1
    local got=$?
    if [ "$got" -eq "$want" ]; then echo "PASS $label"; else echo "FAIL $label (exit $got, want $want)"; failed=1; fi
}

expect_exit 3 "--only ',' is rejected" --only ,
expect_exit 3 "--only '' is rejected" --only ""
expect_exit 3 "--only 'N01,' (empty token) is rejected" --only "N01,"
expect_exit 3 "--only S1 without --self-test is rejected" --only S1
expect_exit 3 "--only N99 is rejected" --only N99
expect_exit 3 "--self-test --only N01 is rejected" --self-test --only N01
expect_exit 3 "unwritable report is an error" --only A01 --report /nonexistent-dir/report.txt
expect_exit 0 "--self-test passes" --self-test

[ "$failed" -eq 0 ] && echo "ALL PASSED"
exit "$failed"
