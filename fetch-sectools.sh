#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Print the path of a usable sectools binary, fetching it if needed.
# Diagnostics go to stderr so the path can be captured with $(...).
#
# Resolution order: QCOM_SECTOOLS, then an existing download under
# QCOM_SECTOOLS_DIR, then a download from the Qualcomm Software Center.
# Download details mirror the meta-qcom sectools-native recipe.

set -eu

VERSION="${QCOM_SECTOOLS_VERSION:-1.50.0}"
DIR="${QCOM_SECTOOLS_DIR:-.sectools}"
SECTOOLS="${QCOM_SECTOOLS:-}"
URL="${QCOM_SECTOOLS_URL:-}"
SHA256="${QCOM_SECTOOLS_SHA256:-}"

log() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<USAGE
Usage: fetch-sectools.sh [--version=VER] [--dir=DIR] [--url=URL] [--sha256=SUM]

Environment: QCOM_SECTOOLS (explicit binary), QCOM_SECTOOLS_VERSION,
QCOM_SECTOOLS_DIR, QCOM_SECTOOLS_URL, QCOM_SECTOOLS_SHA256,
QCOM_SECTOOLS_ARCH (x86_64|aarch64, default: uname -m).
USAGE
}

while [ $# -gt 0 ]; do
    case $1 in
        --version=*) VERSION="${1#*=}" ;;
        --dir=*)     DIR="${1#*=}" ;;
        --url=*)     URL="${1#*=}" ;;
        --sha256=*)  SHA256="${1#*=}" ;;
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

if [ -n "${SECTOOLS}" ]; then
    if [ -x "${SECTOOLS}" ]; then
        printf '%s\n' "${SECTOOLS}"
        exit 0
    fi
    log "ERROR: QCOM_SECTOOLS='${SECTOOLS}' is not an executable file."
    exit 1
fi

# The archive ships per-host builds: Linux (x86_64) and Linux_aarch64.
case "${QCOM_SECTOOLS_ARCH:-$(uname -m)}" in
    x86_64)  PLATFORM_DIR="Linux" ;;
    aarch64) PLATFORM_DIR="Linux_aarch64" ;;
    *)       log "ERROR: unsupported host architecture '$(uname -m)'."; exit 1 ;;
esac

# 1.50.0 downloads as 1.50.zip and unpacks into 1.50/.
TOPDIR="$(printf '%s' "${VERSION}" | cut -d. -f1,2)"
BIN="${DIR}/${VERSION}/${TOPDIR}/${PLATFORM_DIR}/sectools"

if [ -x "${BIN}" ]; then
    abspath "${BIN}"
    exit 0
fi

log "sectools ${VERSION} not found; fetching into ${DIR}/${VERSION}/ ..."
command -v unzip >/dev/null 2>&1 || { log "ERROR: 'unzip' is required."; exit 1; }

: "${URL:=https://softwarecenter.qualcomm.com/api/download/software/tools/Qualcomm_Security_Tools/All/${VERSION}/${TOPDIR}.zip}"
if [ -z "${SHA256}" ] && [ "${VERSION}" = "1.50.0" ]; then
    SHA256="8d6694f1d184e7c204d1e1ea50447a946d7f21838cfddb48b06f0c733d700cbe"
fi

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

if [ -n "${SHA256}" ] && command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${tmpzip}" | cut -d' ' -f1)"
    if [ "${actual}" != "${SHA256}" ]; then
        log "ERROR: sha256 mismatch: expected ${SHA256}, got ${actual}."
        exit 1
    fi
fi

mkdir -p "${DIR}/${VERSION}"
if ! unzip -o -q "${tmpzip}" -d "${DIR}/${VERSION}"; then
    log "ERROR: could not unzip the download; the Software Center may require a login."
    log "       Download sectools manually and set QCOM_SECTOOLS to the binary."
    exit 1
fi

if [ ! -f "${BIN}" ]; then
    log "ERROR: '${BIN}' not found in the archive; set QCOM_SECTOOLS instead."
    exit 1
fi

chmod +x "${BIN}"
log "Installed sectools ${VERSION} at ${BIN}"
abspath "${BIN}"
