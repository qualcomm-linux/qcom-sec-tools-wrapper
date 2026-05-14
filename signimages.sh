#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.

# Define the handler function
cleanup() {
    printf '\nInterrupt received! Cleaning up...\n'

    # cleanup mounts
    if [ ! -z "${LOOP_DEVICE}" ]; then
        sync
        udisksctl unmount --no-user-interaction -b ${LOOP_DEVICE} > /dev/null
        udisksctl loop-delete --no-user-interaction -b ${LOOP_DEVICE} > /dev/null
        sync
    fi

    exit 1
}

# register handler ctrl-c
trap cleanup INT

# Settings
VERSION="0.1"
KEYS_PATH="OEM-KEYS"
KEYS_ROOT_CERT="qpsa_rootca###.cer"
KEYS_CA_CERT="qpsa_attestca###.cer"
KEYS_CA_KEY="qpsa_attestca###.key"
KEYS_ROOTS_HASH="sha384_roots_hash.txt"
ROOT_CERT_TOTALNUM=1
SIGNING_KEY_INDEX=0
OUT_DIR="$(pwd)"
ANTI_ROLLBACK_VERSION=0x0
SECTOOL=""
SECURITY_PROFILE=""
SCRIPT_PATH="$(dirname "$(realpath -- "$0")")"
MIN_PYTHON_VER="3.10.0"
FMP_PATH="${KEYS_PATH}/demoCA"
FMP_ROOT_CER_FILE="QcFMPRoot.cer"
UEFI_KEYS_PATH=""
HW_VER=""

#_color <color code> < text >
_color() {
    [ "${FLAG_COLOR}" -eq 1 ] && printf '\033[%sm%s\033[0m' "$1" "$2" && return
    printf '%s' "$2"
}

# color render functions
COLOR_RED()    { _color "0;31" "$*"; }
COLOR_GREEN()  { _color "0;32" "$*"; }
COLOR_YELLOW() { _color "0;33" "$*"; }
COLOR_DIM()    { _color "2" "$*"; }

# log levels
LOG_ERROR=0
LOG_WARN=1
LOG_INFO=2
LOG_DEBUG=3

# Flags
RETURN_CODE=0
FLAG_CONTINUE=0
FLAG_COLOR=0
LOG_LEVEL=${LOG_INFO}
LOOP_DEVICE=""

# <level> <text>
log()
{
    if [ "${LOG_LEVEL}" -lt "$1" ]; then
        return
    fi
    case "$1" in
        "${LOG_ERROR}")
            shift
            echo >&2 "$(COLOR_RED '[ERROR]') $*"
            ;;
        "${LOG_WARN}")
            if [ "$1" -ge "${LOG_WARN}" ]; then
                shift
                echo "$(COLOR_YELLOW '[WARN]') $*"
            fi
            ;;
        "${LOG_INFO}")
            if [ "$1" -ge "${LOG_INFO}" ]; then
                shift
                echo "[INFO] $*"
            fi
            ;;
        "${LOG_DEBUG}")
            if [ "$1" -ge "${LOG_DEBUG}" ]; then
                shift
                echo "$(COLOR_DIM '[DEBUG]') $*"
            fi
            ;;
        *)
            echo "$1"
            ;;
    esac
}

log_error()
{
    log ${LOG_ERROR} "$*"
}

log_warn()
{
    log ${LOG_WARN} "$*"
}

log_info()
{
    log ${LOG_INFO} "$*"
}

log_debug()
{
    log ${LOG_DEBUG} "$*"
}

log_ok()
{
    if [ "${LOG_LEVEL}" -ge "${LOG_INFO}" ]; then
        echo "$(COLOR_GREEN '[OK]') $*"
    fi
}

