#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.

set -eu
umask 077

SECTOOL=""
SECURITY_PROFILE=""
KEYS_PATH="OEM-KEYS"
KEYS_ROOT_CERT="qpsa_rootca0.cer"
KEYS_CA_CERT="qpsa_attestca0.cer"
KEYS_CA_KEY="qpsa_attestca0.key"
KEYS_ROOTS_HASH="sha384_roots_hash.txt"
OUT_DIR="."
FORCE=0
FUSE_COUNT=0
TEMP_DIR=""

usage()
{
    cat <<'EOF'
Usage: genfuses.sh --sectoolv2 PATH --security-profile FILE [options]
                  --fuse-NAME[=VALUE] ...

Generate a signed sec.elf using the explicitly supplied individual fuse options.
Fuse names, value formats and chipset support are defined by the security profile
and validated by SecTools. Both --fuse-NAME VALUE and --fuse-NAME=VALUE are accepted.
Boolean fuse options take no value. At least one fuse option is required.

Options:
  --sectoolv2 PATH                 Qualcomm SecTools v2 executable
  --security-profile FILE         Chipset security profile XML
  --keys-path DIR                 Signing key directory (default: OEM-KEYS)
  --keys-root-cert-filename FILE   Root certificate (default: qpsa_rootca0.cer)
  --keys-ca-cert-filename FILE     CA certificate (default: qpsa_attestca0.cer)
  --keys-ca-key-filename FILE      CA private key (default: qpsa_attestca0.key)
  --keys-root-hash-filename FILE   Root hash (default: sha384_roots_hash.txt)
  --out-dir DIR                   Output directory (default: current directory)
  --force                         Replace an existing sec.elf after verification
  -h, --help                      Show this help

Signing filenames are relative to --keys-path. The default files are produced by
genkeys.sh. For its RSA keys, select sha256_roots_hash.txt as the root hash file.

List the individual fuse options available for a chipset:
  /path/to/sectools fuse-blower --security-profile /path/to/profile.xml --help

This script generates an image on the host. Device provisioning is a separate step.
EOF
}

die()
{
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup()
{
    if [ -n "$TEMP_DIR" ]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

trap cleanup 0
trap 'exit 1' HUP INT TERM

# Consume the original arguments, moving only fuse options to the end of "$@".
# The count excludes those saved options, preserving argument boundaries without
# eval, shell word splitting, or a temporary file containing fuse values.
remaining=$#
while [ "$remaining" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --force)
            FORCE=1
            shift
            remaining=$((remaining - 1))
            ;;
        --sectoolv2|--security-profile|--keys-path|--out-dir|\
        --keys-root-cert-filename|--keys-ca-cert-filename|\
        --keys-ca-key-filename|--keys-root-hash-filename)
            [ "$remaining" -ge 2 ] || die "$1 requires a value."
            case "$2" in
                ""|--*) die "$1 requires a value." ;;
            esac
            case "$1" in
                --sectoolv2) SECTOOL=$2 ;;
                --security-profile) SECURITY_PROFILE=$2 ;;
                --keys-path) KEYS_PATH=$2 ;;
                --out-dir) OUT_DIR=$2 ;;
                --keys-root-cert-filename) KEYS_ROOT_CERT=$2 ;;
                --keys-ca-cert-filename) KEYS_CA_CERT=$2 ;;
                --keys-ca-key-filename) KEYS_CA_KEY=$2 ;;
                --keys-root-hash-filename) KEYS_ROOTS_HASH=$2 ;;
            esac
            shift 2
            remaining=$((remaining - 2))
            ;;
        --fuse-group|--fuse-group=*)
            die "Select individual --fuse-NAME options instead of fuse groups."
            ;;
        --fuse-*)
            fuse_arg=$1
            fuse_name=${fuse_arg%%=*}
            case "$fuse_name" in
                --fuse-|*[!a-z0-9-]*)
                    die "Invalid fuse option name. See --help."
                    ;;
            esac
            shift
            remaining=$((remaining - 1))
            case "$fuse_arg" in
                *=)
                    die "$fuse_name requires a nonempty value."
                    ;;
                *=*)
                    ;;
                *)
                    if [ "$remaining" -gt 0 ]; then
                        case "$1" in
                            --*|-h) ;;
                            "")
                                die "$fuse_name requires a nonempty value."
                                ;;
                            *)
                                fuse_arg="${fuse_arg}=$1"
                                shift
                                remaining=$((remaining - 1))
                                ;;
                        esac
                    fi
                    ;;
            esac
            set -- "$@" "$fuse_arg"
            FUSE_COUNT=$((FUSE_COUNT + 1))
            ;;
        *)
            die "Unknown argument. Use --help for wrapper options and SecTools help for fuse options."
            ;;
    esac
