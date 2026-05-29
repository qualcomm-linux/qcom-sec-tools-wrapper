#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Resolve a usable Qualcomm sectools binary and print its path to stdout.
# All diagnostics go to stderr so the path can be captured with $(...).
#
# Resolution order:
#   1. ${QCOM_SECTOOLS}                         (explicit binary, used as-is)
#   2. ${QCOM_SECTOOLS_DIR}/${VERSION}/Linux/sectools  (already vendored)
#   3. download + unzip the pinned version from the Qualcomm Software Center
#
# Environment:
#   QCOM_SECTOOLS          explicit path to a sectools binary (skips fetching)
#   QCOM_SECTOOLS_VERSION  version to fetch/use            (default: 1.45)
#   QCOM_SECTOOLS_DIR      vendor directory for downloads  (default: .sectools)
#   QCOM_SECTOOLS_URL      full download URL override      (default: derived)

set -eu

VERSION="${QCOM_SECTOOLS_VERSION:-1.45}"
DIR="${QCOM_SECTOOLS_DIR:-.sectools}"
SECTOOLS="${QCOM_SECTOOLS:-}"
URL="${QCOM_SECTOOLS_URL:-}"

log() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<EOF
Usage: fetch-sectools.sh [--version=VER] [--dir=DIR] [--url=URL]

Prints the path to a usable sectools binary, downloading the pinned version
into DIR/VER/ if no binary is already available.  Configurable via the
QCOM_SECTOOLS* environment variables (see header of this script).
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        --version=*) VERSION="${1#*=}" ;;
        --dir=*)     DIR="${1#*=}" ;;
        --url=*)     URL="${1#*=}" ;;
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

# 1. Explicit binary supplied by the caller.
if [ -n "${SECTOOLS}" ]; then
    if [ -x "${SECTOOLS}" ]; then
        printf '%s\n' "${SECTOOLS}"
        exit 0
    fi
    log "ERROR: QCOM_SECTOOLS is set to '${SECTOOLS}' but it is not an executable file."
    exit 1
fi

# 2. Already vendored from a previous fetch.
BIN="${DIR}/${VERSION}/Linux/sectools"
if [ -x "${BIN}" ]; then
    abspath "${BIN}"
    exit 0
fi

# 3. Fetch and unpack.
log "sectools v${VERSION} not found; fetching into ${DIR}/${VERSION}/ ..."

command -v unzip >/dev/null 2>&1 || { log "ERROR: 'unzip' is required to extract sectools."; exit 1; }

: "${URL:=https://softwarecenter.qualcomm.com/api/download/software/tools/Qualcomm_Security_Tools/All/${VERSION}.0/${VERSION}.zip}"

tmpzip="$(mktemp)"
cleanup() { rm -f "${tmpzip}"; }
trap cleanup EXIT INT TERM

log "Downloading ${URL}"
if command -v curl >/dev/null 2>&1; then
    curl -fSL "${URL}" -o "${tmpzip}" || { log "ERROR: download failed."; exit 1; }
elif command -v wget >/dev/null 2>&1; then
    wget -O "${tmpzip}" "${URL}" || { log "ERROR: download failed."; exit 1; }
else
    log "ERROR: need 'curl' or 'wget' to download sectools."
    exit 1
fi

mkdir -p "${DIR}/${VERSION}"
if ! unzip -o -q "${tmpzip}" -d "${DIR}/${VERSION}"; then
    log "ERROR: could not unzip the download (it may not be a valid archive)."
    log "       The Software Center download can require authentication."
    log "       Download sectools manually and set QCOM_SECTOOLS to its path."
    exit 1
fi

if [ ! -f "${BIN}" ]; then
    log "ERROR: '${BIN}' was not found in the extracted archive."
    log "       Set QCOM_SECTOOLS to the sectools binary path instead."
    exit 1
fi

chmod +x "${BIN}"
log "Installed sectools v${VERSION} at ${BIN}"
abspath "${BIN}"