parse_args()
{
    while [ $# -gt 0 ]
    do
        case $1 in
        --anti-rollback-version)
            if echo "$2" | grep -Eq '^0x?[0-9a-fA-F]+$'; then
                ANTI_ROLLBACK_VERSION=$2
                log_debug "FLAG: ANTI_ROLLBACK_VERSION: ${ANTI_ROLLBACK_VERSION}"
            else
                log_error "ANTI_ROLLBACK_VERSION is not a valid hex number: $2.  Aborting."
                exit 1
            fi
            shift
            shift
            ;;
        --color)
            FLAG_COLOR=1
            log_debug "FLAG: COLOR: Enable"
            shift
            ;;
        --continue-on-error)
            FLAG_CONTINUE=1
            log_debug "FLAG: CONTINUE: Enable"
            shift
            ;;
        --debug)
            LOG_LEVEL=${LOG_DEBUG}
            log_debug "FLAG: Debug: enabled"
            shift
            ;;
        --fmp-path)
            FMP_PATH=$2
            log_debug "FLAG: FMP_PATH: ${FMP_PATH}"
            shift
            shift
            ;;
        --hw-ver)
            HW_VER="[$(echo ${2} | tr '[:upper:]' '[:lower:]')]"
            log_debug "FLAG: HW_VER: ${2}"
            shift
            shift
            ;;
        --keys-path)
            KEYS_PATH=$2
            log_debug "FLAG: KEYS_PATH: ${KEYS_PATH}"
            shift
            shift
            ;;
        --keys-root-cert-filename)
            KEYS_ROOT_CERT=$2
            log_debug "FLAG: KEYS_ROOT_CERT: ${KEYS_ROOT_CERT}"
            shift
            shift
            ;;
        --keys-ca-cert-filename)
            KEYS_CA_CERT=$2
            log_debug "FLAG: KEYS_CA_CERT: ${KEYS_CA_CERT}"
            shift
            shift
            ;;
        --keys-ca-key-filename)
            KEYS_CA_KEY=$2
            log_debug "FLAG: KEYS_CA_KEY: ${KEYS_CA_KEY}"
            shift
            shift
            ;;
        --keys-root-hash-filename)
            KEYS_ROOTS_HASH=$2
            log_debug "FLAG: KEYS_ROOTS_HASH: ${KEYS_ROOTS_HASH}"
            shift
            shift
            ;;
        --out-dir)
            OUT_DIR="$(realpath -- "$2")"
            log_debug "FLAG: OUT_DIR: ${OUT_DIR}"
            shift
            shift
            ;;
        --quiet)
            LOG_LEVEL=${LOG_ERROR}
            shift
            ;;
        --root-cert-totalnum)
            case $2 in
                1)
                    ROOT_CERT_TOTALNUM=$2
                    log_debug "FLAG: ROOT_CERT_TOTALNUM: ${ROOT_CERT_TOTALNUM}"
                    ;;
                *)
                    log_error "ROOT_CERT_TOTALNUM values can only be 1.  Aborting."
                    exit 1
                    ;;
            esac
            shift
            shift
            ;;
        --sectoolv2)
            SECTOOL=$2
            log_debug "FLAG: SECTOOL: ${SECTOOL}"
            shift
            shift
            ;;
        --security-profile)
            SECURITY_PROFILE=$2
            log_debug "FLAG: SECURITY_PROFILE: ${SECURITY_PROFILE}"
            shift
            shift
            ;;
        --signing-key-index)
            case $2 in
                0 | 1 | 2 | 3)
                    SIGNING_KEY_INDEX=$2
                    log_debug "FLAG: SIGNING_KEY_INDEX: ${SIGNING_KEY_INDEX}"
                    ;;
                *)
                    log_error "SIGNING_KEY_INDEX values can be 0,1,2 or 3: $2.  Aborting."
                    exit 1
                    ;;
            esac
            shift
            shift
            ;;
        --uefi-keys-path)
            UEFI_KEYS_PATH=$2
            log_debug "FLAG: UEFI_KEYS_PATH: ${UEFI_KEYS_PATH}"
            shift
            shift
            ;;
        --version)
            echo "Version: ${VERSION}"
            exit 0
            ;;
        --help)
            echo "Usage parameters:"
            echo "--anti-rollback-version: hex value supplied to 'sectoolsv2 secure-image' --anti-rollback-version param"
            echo "  (default: ${ANTI_ROLLBACK_VERSION})"
            echo "--color: enable color logging"
            echo "--continue-on-error: don't break when signing errors are encountered."
            echo "--debug: enables debug logging"
            echo "--fmp-path: path to the FMP keys used for capsule updates (default: ${FMP_PATH})"
            echo "--hw-ver: override the *_security_profile.xml value for HW version"
            echo "--keys-path: path to keys directory generated by genkeys script (default: ${KEYS_PATH})"
            echo "--keys-root-cert-filename: root cert filename (default: ${KEYS_ROOT_CERT})"
            echo "--keys-ca-cert-filename: ca cert filename (default: ${KEYS_CA_CERT})"
            echo "--keys-ca-key-filename: ca key filename (default: ${KEYS_CA_KEY})"
            echo "--keys-root-hash-filename: roots hash filename (default: ${KEYS_ROOTS_HASH})"
            echo "--out-dir: output directory for signed images (default: ${OUT_DIR})"
            echo "--quiet: disable normal logging"
            echo "--root-cert-totalnum: set # of root certs to use. 1-4 allowed (default: ${ROOT_CERT_TOTALNUM})"
            echo "--sectoolv2: path to sectoolv2 binary"
            echo "--security-profile: path to *_security_profile.xml"
            echo "--signing-key-index: which CA key index to use for signing (default: ${SIGNING_KEY_INDEX})"
            echo "--uefi-keys-path: path to UEFI signing keys/certs"
            exit 0
            ;;
        *)
            shift
            ;;
        esac
    done
}

parse_args "$@"


version_greater_equal()
{
    printf '%s\n%s\n' "$2" "$1" | sort --check=quiet --version-sort
}

