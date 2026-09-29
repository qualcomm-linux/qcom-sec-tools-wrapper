# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Minimal POSIX sh test helpers, sourced by tests/test-*.sh.
# shellcheck shell=sh

set -u

# shellcheck disable=SC2034  # used by the sourcing test
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
    [ $# -gt 1 ] && printf '     %s\n' "$2"
}

assert_eq()       { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi; }
assert_file()     { if [ -f "$2" ]; then pass "$1"; else fail "$1" "missing file $2"; fi; }
assert_no_file()  { if [ ! -e "$2" ]; then pass "$1"; else fail "$1" "unexpected $2"; fi; }
assert_grep()     { if grep -q -- "$2" "$3"; then pass "$1"; else fail "$1" "'$2' not found in $3"; fi; }
assert_not_grep() { if grep -q -- "$2" "$3"; then fail "$1" "'$2' found in $3"; else pass "$1"; fi; }
assert_ok()       { name=$1; shift; if "$@"; then pass "$name"; else fail "$name" "command failed: $*"; fi; }
assert_fails()    { name=$1; shift; if "$@"; then fail "$name" "command succeeded: $*"; else pass "$name"; fi; }

new_sandbox() {
    SANDBOX="$(mktemp -d)"
    trap 'rm -rf "$SANDBOX"' EXIT INT TERM
}

summary() {
    printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}