done

[ "$FUSE_COUNT" -gt 0 ] || die "At least one individual --fuse-NAME option is required."
[ -n "$SECTOOL" ] || die "Missing --sectoolv2."
[ -n "$SECURITY_PROFILE" ] || die "Missing --security-profile."
command -v "$SECTOOL" >/dev/null 2>&1 || die "SecTools executable not found."
[ -f "$SECURITY_PROFILE" ] || die "Security profile file not found."

root_cert="${KEYS_PATH}/${KEYS_ROOT_CERT}"
ca_cert="${KEYS_PATH}/${KEYS_CA_CERT}"
ca_key="${KEYS_PATH}/${KEYS_CA_KEY}"
hash_file="${KEYS_PATH}/${KEYS_ROOTS_HASH}"
for signing_file in "$root_cert" "$ca_cert" "$ca_key" "$hash_file"; do
    if [ ! -r "$signing_file" ] || [ ! -f "$signing_file" ]; then
        die "Missing or unreadable signing input: $signing_file"
    fi
done

# OpenSSL's digest output ends in the hash, even when its filename has spaces.
root_hash=$(awk 'NF { print $NF }' < "$hash_file")
case "$root_hash" in
    ""|*[!0-9a-fA-F]*) die "Root hash file must contain one hexadecimal digest." ;;
esac
case "${#root_hash}" in
    64|96|128) ;;
    *) die "Root hash must be a SHA-256, SHA-384 or SHA-512 digest." ;;
esac

mkdir -p -- "$OUT_DIR"
outfile="${OUT_DIR%/}/sec.elf"
[ ! -d "$outfile" ] || die "Output path is a directory: $outfile"
if [ "$FORCE" -eq 0 ] && { [ -e "$outfile" ] || [ -L "$outfile" ]; }; then
    die "Output already exists; choose another --out-dir or use --force."
fi
TEMP_DIR=$(mktemp -d -- "${OUT_DIR%/}/.genfuses.XXXXXXXX")

printf 'Generating sec.elf with %s explicitly selected fuse option(s).\n' "$FUSE_COUNT"
"$SECTOOL" fuse-blower \
    --security-profile "$SECURITY_PROFILE" \
    --generate --sign --signing-mode LOCAL \
    --root-certificate "$root_cert" \
    --ca-certificate "$ca_cert" --ca-key "$ca_key" \
    --outfile "$TEMP_DIR/sec.elf" \
    "$@"

[ -s "$TEMP_DIR/sec.elf" ] || die "SecTools did not produce sec.elf."
"$SECTOOL" fuse-blower --verify-root "0x${root_hash}" "$TEMP_DIR/sec.elf"

# Publish only after both generation and verification succeed. A hard link
# prevents replacing a concurrently created output when --force is absent.
if [ "$FORCE" -eq 1 ]; then
    mv -fT -- "$TEMP_DIR/sec.elf" "$outfile"
else
    ln -T -- "$TEMP_DIR/sec.elf" "$outfile"
fi
printf 'Generated %s\n' "$outfile"