# <signfile> <sudo flag>
sign_verify()
{
    SUDO_FLAG=""
    if [ "$2" -eq 1 ]; then
        SUDO_FLAG="sudo "
    fi
    log_debug "Found $1"

    file="$(basename $1)"
    filedir="$(dirname "$1")"

    sign_id=$(${SECTOOL} secure-image --inspect $1 | grep "| Software ID:" | cut -d'|' -f3 | head -n 1)
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ]; then
        log_error "secure-image inspect "Software ID" failed for $1."
        if [ "${FLAG_CONTINUE}" -eq 0 ]; then
            exit 1
        else
            RETURN_CODE=1
            return 0
        fi
    fi
    if [ -z "${sign_id}" ]; then
        log_warn "Signatures not found in $1.  Skipping."
        return 0
    fi

    MATCH=""
    bind_hw_ver=$(${SECTOOL} secure-image --inspect $1 | grep "| Bound to SoC Hardware Version" | cut -d'|' -f3 | head -n 1 | trim)
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ]; then
        log_error "secure-image inspect "Hardware Version" failed for $1."
        if [ "${FLAG_CONTINUE}" -eq 0 ]; then
            exit 1
        else
            RETURN_CODE=1
            return 0
        fi
    fi
    if [ "${bind_hw_ver}" = "False" ]; then
        MATCH="ANY"
    else
        sign_hw_ver=$(${SECTOOL} secure-image --inspect $1 | grep "| SoC Hardware Version" | cut -d'|' -f3 | head -n 1 | trim | tr '[:upper:]' '[:lower:]')
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "secure-image inspect "Hardware Version" failed for $1."
            if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                exit 1
            else
                RETURN_CODE=1
                return 0
            fi
        fi
        for word in ${sign_hw_ver}
        do
            case "${HW_VER}" in
                *"[${word}]"*) MATCH=${word} ;;
            esac
        done
    fi

    if [ -z "${MATCH}" ]; then
        log_warn "HW version mismatch (${sign_hw_ver}) in $1.  Skipping."
        return 0
    else
        log_debug "MATCH HW version: PROFILE:${HW_VER} vs. FILE:${MATCH}"
    fi

    # Lookup the IMAGE-ID from mapping
    IMAGE_ID=$(echo "${IMAGE_ID_MAPPING}" | grep "${file}" | cut -d' ' -f2)
    PIL_SPLIT_FLAG=$(echo "${IMAGE_ID_MAPPING}" | grep "${file}" | cut -d' ' -f3)
    if [ -z "${IMAGE_ID}" ] || [ "${IMAGE_ID}" = "UNKNOWN" ]; then
        log_error "IMAGE-ID mapping not found for ${file}."
        if [ "${FLAG_CONTINUE}" -eq 0 ]; then
            exit 1
        else
            RETURN_CODE=1
            return 0
        fi
    fi

    case "${IMAGE_ID}" in
        *SKIP:*)
            log_warn "IMAGE-ID:SKIP for ${file}.  Skipping."
            return 0
            ;;
    esac

    # Check to make sure the IMAGE_ID is valid for the supplied security-profile
    if echo "${VALID_IMAGE_ID}" | grep "${IMAGE_ID}" >/dev/null 2>&1; then
        log_debug "IMAGE-ID(${IMAGE_ID}) is valid for ${file}."
    else
        log_warn "IMAGE-ID(${IMAGE_ID}) is not valid for this security-profile(${SECURITY_PROFILE}).  Skipping."
        return 0
    fi

    if [ "${PIL_SPLIT_FLAG}" -eq 1 ]; then
        if [ -f "${filedir}/${file%.*}.mdt" ]; then
            log_debug "> Found PIL-SPLIT flag for $1.  Cleaning up fragments."
            ${SUDO_FLAG} rm ${filedir}/${file%.*}.mdt
            ${SUDO_FLAG} rm ${filedir}/${file%.*}.b* && true
        else
            log_debug "> Disabling PIL-SPLIT for $1.  No fragments found.."
            PIL_SPLIT_FLAG=0
        fi
    fi

    log_debug "Signing $1"
    OUTPUT=$(${SUDO_FLAG} ${SECTOOL} secure-image ${VERBOSE} \
        --sign $1 --image-id=${IMAGE_ID} \
        --security-profile ${SECURITY_PROFILE} \
        --anti-rollback-version=${ANTI_ROLLBACK_VERSION} \
        --signing-mode LOCAL \
        ${ROOT_CERT_INDEX} \
        --root-certificate ${ROOT_CERT_LIST} \
        --ca-certificate=${KEYS_CA_CERT_FILENAME} --ca-key=${KEYS_CA_KEY_FILENAME} \
        --outfile $1)
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
        printf '%s\n' "${OUTPUT}"
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "secure-image sign failed for $1."
            if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                exit 1
            else
                RETURN_CODE=1
                return 0
            fi
        fi
    fi

    if [ "${PIL_SPLIT_FLAG}" -eq 1 ]; then
        OUTPUT=$(${SUDO_FLAG} ${SCRIPT_PATH}/bin/pil-splitter $1 ${filedir}/${file%.*}.mdt)
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
            printf '%s\n' "${OUTPUT}"
            if [ "${RESPONSE}" -ne 0 ]; then
                log_error "pil-splitter failed."
                if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                    exit 1
                else
                    RETURN_CODE=1
                    return 0
                fi
            fi
        fi
    fi

    log_debug "Verifying root hash of $1"
    OUTPUT=$(${SECTOOL} secure-image ${VERBOSE} --verify-root ${ROOT_CERT_HASH} $1)
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
        printf '%s\n' "${OUTPUT}"
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "secure-image verify of root cert hash failed for $1."
            if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                exit 1
            else
                RETURN_CODE=1
                return 0
            fi
        fi
    fi

    # verify pil-split file
    if [ "${PIL_SPLIT_FLAG}" -eq 1 ]; then
        mdt_file="${filedir}/${file%.*}.mdt"
        log_debug "Verifying root hash of ${mdt_file}"
        OUTPUT=$(${SECTOOL} secure-image ${VERBOSE} --verify-root ${ROOT_CERT_HASH} ${mdt_file})
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
            printf '%s\n' "${OUTPUT}"
            if [ "${RESPONSE}" -ne 0 ]; then
                log_error "secure-image verify of root cert hash failed for ${mdt_file}."
                if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                    exit 1
                else
                    RETURN_CODE=1
                    return 0
                fi
            fi
        fi
    fi

    log_ok "SIGNED: $1"
}

