#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.

# Break on errors
set -e

# Settings
SCRIPT_DIR="$(dirname "$(realpath -- "$0")")"
OUT_DIR="OEM-KEYS"
RSA_KEY_SIZE=2048
RSA_VALID_KEY_SIZES="2048 4096"
MIN_OPENSSL_VER="1.1.1"
USE_OPENSSL1=0
ROOT_CERT_TOTALNUM=1
ROOT_CERT_SUBJECT="/CN=OEM Root CA ###/O=SecTools/OU=OEM Key/L=San Diego/ST=California/C=US"
CA_CERT_SUBJECT="/CN=OEM Attestation CA ###/O=SecTools/OU=OEM Key/L=San Diego/ST=California/C=US"
FMP_CA_DIR="demoCA"
FMP_ROOT_CERT_SUBJECT="/CN=OEM Root CA/O=FMP/OU=OEM Key/L=San Diego/ST=California/C=US"
FMP_CA_CERT_SUBJECT="/CN=OEM Intermediate CA/O=FMP/OU=OEM Key/L=San Diego/ST=California/C=US"
FMP_USER_CERT_SUBJECT="/CN=OEM User/O=FMP/OU=OEM Key/L=San Diego/ST=California/C=US"
FMP_KEY_SIZE=2048
FMP_KEY_PASSWORD=""
SHA_HASH_SIZE="384"

# Flags
DEBUG=0
FORCE=0
QUIET=0
USE_ECDSA=1

parse_args()
{
    while [ $# -gt 0 ]
    do
        case $1 in
        --ca-cert-subject)
            CA_CERT_SUBJECT=$2
            echo "FLAG: CA_CERT_SUBJECT: ${CA_CERT_SUBJECT}"
            shift
            shift
            ;;
        --debug)
            DEBUG=1
            echo "FLAG: Debug: enabled"
            shift
            ;;
        --fmp-ca-cert-subject)
            FMP_CA_CERT_SUBJECT=$2
            echo "FLAG: FMP_CA_CERT_SUBJECT: ${FMP_CA_CERT_SUBJECT}"
            shift
            shift
            ;;
        --fmp-key-password)
            FMP_KEY_PASSWORD=$2
            echo "FLAG: FMP_KEY_PASSWORD: (set)"
            shift
            shift
            ;;
        --fmp-root-cert-subject)
            FMP_ROOT_CERT_SUBJECT=$2
            echo "FLAG: FMP_ROOT_CERT_SUBJECT: ${FMP_ROOT_CERT_SUBJECT}"
            shift
            shift
            ;;
        --fmp-user-cert-subject)
            FMP_USER_CERT_SUBJECT=$2
            echo "FLAG: FMP_USER_CERT_SUBJECT: ${FMP_USER_CERT_SUBJECT}"
            shift
            shift
            ;;
        --force)
            FORCE=1
            echo "FLAG: Force overwrite: enabled"
            shift
            ;;
        --quiet)
            QUIET=1
            echo "FLAG: Quiet mode"
            shift
            ;;
        --root-cert-subject)
            ROOT_CERT_SUBJECT=$2
            echo "FLAG: ROOT_CERT_SUBJECT: ${ROOT_CERT_SUBJECT}"
            shift
            shift
            ;;
        --root-cert-totalnum)
            case $2 in
                1)
                    ROOT_CERT_TOTALNUM=$2
                    echo "FLAG: ROOT_CERT_TOTALNUM: ${ROOT_CERT_TOTALNUM}"
                    ;;
                *)
                    echo >&2 "ERROR: ROOT_CERT_TOTALNUM values can only be 1.  Aborting."
                    exit 1
                    ;;
            esac
            shift
            shift
            ;;
        --rsa-key-size)
            found=0
            for value in ${RSA_VALID_KEY_SIZES}; do
                if [ "$2" = "${value}" ]; then
                    RSA_KEY_SIZE=$2
                    echo "FLAG: RSA_KEY_SIZE=${RSA_KEY_SIZE}"
                    found=1
                    break
                fi
            done
            if [ "${found}" -eq 0 ]; then
                echo "Invalid key size: $2.  Valid values: 2048 or 4096.  Aborting."
                exit 1
            fi
            shift
            shift
            ;;
        --use-rsa)
            USE_ECDSA=0
            SHA_HASH_SIZE="256"
            echo "FLAG: Use RSA: enabled"
            shift
            ;;
        --help)
            echo "Usage parameters:"
            echo "--ca-cert-subject: subject data for CA cert(s)."
            echo "  Make sure to use quotes and place ### where the key # should go."
            echo "--debug: enables debug logging"
            echo "--fmp-ca-cert-subject: subject data for FMP CA cert"
            echo "--fmp-key-password: password for all FMP keys"
            echo "--fmp-root-cert-subject: subject data for FMP root cert"
            echo "--fmp-user-cert-subject: subject data for FMP user cert"
            echo "--force: force overwrite files (dangerous!)"
            echo "--quiet: disable normal logging"
            echo "--root-cert-subject: subject data for root cert(s)"
            echo "  Make sure to use quotes and place ### where the key # should go."
            echo "--root-cert-totalnum: set # of root certs to use. 1-4 allowed (default: ${ROOT_CERT_TOTALNUM})"
            echo "--rsa-key-size: set RSA key size to 2048 or 4096"
            echo "--use-rsa: Use RSA instead of ECDSA for generating keys (default: use ECDSA)"
            exit 0
            ;;
        *)
            shift
            ;;
        esac
    done
}

