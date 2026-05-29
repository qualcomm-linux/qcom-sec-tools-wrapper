#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Resolve a usable qdl binary and print its path to stdout, building the pinned
# release from source if needed.  All diagnostics go to stderr so the path can
# be captured with $(...).  Idempotent.
#
# Resolution order:
#   1. ${QCOM_QDL}                              (explicit binary, used as-is)
#   2. ${QCOM_QDL_DIR}/${VERSION}/build/qdl     (already built)
#   3. git clone the ${VERSION} ref and build it with meson + ninja
#
# Environment:
#   QCOM_QDL          explicit path to a qdl binary (skips building)
#   QCOM_QDL_VERSION  git ref (branch or tag) to build (default: master)
#   QCOM_QDL_DIR      directory for the source/build  (default: .qdl)
#   QCOM_QDL_REPO     git repository to clone         (default: linux-msm/qdl)

set -eu

VERSION="${QCOM_QDL_VERSION:-master}"
DIR="${QCOM_QDL_DIR:-.qdl}"
QDL="${QCOM_QDL:-}"
REPO="${QCOM_QDL_REPO:-https://github.com/linux-msm/qdl.git}"

log() { printf '%s\n' "$*" >&2; }

usage() {
    cat >&2 <<EOF
Usage: fetch-qdl.sh [--version=VER] [--dir=DIR] [--repo=URL]

Prints the path to a usable qdl binary, cloning the pinned ref (branch or tag)
and building it (meson + ninja) into DIR/VER/ when no binary is available.
Configurable via the QCOM_QDL* environment variables (see header).
EOF
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

# 1. Explicit binary supplied by the caller.
if [ -n "${QDL}" ]; then
    if [ -x "${QDL}" ]; then
        printf '%s\n' "${QDL}"
        exit 0
    fi
    log "ERROR: QCOM_QDL is set to '${QDL}' but it is not an executable file."
    exit 1
fi

srcdir="${DIR}/${VERSION}/src"
builddir="${DIR}/${VERSION}/build"
BIN="${builddir}/qdl"

# 2. Already built from a previous run.
if [ -x "${BIN}" ]; then
    abspath "${BIN}"
    exit 0
fi

# 3. Clone and build.
log "qdl ${VERSION} not found; cloning + building into ${DIR}/${VERSION}/ ..."
for tool in git meson ninja; do
    command -v "${tool}" >/dev/null 2>&1 || { log "ERROR: '${tool}' is required to build qdl."; exit 1; }
done

if [ ! -d "${srcdir}/.git" ]; then
    log "Cloning ${REPO} (ref ${VERSION})"
    if ! git clone --depth 1 --branch "${VERSION}" "${REPO}" "${srcdir}" >&2; then
        log "ERROR: failed to clone qdl ${VERSION} from ${REPO}."
        exit 1
    fi
fi

if [ ! -f "${builddir}/build.ninja" ]; then
    log "Configuring qdl build (meson setup)"
    if ! meson setup "${builddir}" "${srcdir}" >&2; then
        log "ERROR: meson setup failed."
        log "       qdl needs the libusb-1.0, libxml-2.0 and libzip development packages."
        exit 1
    fi
fi

log "Building qdl (ninja)"
if ! ninja -C "${builddir}" qdl >&2; then
    log "ERROR: qdl build failed."
    exit 1
fi

if [ ! -x "${BIN}" ]; then
    log "ERROR: qdl binary was not produced at ${BIN}."
    exit 1
fi

log "Built qdl ${VERSION} at ${BIN}"
abspath "${BIN}"