# <filepath>
# sets LOOP_DEVICE and LOOP_MOUNT
setup_mount()
{
    # setup loop device
    OUTPUT=$(udisksctl loop-setup --no-user-interaction -f $1)
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
        printf '%s\n' "${OUTPUT}"
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "setup_mount: Failed to assign $1 to a loop device"
            return 1
        fi
    fi
    LOOP_DEVICE=$(echo "${OUTPUT}" | grep -o '/dev/loop[0-9]*')
    log_debug "setup_mount: $1 loop device is ${LOOP_DEVICE}"

    # mount loop device
    OUTPUT=$(udisksctl mount --no-user-interaction -b ${LOOP_DEVICE} -o rw)
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
        printf '%s\n' "${OUTPUT}"
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "setup_mount: Failed to mount $1"
            udisksctl loop-delete --no-user-interaction -b ${LOOP_DEVICE} > /dev/null
            LOOP_DEVICE=""
            return 1
        fi
    fi
    LOOP_MOUNT=$(echo "${OUTPUT}" | sed 's/.* at //')
    log_debug "setup_mount: $1 mounted at ${LOOP_MOUNT}"

    return 0
}

# <loop device>
cleanup_mount()
{
    sync
    udisksctl unmount --no-user-interaction -b $1 > /dev/null
    udisksctl loop-delete --no-user-interaction -b $1 > /dev/null
    sync
    LOOP_MOUNT=""
    LOOP_DEVICE=""
}

command -v dtc >/dev/null 2>&1 || { log_error "Missing dtc command.  Aborting."; exit 1; }
log_debug "dtc (device-tree compiler) found."

command -v python3 >/dev/null 2>&1 || { log_error "Missing python3.  Aborting."; exit 1; }
log_debug "python3.x found."

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
version_greater_equal "${PYTHON_VERSION}" ${MIN_PYTHON_VER} || { log_error "Need at least python3 ${MIN_PYTHON_VER}.  Aborting."; exit 1; }
log_debug "python3 version == ${PYTHON_VERSION}"

## TODO: check for the following Python3 packages:
## pip3 install --user python-magic OR sudo apt install python3-magic
## pip3 install --user pyelftools OR sudo apt install python3-pyelftools

if [ ! -z "${UEFI_KEYS_PATH}" ]; then
    command -v udisksctl >/dev/null 2>&1 || { log_error "Missing udisksctl command needed to mount UEFI artifacts (sudo apt install udisks2).  Aborting."; exit 1; }
    log_debug "udisksctl command found."
    command -v sbsign >/dev/null 2>&1 || { log_error "Missing sbsign command needed for UEFI signing (sudo apt install sbsigntool).  Aborting."; exit 1; }
    log_debug "sbsign command found."
fi

[ -z "${SECTOOL}"  ] && { log_error "Missing --sectoolv2 parameter.  Aborting."; exit 1; }
[ -z "${SECURITY_PROFILE}"  ] && { log_error "Missing --security-profile parameter.  Aborting."; exit 1; }
[ ! -f "${SECURITY_PROFILE}"  ] && { log_error "File for security-profile could not be found: ${SECURITY_PROFILE}  Aborting."; exit 1; }
[ ! -d "${KEYS_PATH}"  ] && { log_error "Directory for KEYS_PATH is not found: ${KEYS_PATH}.  Use --keys-path to set.  Aborting."; exit 1; }
[ ! -d "${OUT_DIR}" ] && { log_error "OUT_DIR not found: ${OUT_DIR}.  Aborting."; exit 1; }
[ ! -z "${UEFI_KEYS_PATH}" ] && [ ! -d "${UEFI_KEYS_PATH}"  ] && { log_error "Directory for UEFI_KEYS_PATH is not found: ${UEFI_KEYS_PATH}.  Use --uefi-keys-path to set.  Aborting."; exit 1; }

if [ "${SIGNING_KEY_INDEX}" -ge "${ROOT_CERT_TOTALNUM}" ]; then
        log_error "--signing-key-index(${SIGNING_KEY_INDEX}) cannot be equal or greater to --root-cert-totalnum(${ROOT_CERT_TOTALNUM}).  Aborting."
        exit 1
fi

if [ ! -f "${KEYS_PATH}/${KEYS_ROOTS_HASH}" ]; then
    log_error "Cannot find roots hash file: ${KEYS_PATH}/${KEYS_ROOTS_HASH}.  Aborting."
    exit 1
