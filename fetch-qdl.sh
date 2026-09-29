#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Print the path of a usable qdl binary, building it from source if needed.
# Diagnostics go to stderr so the path can be captured with $(...).
#
# Resolution order: QCOM_QDL, then an existing build under QCOM_QDL_DIR,
# then a clone of QCOM_QDL_VERSION from QCOM_QDL_REPO built with meson.

set -eu

VERSION="${QCOM_QDL_VERSION:-v2.8}"
DIR="${QCOM_QDL_DIR:-.qdl}"
QDL="${QCOM_QDL:-}"
REPO="${QCOM_QDL_REPO:-https://github.com/linux-msm/qdl.git}"

log() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<USAGE
Usage: fetch-qdl.sh [--version=REF] [--dir=DIR] [--repo=URL]

Environment: QCOM_QDL (explicit binary), QCOM_QDL_VERSION, QCOM_QDL_DIR,
QCOM_QDL_REPO.
USAGE
}

while [ $# -gt 0 ]; do
    case $1 in
        --version=*) VERSION="${1#*=}" ;;
        --dir=*)     DIR="${1#*=}" ;;
        --repo=*)    REPO="${1#*=}" ;;
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

if [ -n "${QDL}" ]; then
    if [ -x "${QDL}" ]; then
        printf '%s\n' "${QDL}"
        exit 0
    fi
    log "ERROR: QCOM_QDL='${QDL}' is not an executable file."
    exit 1
fi

srcdir="${DIR}/${VERSION}/src"
builddir="${DIR}/${VERSION}/build"
BIN="${builddir}/qdl"

if [ -x "${BIN}" ]; then
    abspath "${BIN}"
    exit 0
fi

log "qdl ${VERSION} not found; building into ${DIR}/${VERSION}/ ..."
for tool in git meson ninja; do
    command -v "${tool}" >/dev/null 2>&1 || { log "ERROR: '${tool}' is required to build qdl."; exit 1; }
done

if [ ! -d "${srcdir}/.git" ]; then
    log "Cloning ${REPO} (${VERSION})"
    git clone --depth 1 --branch "${VERSION}" "${REPO}" "${srcdir}" >&2 \
        || { log "ERROR: failed to clone qdl ${VERSION} from ${REPO}."; exit 1; }
fi

if [ ! -f "${builddir}/build.ninja" ]; then
    meson setup "${builddir}" "${srcdir}" >&2 \
        || { log "ERROR: meson setup failed (needs libusb-1.0, libxml-2.0, libzip dev packages)."; exit 1; }
fi

ninja -C "${builddir}" qdl >&2 || { log "ERROR: qdl build failed."; exit 1; }

[ -x "${BIN}" ] || { log "ERROR: qdl binary not produced at ${BIN}."; exit 1; }

log "Built qdl ${VERSION} at ${BIN}"
abspath "${BIN}"