parse_args "$@"

debug_log()
{
    if [ "${DEBUG}" -eq 1 ]; then
        echo "DEBUG: $1"
    fi
}

log()
{
    if [ "${QUIET}" -ne 1 ]; then
        echo "$1"
    fi
}

version_greater_equal()
{
    printf '%s\n%s\n' "$2" "$1" | sort --check=quiet --version-sort
}


# Checks

log "Check for dependencies"
command -v openssl >/dev/null 2>&1 || { echo >&2 "Missing openssl command.  Aborting."; exit 1; }
command -v hexdump >/dev/null 2>&1 || { echo >&2 "Missing hexdump command.  Aborting."; exit 1; }

OPENSSL_VERSION=$(openssl version | cut -d' ' -f2)
log "Check openssl version (${OPENSSL_VERSION}) >= ${MIN_OPENSSL_VER}"
version_greater_equal "${OPENSSL_VERSION}" ${MIN_OPENSSL_VER} || { echo >&2 "Need at least openssl ${MIN_OPENSSL_VER}.  Aborting."; exit 1; }
log "> openssl version == ${OPENSSL_VERSION}"
if [ "$(echo ${OPENSSL_VERSION} | cut -c1)" -eq 1 ]; then
    USE_OPENSSL1=1
    log "> Using OpenSSL 1.x commands"
fi
log "> dependencies: OK"

log "Check for ${OUT_DIR} directory"
if [ ! -d "${OUT_DIR}" ]; then
    log "> Creating ${OUT_DIR} directory"
    mkdir ${OUT_DIR}
else
    log "> Found ${OUT_DIR} directory"
fi

log "Check for ${OUT_DIR}/${FMP_CA_DIR} directory"
if [ ! -d "${OUT_DIR}/${FMP_CA_DIR}" ]; then
    log "> Creating ${OUT_DIR}/${FMP_CA_DIR} directory"
    mkdir ${OUT_DIR}/${FMP_CA_DIR}
else
    log "> Found ${OUT_DIR}/${FMP_CA_DIR} directory"
fi

if [ "x${FMP_KEY_PASSWORD}" = "x" ]; then
    echo "> ERROR: please set FMP key password with --fmp-key-password param.  Aborting."
    exit 1
fi