fi
log_debug "Reading the sha384 hash of the root certificate(s)."
ROOT_CERT_HASH="0x$(cat ${KEYS_PATH}/${KEYS_ROOTS_HASH} | cut -d' ' -f2)"
log_debug "> Done"

# Define a newline
newline="
"

if [ -z "${HW_VER}" ]; then
    # Read the SoC HW versions from the security profile
    HW_VER_RAW="$(sed -n '/<soc_hw_versions>/,/<\/soc_hw_versions>/p' ${SECURITY_PROFILE})"
    for line in ${HW_VER_RAW}
    do
        case "${line}" in
            *soc_hw_versions*) continue ;;
        esac
        if [ -n "${HW_VER}" ]; then
            HW_VER="${HW_VER}|"
        fi
        HW_VER="${HW_VER}[$(printf '%s' "${line}" | grep -oP '(?<=\<value\>).*?(?=\<\/value\>)' | tr '[:upper:]' '[:lower:]')]"
    done
fi
log_info "Signing images for HW Version(s): ${HW_VER}"


# Get list of valid image IDs from the security profile
log_debug "Creating a list of valid IMAGE-IDs"
OIFS="${IFS}"
IFS=${newline}
VALID_IMAGE_ID=""
SKIP_FIRST=0
for line in $(${SECTOOL} secure-image --available-image-ids --security-profile ${SECURITY_PROFILE})
do
    if [ "${SKIP_FIRST}" -eq 0 ]; then
        SKIP_FIRST=1
        continue
    fi
    NEW_ID=$(echo "${line}" | cut -c4-)
    log_debug "> Add mapping: ${NEW_ID}"
    VALID_IMAGE_ID="${VALID_IMAGE_ID}${NEW_ID}${newline}"
done
IFS="${OIFS}"
log_debug "> Done"

# <filename> <image_id> <pil-split-flag>
IMAGE_ID_MAPPING="\
a612_zap.mbn GPU-MICRO-CODE 0 ${newline}\
a623_zap.mbn GPU-MICRO-CODE 0 ${newline}\
a660_zap.mbn GPU-MICRO-CODE 1 ${newline}\
a663_zap.mbn GPU-MICRO-CODE 0 ${newline}\
a702_zap.mbn GPU-MICRO-CODE 0 ${newline}\
adsp.mbn ADSP 1 ${newline}\
aop.mbn AOP 0 ${newline}\
basic_sec.elf SEC-ELF 0 ${newline}\
CAMERA_ICP.mbn CAMERA-FW 0 ${newline}\
cdsp.mbn CDSP 1 ${newline}\
cdsp0.mbn CDSP0 0 ${newline}\
cdsp1.mbn CDSP1 0 ${newline}\
cpucp.elf CPUCP 0 ${newline}\
devcfg.mbn TZ-DEVCFG 0 ${newline}\
devcfg_iot.mbn TZ-DEVCFG 0 ${newline}\
gpdsp0.mbn GPDSP0 0 ${newline}\
gpdsp1.mbn GPDSP1 0 ${newline}\
hypvm.mbn QHEE 0 ${newline}\
imagefv.elf UEFIFV 0 ${newline}\
ipa_fws.mbn IPA-FW 1 ${newline}\
loadalgota64.mbn TZ-APP-OEM 1 ${newline}\
modem.mbn MPSS 0 ${newline}\
msbtfw11.mbn SKIP:BAD-FORMAT 0 ${newline}\
multi_image.mbn OEM-MISC 0 ${newline}\
multi_image_qti.mbn SKIP:OEM-MISC:QTI-SIGNED 0 ${newline}\
prog_firehose_ddr.elf DEVICE-PROGRAMMER 0 ${newline}\
prog_firehose_lite.elf DEVICE-PROGRAMMER 0 ${newline}\
qupv3fw.elf QUPV3 0 ${newline}\
rpm.mbn RPM 0 ${newline}\
sailhyp.elf SKIP:UNKNOWN 0 ${newline}\
sailsw1.elf SKIP:UNKNOWN 0 ${newline}\
sec.elf SEC-ELF 0 ${newline}\
shrm.elf SHRM 0 ${newline}\
tz.mbn TZ 0 ${newline}\
tzecotestapp.mbn TZ-APP-QTI 0 ${newline}\
uefi.elf UEFI 0 ${newline}\
uefi_dtbs.elf UEFI-DTB 0 ${newline}\
uefi_sec.mbn TZ-APP-OEM 0 ${newline}\
venus.mbn VENUS-FW 0 ${newline}\
vpu20_1v.mbn VENUS-FW 0 ${newline}\
vpu20_p1.mbn VENUS-FW 0 ${newline}\
vpu20_p1_gen2.mbn VENUS-FW 0 ${newline}\
vpu20_p1_gen2_s6.mbn VENUS-FW 0 ${newline}\
vpu30_4v.mbn VENUS-FW 0 ${newline}\
vpu30_4v_16mb.mbn VENUS-FW 0 ${newline}\
vpu30_p4.mbn VENUS-FW 0 ${newline}\
vpu30_p4_s6.mbn VENUS-FW 0 ${newline}\
vpu30_p4_s6_16mb.mbn VENUS-FW 0 ${newline}\
vpu30_p4_s7.mbn VENUS-FW 0 ${newline}\
vpu33_p4.mbn VENUS-FW 0 ${newline}\
vpu33_p4_s7.mbn VENUS-FW 0 ${newline}\
vpu35_p4.mbn VENUS-FW 0 ${newline}\
vpu35_p4_s7.mbn VENUS-FW 0 ${newline}\
vpu36_p4_s7.mbn VENUS-FW 0 ${newline}\
vpu40_p2_s7.mbn VENUS-FW 0 ${newline}\
wlanmdsp.mbn WLAN-USER-PD 0 ${newline}\
wpss.mbn WPSS 1 ${newline}\
xbl_config.elf XBL-CONFIG 0 ${newline}\
xbl_config_gunyah.elf XBL-CONFIG 0 ${newline}\
xbl_config_kvm.elf XBL-CONFIG 0 ${newline}\
xbl_feature_config.elf XBL-CONFIG 0 ${newline}\
xbl.elf XBL 0 ${newline}\
XblRamdump.elf XBL-RAM-DUMP 0 ${newline}\
DigestsToSign.bin.mbn VIP 0 ${newline}\
FD02C9DA-306C-48C7-A49C-BBD827AE86EE.mbn TZ-APP-OEM 0 ${newline}\
"

