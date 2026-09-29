#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Exercise fetch-security-profile.sh against a local profiles repository.

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
new_sandbox

FETCH="$ROOT/fetch-security-profile.sh"
ERR="$SANDBOX/err.log"
cd "$SANDBOX" || exit 1

run() { OUTPUT="$("$@" 2> "$ERR")"; }
git_() { git -c user.name=t -c user.email=t@example.com -C repo "$@"; }

assert_fails "unset profile is rejected" run env -u QCOM_SEC_PROFILE "$FETCH"
assert_grep "error names QCOM_SEC_PROFILE" "QCOM_SEC_PROFILE" "$ERR"

# Paths are used as-is.
mkdir -p mine; touch mine/custom.xml
assert_ok "relative path is accepted" run env QCOM_SEC_PROFILE=mine/custom.xml "$FETCH"
assert_eq "relative path is made absolute" "$SANDBOX/mine/custom.xml" "$OUTPUT"
assert_ok "absolute path is accepted" run env QCOM_SEC_PROFILE="$SANDBOX/mine/custom.xml" "$FETCH"
assert_eq "absolute path is printed" "$SANDBOX/mine/custom.xml" "$OUTPUT"
assert_fails "missing path is rejected" run env QCOM_SEC_PROFILE=mine/none.xml "$FETCH"
assert_ok "--profile= works" run "$FETCH" --profile="$SANDBOX/mine/custom.xml"

# Bare names come from the profiles repository.
git init -q repo
echo one > repo/kodiak_security_profile.xml
git_ add . && git_ commit -q -m one
REV1="$(git_ rev-parse HEAD)"
echo two > repo/kodiak_security_profile.xml
echo lemans > repo/lemans_security_profile.xml
git_ add . && git_ commit -q -m two
REV2="$(git_ rev-parse HEAD)"

ENV="env QCOM_SEC_PROFILES_REPO=$SANDBOX/repo QCOM_SEC_PROFILES_DIR=profiles"
# shellcheck disable=SC2086
assert_ok "bare name is fetched" run $ENV QCOM_SEC_PROFILES_REV="$REV2" QCOM_SEC_PROFILE=kodiak_security_profile.xml "$FETCH"
assert_eq "bare name resolves inside the clone" "$SANDBOX/profiles/kodiak_security_profile.xml" "$OUTPUT"
assert_eq "pinned revision content" two "$(cat profiles/kodiak_security_profile.xml)"
assert_grep "clone is reported" "Cloning" "$ERR"

# shellcheck disable=SC2086
assert_ok "second name reuses the clone" run $ENV QCOM_SEC_PROFILES_REV="$REV2" QCOM_SEC_PROFILE=lemans_security_profile.xml "$FETCH"
assert_not_grep "no second clone" "Cloning" "$ERR"

# shellcheck disable=SC2086
assert_ok "other revision is checked out" run $ENV QCOM_SEC_PROFILES_REV="$REV1" QCOM_SEC_PROFILE=kodiak_security_profile.xml "$FETCH"
assert_eq "older revision content" one "$(cat profiles/kodiak_security_profile.xml)"

# shellcheck disable=SC2086
assert_fails "unknown name is rejected" run $ENV QCOM_SEC_PROFILES_REV="$REV2" QCOM_SEC_PROFILE=nope_security_profile.xml "$FETCH"
assert_grep "unknown name is reported" "not found in" "$ERR"
# shellcheck disable=SC2086
assert_fails "unknown revision is rejected" run $ENV QCOM_SEC_PROFILES_REV=0000000000000000000000000000000000000000 QCOM_SEC_PROFILE=kodiak_security_profile.xml "$FETCH"

summary