log "Checking for existing keys"
KEYS_FOUND=0
ls ${OUT_DIR}/*.key >/dev/null 2>&1 && KEYS_FOUND=1
ls ${OUT_DIR}/*.cer >/dev/null 2>&1 && KEYS_FOUND=1
ls ${OUT_DIR}/${FMP_CA_DIR}/*.key >/dev/null 2>&1 && KEYS_FOUND=1
ls ${OUT_DIR}/${FMP_CA_DIR}/*.cer >/dev/null 2>&1 && KEYS_FOUND=1
ls ${OUT_DIR}/${FMP_CA_DIR}/*.pem >/dev/null 2>&1 && KEYS_FOUND=1
ls ${OUT_DIR}/${FMP_CA_DIR}/*.pfx >/dev/null 2>&1 && KEYS_FOUND=1
if [ "${KEYS_FOUND}" -eq 1 ]; then
    if [ "${FORCE}" -eq 1 ]; then
        echo "> Force flag enabled: overwriting existing keys!"
    else
        echo "> Existing keys found.  Aborting."
        exit 1
    fi
else
    echo "> No keys found.  Proceeding."
fi


# Generate a randfile

log "Generating randfile"
dd if=/dev/urandom of=randfile bs=256 count=1 > /dev/null 2>&1
log "> Generated."


key=0
# Loop through ROOT_CERT_TOTALNUM
while [ "${key}" -lt ${ROOT_CERT_TOTALNUM} ]
do
    if [ "${USE_ECDSA}" -eq 1 ]; then

        # Generate ECDSA root key and certificate (SHA384)
        # QLI 1.8: https://docs.qualcomm.com/doc/80-70029-11/topic/generate-keys-and-certificates.html?product=895724676033554725&facet=Security&version=1.8#option-1-generate-ecdsa-root-key-and-certificate

        log "Generate the ECDSA root ${key} key and certificate"

        openssl ecparam -genkey -name secp384r1 -outform PEM -out ${OUT_DIR}/qpsa_rootca${key}.key
        log "> Created ECDSA root ${key} key"

        openssl req -new -key ${OUT_DIR}/qpsa_rootca${key}.key -sha${SHA_HASH_SIZE} -out ${OUT_DIR}/rootca${key}_pem.crt \
            -subj "$(echo "${ROOT_CERT_SUBJECT}" | sed "s/###/${key}/g")" \
            -config ${SCRIPT_DIR}/opensslroot.cfg -x509 -days 7300 -set_serial 1

        openssl x509 -in ${OUT_DIR}/rootca${key}_pem.crt -inform PEM -out ${OUT_DIR}/qpsa_rootca${key}.cer -outform DER
        log "> Created ECDSA root ${key} certificate"

        log "Generate the intermediate certificate authority (CA) ${key} key and certificate"

        openssl ecparam -genkey -name secp384r1 -outform PEM -out ${OUT_DIR}/qpsa_attestca${key}.key
        log "> Created EC Atrestation CA ${key} key"

        openssl req -new -key ${OUT_DIR}/qpsa_attestca${key}.key -out ${OUT_DIR}/ca${key}.csr \
            -subj "$(echo "${CA_CERT_SUBJECT}" | sed "s/###/${key}/g")" \
            -config ${SCRIPT_DIR}/opensslroot.cfg -sha${SHA_HASH_SIZE}

        openssl x509 -req -in ${OUT_DIR}/ca${key}.csr -CA ${OUT_DIR}/rootca${key}_pem.crt -CAkey ${OUT_DIR}/qpsa_rootca${key}.key \
            -out ${OUT_DIR}/attestca${key}_pem.crt -set_serial 1 -days 7300 -extfile ${SCRIPT_DIR}/v3.ext -sha${SHA_HASH_SIZE} -CAcreateserial

        openssl x509 -inform PEM -in ${OUT_DIR}/attestca${key}_pem.crt -outform DER -out ${OUT_DIR}/qpsa_attestca${key}.cer
        log "> Created EC Attestation CA ${key} certificate"

    else
        # Generate RSA CA key pair and certificate (SHA256)
        # QLI 1.8: https://docs.qualcomm.com/doc/80-70029-11/topic/generate-keys-and-certificates.html?product=895724676033554725&facet=Security&version=1.8#option-2-generate-rsa-key-pair-and-certificate

        log "Generate the root CA ${key} key and certificate"

        openssl genrsa -out ${OUT_DIR}/qpsa_rootca${key}.key ${RSA_KEY_SIZE}
        log "> Created RSA root CA ${key} key"

        if [ "${USE_OPENSSL1}" -eq 1 ]; then
            openssl req -new -sha${SHA_HASH_SIZE} -key ${OUT_DIR}/qpsa_rootca${key}.key -x509 -out ${OUT_DIR}/rootca_pem${key}.crt \
                -subj "$(echo "${ROOT_CERT_SUBJECT}" | sed "s/###/${key}/g")" \
                -days 7300 -set_serial 1 -config ${SCRIPT_DIR}/opensslroot.cfg -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1 -sigopt digest:sha${SHA_HASH_SIZE}
        else
            openssl req -new -sha${SHA_HASH_SIZE} -key ${OUT_DIR}/qpsa_rootca${key}.key -x509 -out ${OUT_DIR}/rootca_pem${key}.crt \
                -subj "$(echo "${ROOT_CERT_SUBJECT}" | sed "s/###/${key}/g")" \
                -days 7300 -set_serial 1 -config ${SCRIPT_DIR}/opensslroot.cfg -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1
        fi

        openssl x509 -in ${OUT_DIR}/rootca_pem${key}.crt -inform PEM -out ${OUT_DIR}/qpsa_rootca${key}.cer -outform DER
        log "> Created RSA root CA certificate"

        log "Generate the attestation CA ${key} key and certificate"

        openssl genrsa -out ${OUT_DIR}/qpsa_attestca${key}.key ${RSA_KEY_SIZE}
        log "> Created RSA Attestation CA ${key} key"

        openssl req -new -key ${OUT_DIR}/qpsa_attestca${key}.key -out ${OUT_DIR}/attestca${key}.csr \
            -subj "$(echo "${CA_CERT_SUBJECT}" | sed "s/###/${key}/g")" \
            -config ${SCRIPT_DIR}/opensslroot.cfg -sha${SHA_HASH_SIZE}

        if [ "${USE_OPENSSL1}" -eq 1 ]; then
            openssl x509 -req -in ${OUT_DIR}/attestca${key}.csr -CA ${OUT_DIR}/rootca_pem${key}.crt -CAkey ${OUT_DIR}/qpsa_rootca${key}.key \
                -out ${OUT_DIR}/attestca${key}_pem.crt -sha${SHA_HASH_SIZE} -set_serial 5 -days 7300 -extfile ${SCRIPT_DIR}/v3.ext -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1 -sigopt digest:sha${SHA_HASH_SIZE}
        else
            openssl x509 -req -in ${OUT_DIR}/attestca${key}.csr -CA ${OUT_DIR}/rootca_pem${key}.crt -CAkey ${OUT_DIR}/qpsa_rootca${key}.key \
                -out ${OUT_DIR}/attestca${key}_pem.crt -sha${SHA_HASH_SIZE} -set_serial 5 -days 7300 -extfile ${SCRIPT_DIR}/v3.ext -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1
        fi

        openssl x509 -inform PEM -in ${OUT_DIR}/attestca${key}_pem.crt -outform DER -out ${OUT_DIR}/qpsa_attestca${key}.cer

        rm ${OUT_DIR}/*.crt && true
        log "> Created RSA Attestation CA ${key} certificate"
    fi

    # increment key counter
    key=$((key + 1))
done

# Generate SHA256 hash for RSA and SHA384 for ECDSA
# QLI 1.8: https://docs.qualcomm.com/doc/80-70029-11/topic/generate-keys-and-certificates.html?product=895724676033554725&facet=Security&version=1.8

log "Generate SHA${SHA_HASH_SIZE} hash for signing"
key=0
rm -rf ${OUT_DIR}/qpsa_roots.bin
# Loop through ROOT_CERT_TOTALNUM
while [ "${key}" -lt ${ROOT_CERT_TOTALNUM} ]
do
    debug_log "> Adding root ${key} cert"
    cat ${OUT_DIR}/qpsa_rootca${key}.cer >> ${OUT_DIR}/qpsa_roots.bin

    # increment key counter
    key=$((key + 1))
done
openssl dgst -sha${SHA_HASH_SIZE} ${OUT_DIR}/qpsa_roots.bin >${OUT_DIR}/sha${SHA_HASH_SIZE}_roots_hash.txt
rm ${OUT_DIR}/${OUT_DIR}/qpsa_roots.bin && true
log "> Created"

# Generate FMP (Firmware Management Protocol keys)
# https://github.com/tianocore/tianocore.github.io/wiki/Capsule-Based-System-Firmware-Update-Generate-Keys

log "Initialize FMP CA dir"
mkdir -p ${OUT_DIR}/${FMP_CA_DIR}/newcerts
touch ${OUT_DIR}/${FMP_CA_DIR}/index.txt
echo 01 > ${OUT_DIR}/${FMP_CA_DIR}/serial
log "> Initialized"

# NOTE: The following commands have to be run from the local path where "./demoCA" exists
# save our current location (in case we want it later)
ORIG_DIR="$(pwd)"
# copy our randomness file along with us
cp randfile ${OUT_DIR}/
cd ${OUT_DIR}/

log "Create FMP root key/certificate"
openssl genrsa -aes256 -passout "pass:${FMP_KEY_PASSWORD}" \
    -out ${FMP_CA_DIR}/QcFMPRoot.key ${FMP_KEY_SIZE}
openssl req -new -x509 -config ${SCRIPT_DIR}/opensslroot.cfg -subj "${FMP_ROOT_CERT_SUBJECT}" -days 3650 \
    -passin "pass:${FMP_KEY_PASSWORD}" -key ${FMP_CA_DIR}/QcFMPRoot.key \
    -out ${FMP_CA_DIR}/QcFMPRoot.crt
openssl x509 -in ${FMP_CA_DIR}/QcFMPRoot.crt \
    -out ${FMP_CA_DIR}/QcFMPRoot.cer -outform DER
openssl x509 -inform DER -in ${FMP_CA_DIR}/QcFMPRoot.cer \
    -outform PEM -out ${FMP_CA_DIR}/QcFMPRoot.pub.pem
log "> Created"

log "Create FMP intermediate CA key/certificate"
# Enter passphrase
openssl genrsa -aes256 -passout "pass:${FMP_KEY_PASSWORD}" \
    -out ${FMP_CA_DIR}/QcFMPSub.key ${FMP_KEY_SIZE}
openssl req -new -config ${SCRIPT_DIR}/opensslroot.cfg -subj "${FMP_CA_CERT_SUBJECT}" \
    -passin "pass:${FMP_KEY_PASSWORD}" -key ${FMP_CA_DIR}/QcFMPSub.key \
    -out ${FMP_CA_DIR}/QcFMPSub.csr
openssl ca -config ${SCRIPT_DIR}/opensslroot.cfg -extensions v3_ca -batch \
    -in ${FMP_CA_DIR}/QcFMPSub.csr -days 3650 \
    -out ${FMP_CA_DIR}/QcFMPSub.crt -cert ${FMP_CA_DIR}/QcFMPRoot.crt \
    -passin "pass:${FMP_KEY_PASSWORD}" -keyfile ${FMP_CA_DIR}/QcFMPRoot.key
openssl x509 -in ${FMP_CA_DIR}/QcFMPSub.crt \
    -out ${FMP_CA_DIR}/QcFMPSub.cer -outform DER
openssl x509 -inform DER -in ${FMP_CA_DIR}/QcFMPSub.cer \
    -outform PEM -out ${FMP_CA_DIR}/QcFMPSub.pub.pem
log "> Created"

log "Create FMP user key/certificate for data signing"
openssl genrsa -aes256 -passout "pass:${FMP_KEY_PASSWORD}" \
    -out ${FMP_CA_DIR}/QcFMPCert.key ${FMP_KEY_SIZE}
openssl req -new -config ${SCRIPT_DIR}/opensslroot.cfg -subj "${FMP_USER_CERT_SUBJECT}" \
    -passin "pass:${FMP_KEY_PASSWORD}" -key ${FMP_CA_DIR}/QcFMPCert.key \
    -out ${FMP_CA_DIR}/QcFMPCert.csr
openssl ca -config ${SCRIPT_DIR}/opensslroot.cfg -batch \
    -in ${FMP_CA_DIR}/QcFMPCert.csr -days 3650 \
    -out ${FMP_CA_DIR}/QcFMPCert.crt -cert ${FMP_CA_DIR}/QcFMPSub.crt \
    -passin "pass:${FMP_KEY_PASSWORD}" -keyfile ${FMP_CA_DIR}/QcFMPSub.key
openssl x509 -in ${FMP_CA_DIR}/QcFMPCert.crt \
    -out ${FMP_CA_DIR}/QcFMPCert.cer -outform DER
openssl x509 -inform DER -in ${FMP_CA_DIR}/QcFMPCert.cer \
    -outform PEM -out ${FMP_CA_DIR}/QcFMPCert.pub.pem
log "> Created"

log "Convert FMP user key to PKCS12 format"
openssl pkcs12 -export -passout "pass:${FMP_KEY_PASSWORD}" -out ${FMP_CA_DIR}/QcFMPCert.pfx \
    -passin "pass:${FMP_KEY_PASSWORD}" -inkey ${FMP_CA_DIR}/QcFMPCert.key \
    -in ${FMP_CA_DIR}/QcFMPCert.crt
openssl pkcs12 -passin "pass:${FMP_KEY_PASSWORD}" -in ${FMP_CA_DIR}/QcFMPCert.pfx -nodes \
    -out ${FMP_CA_DIR}/QcFMPCert.pem
log "> Converted"

log "Generate FMP root hex file"
printf '0x%08x ' "$(stat -c %s ${FMP_CA_DIR}/QcFMPRoot.cer)" > ${FMP_CA_DIR}/QcFMPRoot.inc
hexdump --no-squeezing -e '1/1 "0x%02x" 1/1 "%02x" 1/1 "%02x" 1/1 "%02x "' ${FMP_CA_DIR}/QcFMPRoot.cer | sed 's/ *$//' >> ${FMP_CA_DIR}/QcFMPRoot.inc
log "> Generated"

# cleanup randfile
rm randfile
# Go back the original dir
cd ${ORIG_DIR}

# Clean up

log "Cleaning up"

rm randfile
rm ${OUT_DIR}/*.csr
rm ${OUT_DIR}/${FMP_CA_DIR}/*.csr

log "> Done"