# Create a list of root certificates
ROOT_CERT_LIST=""
key=0
# Loop through ROOT_CERT_TOTALNUM
while [ "${key}" -lt ${ROOT_CERT_TOTALNUM} ]
do
    KEY_FILENAME=$(echo "${KEYS_PATH}/${KEYS_ROOT_CERT}" | sed "s/###/${key}/g")
    if [ ! -f "${KEY_FILENAME}" ]; then
        log_error "Cannot find root certificate: ${KEY_FILENAME}.  Aborting."
        exit 1
    fi
    ROOT_CERT_LIST="${ROOT_CERT_LIST} ${KEY_FILENAME}"
    # increment key counter
    key=$((key + 1))
done

KEYS_CA_KEY_FILENAME=$(echo "${KEYS_PATH}/${KEYS_CA_KEY}" | sed "s/###/${SIGNING_KEY_INDEX}/g")
if [ ! -f "${KEYS_CA_KEY_FILENAME}" ]; then
    log_error "Cannot find CA key: ${KEYS_CA_KEY_FILENAME}.  Aborting."
    exit 1
fi

KEYS_CA_CERT_FILENAME=$(echo "${KEYS_PATH}/${KEYS_CA_CERT}" | sed "s/###/${SIGNING_KEY_INDEX}/g")
if [ ! -f "${KEYS_CA_CERT_FILENAME}" ]; then
    log_error "Cannot find CA certificate: ${KEYS_CA_CERT_FILENAME}.  Aborting."
    exit 1
fi

# Signing data for more than 1 root key
ROOT_CERT_INDEX=""
if [ "${ROOT_CERT_TOTALNUM}" -gt 1 ]; then
    ROOT_CERT_INDEX="--root-certificate-index ${SIGNING_KEY_INDEX}"
fi

VERBOSE=""
if [ "${LOG_LEVEL}" -ge "${LOG_DEBUG}" ]; then
    VERBOSE="--verbose"
fi

XBL_CONFIG_FILENAME="xbl_config.elf"
if [ -f ${OUT_DIR}/uefi_dtbs.elf ]; then
    XBL_CONFIG_FILENAME="uefi_dtbs.elf"
