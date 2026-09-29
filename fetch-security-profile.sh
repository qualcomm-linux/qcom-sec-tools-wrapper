#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Print the absolute path of a sectools security profile XML.
# Diagnostics go to stderr so the path can be captured with $(...).
#
# A profile containing a '/' is used as a path.  A bare filename
# (e.g. kodiak_security_profile.xml) is taken from a clone of
# https://github.com/qualcomm/security-profiles, fetched on demand.

set -eu

PROFILE="${QCOM_SEC_PROFILE:-}"
DIR="${QCOM_SEC_PROFILES_DIR:-.security-profiles}"
REPO="${QCOM_SEC_PROFILES_REPO:-https://github.com/qualcomm/security-profiles.git}"
REV="${QCOM_SEC_PROFILES_REV:-bb3e8c735d6b7fee25227395249f9ec674867464}"

log() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<USAGE
Usage: fetch-security-profile.sh [--profile=NAME|PATH] [--dir=DIR] [--repo=URL] [--rev=REV]

Environment: QCOM_SEC_PROFILE, QCOM_SEC_PROFILES_DIR, QCOM_SEC_PROFILES_REPO,
QCOM_SEC_PROFILES_REV.
USAGE
}

while [ $# -gt 0 ]; do
    case $1 in
        --profile=*) PROFILE="${1#*=}" ;;
        --dir=*)     DIR="${1#*=}" ;;
        --repo=*)    REPO="${1#*=}" ;;
        --rev=*)     REV="${1#*=}" ;;
        -h|--help)   usage; exit 0 ;;
        *)           log "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
done

abspath() {
    case $1 in
        /*) printf '%s\n' "$1" ;;
        *)  printf '%s/%s\n' "$(pwd)" "$1" ;;
    esac
}

[ -n "${PROFILE}" ] || { log "ERROR: QCOM_SEC_PROFILE is not set."; exit 1; }

case "${PROFILE}" in
    */*)
        [ -f "${PROFILE}" ] || { log "ERROR: security profile not found: ${PROFILE}"; exit 1; }
        abspath "${PROFILE}"
        exit 0
        ;;
esac

if [ ! -d "${DIR}/.git" ]; then
    command -v git >/dev/null 2>&1 || { log "ERROR: 'git' is required to fetch security profiles."; exit 1; }
    log "Cloning ${REPO} into ${DIR}"
    git clone -q "${REPO}" "${DIR}" >&2 || { log "ERROR: failed to clone ${REPO}."; exit 1; }
fi

if [ "$(git -C "${DIR}" rev-parse HEAD)" != "${REV}" ]; then
    git -C "${DIR}" fetch -q origin >&2 || log "WARNING: could not fetch ${REPO}; using local clone."
    git -C "${DIR}" checkout -q "${REV}" >&2 || { log "ERROR: revision ${REV} not found in ${DIR}."; exit 1; }
fi

BIN="${DIR}/${PROFILE}"
[ -f "${BIN}" ] || { log "ERROR: '${PROFILE}' not found in ${REPO} (${REV})."; exit 1; }
abspath "${BIN}"