fi
if [ -f "${OUT_DIR}/${XBL_CONFIG_FILENAME}" ] && [ -f "${FMP_PATH}/${FMP_ROOT_CER_FILE}" ]; then
    log_debug "Generate FMP root certificate hex file"
    rm -rf ./tmp-fmp-root-cert-hex.inc
    printf '0x%08x ' "$(stat -c %s ${FMP_PATH}/${FMP_ROOT_CER_FILE})" > ./tmp-fmp-root-cert-hex.inc
    hexdump --no-squeezing -e '1/1 "0x%02x" 1/1 "%02x" 1/1 "%02x" 1/1 "%02x "' ${FMP_PATH}/${FMP_ROOT_CER_FILE} | sed 's/ *$//' >> ./tmp-fmp-root-cert-hex.inc
    log_debug "> Generated"

    log_info "Adding FMP root certificate to ${XBL_CONFIG_FILENAME}."
    log_debug "> Clear old xbl_config-temp dir"
    rm -rf ${OUT_DIR}/xbl_config-temp
    log_debug "> Dumping contents of ${XBL_CONFIG_FILENAME} to ${OUT_DIR}/xbl_config-temp"
    OUTPUT=$(${SECTOOL} secure-image --dump ${OUT_DIR}/xbl_config-temp ${OUT_DIR}/${XBL_CONFIG_FILENAME})
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ]; then
        printf '%s\n' "${OUTPUT}"
        log_error "secure-image dump failed for ${OUT_DIR}/${XBL_CONFIG_FILENAME}."
        if [ "${FLAG_CONTINUE}" -eq 0 ]; then
            exit 1
        else
            RETURN_CODE=1
        fi
    else
        file_list=$(grep -l "QcCapsuleRootCert" ${OUT_DIR}/xbl_config-temp/segments/*.bin)
        found_dtb=0
        for file in ${file_list}
        do
            log_debug "> Checking ${file} for DTB values"
            if [ "$(hexdump -n 4 -e '4/1 "%02x"' ${file})" = "d00dfeed" ]; then
                log_debug "> python3 ${SCRIPT_PATH}/cbsp-boot-utilities/uefi_capsule_generation/set_dtb_property.py ${file} /sw/uefi/uefiplat QcCapsuleRootCert @list:./tmp-fmp-root-cert-hex.inc ${file}.new"
                OUTPUT=$(python3 ${SCRIPT_PATH}/cbsp-boot-utilities/uefi_capsule_generation/set_dtb_property.py \
                    ${file} /sw/uefi/uefiplat QcCapsuleRootCert @list:./tmp-fmp-root-cert-hex.inc ${file}.new)
                RESPONSE=$?
                if [ "${RESPONSE}" -ne 0 ]; then
                    printf '%s\n' "${OUTPUT}"
                    log_error "set_dtb_property failed for ${OUT_DIR}/${XBL_CONFIG_FILENAME}."
                    if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                        rm -rf ${OUT_DIR}/xbl_config-temp
                        exit 1
                    else
                        RETURN_CODE=1
                    fi
                else
                    # save the segment # for passing into xblconfig_parser
                    found_dtb=$(basename -s .bin "${file}" | sed 's/.*_//')
                    break
                fi
            fi
        done
    fi

    # cleanup tmp file
    rm ./tmp-fmp-root-cert-hex.inc

    # if changed recombine
    if [ "${found_dtb}" -gt 0 ]; then
        log_debug "> Add patched segment back into ${XBL_CONFIG_FILENAME} and recalculate hash."
        log_debug "> python3 ${SCRIPT_PATH}/cbsp-boot-utilities/uefi_capsule_generation/xblconfig_parser.py ${OUT_DIR}/${XBL_CONFIG_FILENAME} replace ${found_dtb} ${file}.new ${OUT_DIR}/${XBL_CONFIG_FILENAME}.patched"
        OUTPUT=$(python3 ${SCRIPT_PATH}/cbsp-boot-utilities/uefi_capsule_generation/xblconfig_parser.py ${OUT_DIR}/${XBL_CONFIG_FILENAME} replace \
            ${found_dtb} ${file}.new ${OUT_DIR}/${XBL_CONFIG_FILENAME}.patched)
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ]; then
            printf '%s\n' "${OUTPUT}"
            log_error "xblconfig_parser replace failed for ${OUT_DIR}/${XBL_CONFIG_FILENAME}."
            if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                rm -rf ${OUT_DIR}/xbl_config-temp
                exit 1
            else
                RETURN_CODE=1
            fi
        fi
        mv ${OUT_DIR}/${XBL_CONFIG_FILENAME}.patched ${OUT_DIR}/${XBL_CONFIG_FILENAME}
    else
        log_warn "> No post-DDR dtb was found! No changes made to ${XBL_CONFIG_FILENAME}."
    fi
    log_debug "> Cleaning up temp files"
    rm -rf ${OUT_DIR}/xbl_config-temp

    log_ok "> Completed FMP root processing for ${XBL_CONFIG_FILENAME}"
else
    [ ! -f "${OUT_DIR}/${XBL_CONFIG_FILENAME}" ] && { log_warn "No xbl_config.elf was found.  Skipping processing."; }
    [ ! -f "${FMP_PATH}/${FMP_ROOT_CER_FILE}" ] && { log_warn "No FMP root certificate found.  Skipping processing."; }
fi

log_info "Searching for MDT files without matching MBN files ..."
file_list=$(find ${OUT_DIR} -iname "*.mdt")
mbn_create_list=""
for file in ${file_list}
do
    mbn_file=$(basename "${file%.*}.mbn")
    mbn_base=$(dirname "${file}")
    log_debug "> Checking for ${mbn_base}/${mbn_file}"
    if [ ! -f "${mbn_base}/${mbn_file}" ]; then
        log_debug "> ${mbn_base}/${mbn_file} not found!  Creating from MDT fragments."
        OUTPUT=$(${SCRIPT_PATH}/bin/pil-squasher "${mbn_base}/${mbn_file}" ${file})
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
            printf '%s\n' "${OUTPUT}"
        fi
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "pil-squasher failed for ${file}."
            if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                exit 1
            else
                RETURN_CODE=1
            fi
        else
            mbn_create_list="${mbn_create_list} ${mbn_base}/${mbn_file}"
        fi
    else
        log_debug "> Found ${mbn_base}/${mbn_file}"
    fi
done

log_info "Searching for boot files to sign with OEM keys: ${KEYS_PATH}"
file_list=$(find ${OUT_DIR} -iname "*.mbn" -o -iname "*.elf")
for file in ${file_list}
do
    sign_verify "${file}" 0
done
log_ok "> Completed image signing"

# Check for rootfs.img and mount it
if [ -f "${OUT_DIR}/rootfs.img" ]; then
    log_warn "Rootfs signing requires root. Asking for root permissions (if needed) ..."
    sudo -v
    setup_mount ${OUT_DIR}/rootfs.img
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ]; then
        exit 1
    fi

    log_info "Searching rootfs for files to sign with OEM keys: ${KEYS_PATH}"
    file_list=$(sudo find ${LOOP_MOUNT} -iname "*.mbn" -o -iname "*.elf")
    for file in ${file_list}
    do
        sign_verify "${file}" 1
    done

    cleanup_mount ${LOOP_DEVICE}
    log_debug "> Unmounted rootfs.img"
    log_ok "> Completed rootfs image signing"
fi

# Handle UEFI signing workflows
if [ ! -z "${UEFI_KEYS_PATH}" ]; then
    log_info "Searching files to sign with UEFI keys: ${UEFI_KEYS_PATH}"

    # if missing, copy efi.bin into OUT_DIR for modification
    if [ ! -f ${OUT_DIR}/efi.bin ]; then
        log_debug "UEFI: Copying efi.bin to ${OUT_DIR} for modification"
        cp efi.bin ${OUT_DIR}/efi.bin
    fi

    setup_mount ${OUT_DIR}/efi.bin
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ]; then
        exit 1
    fi

    # TODO check if efi.bin was mounted ro and warn

    file_list=$(find ${LOOP_MOUNT} -iname "*vmlinuz*" -o -iname "*.efi")
    for file in ${file_list}
    do
        FILEPATH="$(echo "${file}" | sed "s:${LOOP_MOUNT}/::")"

        # remove existing signatures
        while true; do
            sbattach --remove ${file} > /dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                break
            fi
            log_debug "UEFI: Removed old signature from ${FILEPATH}"
        done

        OUTPUT=$(sbsign --key ${UEFI_KEYS_PATH}/DB.key --cert ${UEFI_KEYS_PATH}/DB.crt ${file} --output ${file} 2>&1)
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
            printf '%s\n' "${OUTPUT}"
        fi
        if [ "${RESPONSE}" -ne 0 ]; then
            log_error "UEFI: Failed to sign ${FILEPATH}"
            if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                udisksctl unmount --no-user-interaction -b ${LOOP_DEVICE} > /dev/null
                udisksctl loop-delete --no-user-interaction -b ${LOOP_DEVICE} > /dev/null
                exit 1
            else
                RETURN_CODE=1
            fi
        else
            log_info "SIGNED (efi.bin): ${FILEPATH}"
        fi
    done

    cleanup_mount ${LOOP_DEVICE}
    log_debug "> Unmounted efi.bin"

    # if missing, copy dtb.bin into OUT_DIR for modification
    if [ ! -f ${OUT_DIR}/dtb.bin ]; then
        log_debug "UEFI: Copying dtb.bin to ${OUT_DIR} for modification."
        cp dtb.bin ${OUT_DIR}/dtb.bin
    fi

    setup_mount ${OUT_DIR}/dtb.bin
    RESPONSE=$?
    if [ "${RESPONSE}" -ne 0 ]; then
        exit 1
    fi

    file_list=$(find ${LOOP_MOUNT} -iname "combined-dtb.dtb" -o -iname "qclinux_fit.img")
    if [ -z "${file_list}" ]; then
        log_error "UEFI: Unable to find dtb.bin artifact for signing."
        if [ "${FLAG_CONTINUE}" -eq 0 ]; then
            exit 1
        else
            RETURN_CODE=1
        fi
    else
        for file in ${file_list}
        do
            SIGNFILE=${file%.dtb}
            SIGNFILE=${SIGNFILE%.img}
            SIGNFILE=${SIGNFILE}.sig
            FILEPATH="$(echo "${SIGNFILE}" | sed "s:${LOOP_MOUNT}/::")"
            openssl cms -sign -inkey ${UEFI_KEYS_PATH}/DB.key -signer ${UEFI_KEYS_PATH}/DB.crt -binary -in ${file} --out ${SIGNFILE} -outform DER
            log_info "SIGNED (dtb.bin): ${FILEPATH}"
        done
    fi

    cleanup_mount ${LOOP_DEVICE}
    log_debug "> Unmounted dtb.bin"

    # look for vmlinuz in rootfs mount
    log_debug "UEFI: Searching for vmlinuz files to sign with DB key/cert."
    file_list=$(find ${OUT_DIR} -iname "*vmlinuz*")
    for file in ${file_list}
    do
        OUTPUT=$(sbsign --key ${UEFI_KEYS_PATH}/DB.key --cert ${UEFI_KEYS_PATH}/DB.crt ${file} --output ${file})
        RESPONSE=$?
        if [ "${RESPONSE}" -ne 0 ] || [ ! -z "${VERBOSE}" ]; then
            printf '%s\n' "${OUTPUT}"
            if [ "${RESPONSE}" -ne 0 ]; then
                log_error "UEFI: Failed to sign ${file}"
                if [ "${FLAG_CONTINUE}" -eq 0 ]; then
                    exit 1
                else
                    RETURN_CODE=1
                fi
            fi
        fi
        log_info "UEFI: Signed ${file} with DB key/cert."
    done

    log_ok "> Completed UEFI handling"
fi

exit ${RETURN_CODE}
