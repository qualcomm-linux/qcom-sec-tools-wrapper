#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Exercise the Makefile against stub scripts that log their arguments.
# shellcheck disable=SC2016  # stub bodies are evaluated by the stubs

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
new_sandbox

cp "$ROOT/Makefile" "$ROOT/.env.sample" "$SANDBOX"/
CALLS="$SANDBOX/calls.log"
OUT="$SANDBOX/out.log"
export CALLS

# stub NAME [BODY]: create a script that logs "NAME args" then runs BODY.
stub() {
    {
        echo '#!/bin/sh'
        printf "printf '%%s %%s\\\\n' '%s' \"\$*\" >> \"\$CALLS\"\n" "$1"
        [ $# -gt 1 ] && echo "$2"
        echo 'exit 0'
    } > "$SANDBOX/$1"
    chmod +x "$SANDBOX/$1"
}

stub signimages.sh
stub genkeys.sh
stub gencapsule.sh
stub secure.sh 'while [ $# -gt 0 ]; do [ "$1" = --out-dir ] && touch "$2/sec.elf"; shift; done'
stub sectools 'while [ $# -gt 0 ]; do [ "$1" = --outfile ] && touch "$2"; shift; done'
stub qdl 'for a in "$@"; do case $a in --create-digests=*) d=${a#*=}; mkdir -p "$d"; touch "$d/DigestsToSign.bin";; esac; done'
stub fetch-sectools.sh "echo '$SANDBOX/sectools'"
stub fetch-qdl.sh "echo '$SANDBOX/qdl'"
stub fetch-security-profile.sh "case \$QCOM_SEC_PROFILE in */*) echo \"\$QCOM_SEC_PROFILE\";; *) echo \"$SANDBOX/profiles/\$QCOM_SEC_PROFILE\";; esac"

mkdir -p "$SANDBOX/flat"
echo '<program label="xbl" filename="xbl.elf"/><program label="secdata" filename=""/>' > "$SANDBOX/flat/rawprogram0.xml"
echo '<patches/>' > "$SANDBOX/flat/patch0.xml"
touch "$SANDBOX/flat/a.mbn" "$SANDBOX/flat/prog_firehose_ddr.elf"

PROFILE=kodiak_security_profile.xml
SIGNED="$SANDBOX/signed-build"
VIP="$SIGNED/vip-tables"

run_make() {
    : > "$CALLS"
    (cd "$SANDBOX" && make --no-print-directory "$@") > "$OUT" 2>&1
}
calls() { grep "^$1 " "$CALLS"; }
line_of() { grep -n -- "$1" "$CALLS" | head -1 | cut -d: -f1; }

# --- help ---------------------------------------------------------------
assert_ok "help succeeds" run_make help
assert_grep "help lists sign-build-with-fuse-blower" "sign-build-with-fuse-blower" "$OUT"
assert_grep "default goal is help" "make targets" "$OUT"

# --- guards -------------------------------------------------------------
assert_fails "sign-build without profile fails" run_make sign-build QCOM_FLAT_BUILD="$SANDBOX/flat"
assert_grep "guard names QCOM_SEC_PROFILE" "QCOM_SEC_PROFILE is not set" "$OUT"
assert_fails "sign-build without flat build fails" run_make sign-build QCOM_SEC_PROFILE=$PROFILE
assert_grep "guard names QCOM_FLAT_BUILD" "QCOM_FLAT_BUILD is not set" "$OUT"
assert_fails "gen-fuse-blower without fuse ids fails" run_make gen-fuse-blower QCOM_SEC_PROFILE=$PROFILE
assert_grep "guard names QCOM_FUSE_OEM_HW_ID" "QCOM_FUSE_OEM_HW_ID is not set" "$OUT"
assert_fails "generate-keys without password fails" run_make generate-keys
assert_grep "guard names QCOM_FMP_KEY_PASSWORD" "QCOM_FMP_KEY_PASSWORD is not set" "$OUT"

# --- deps ---------------------------------------------------------------
assert_ok "deps succeeds" run_make deps QCOM_SEC_PROFILE=$PROFILE
assert_grep "deps fetches sectools" "^fetch-sectools.sh" "$CALLS"
assert_grep "deps resolves the profile" "^fetch-security-profile.sh" "$CALLS"
assert_grep "deps fetches qdl" "^fetch-qdl.sh" "$CALLS"
assert_ok "deps with VIP disabled succeeds" run_make deps QCOM_VIP_DISABLE=1
assert_not_grep "deps skips qdl when VIP disabled" "^fetch-qdl.sh" "$CALLS"
assert_not_grep "deps skips profile when unset" "^fetch-security-profile.sh" "$CALLS"

# --- sign-build, VIP disabled -------------------------------------------
assert_ok "sign-build (no VIP) succeeds" run_make sign-build QCOM_SEC_PROFILE=$PROFILE QCOM_FLAT_BUILD="$SANDBOX/flat" QCOM_VIP_DISABLE=1
assert_file "build is staged" "$SIGNED/a.mbn"
assert_eq "signimages called once" 1 "$(calls signimages.sh | wc -l)"
assert_grep "signimages gets sectools" "signimages.sh --sectoolv2 $SANDBOX/sectools " "$CALLS"
assert_grep "signimages gets resolved profile" "--security-profile $SANDBOX/profiles/$PROFILE " "$CALLS"
assert_grep "signimages gets keys" "--keys-path OEM-KEYS --fmp-path OEM-KEYS/demoCA " "$CALLS"
assert_grep "signimages gets defaults" "--root-cert-totalnum 1 --signing-key-index 0 " "$CALLS"
assert_grep "signimages gets out-dir" "--out-dir $SIGNED\$" "$CALLS"
assert_not_grep "no UEFI flag by default" "--uefi-keys-path" "$CALLS"
assert_not_grep "no qdl when VIP disabled" "^qdl " "$CALLS"
assert_grep "VIP skip is reported" "skipping VIP" "$OUT"

# --- sign-build, VIP enabled --------------------------------------------
assert_ok "sign-build (VIP) succeeds" run_make sign-build QCOM_SEC_PROFILE=$PROFILE QCOM_FLAT_BUILD="$SANDBOX/flat"
assert_grep "qdl creates digests" "^qdl --allow-fusing --dry-run --create-digests=$VIP prog_firehose_ddr.elf rawprogram0.xml patch0.xml\$" "$CALLS"
assert_grep "sectools wraps the table" "^sectools mbn-tool generate --data $VIP/DigestsToSign.bin --mbn-version 6 --outfile $VIP/DigestsToSign.bin.mbn\$" "$CALLS"
assert_eq "signimages called twice" 2 "$(calls signimages.sh | wc -l)"
assert_grep "VIP table is signed" "signimages.sh .*--out-dir $VIP\$" "$CALLS"
assert_file "VIP table exists" "$VIP/DigestsToSign.bin.mbn"

# --- overrides ----------------------------------------------------------
assert_ok "sign-build with UEFI keys succeeds" run_make sign-build QCOM_SEC_PROFILE=$PROFILE QCOM_FLAT_BUILD="$SANDBOX/flat" QCOM_VIP_DISABLE=1 QCOM_UEFI_KEYS=/uefi
assert_grep "UEFI flag is passed" "--uefi-keys-path /uefi" "$CALLS"
assert_ok "sign-build with profile path succeeds" run_make sign-build QCOM_SEC_PROFILE=/abs/p.xml QCOM_FLAT_BUILD="$SANDBOX/flat" QCOM_VIP_DISABLE=1
assert_grep "profile path is passed through" "--security-profile /abs/p.xml " "$CALLS"
assert_ok "sign-build with key overrides succeeds" run_make sign-build QCOM_SEC_PROFILE=$PROFILE QCOM_FLAT_BUILD="$SANDBOX/flat" QCOM_VIP_DISABLE=1 QCOM_ROT_KEYS=/keys QCOM_ROOT_CERT_TOTALNUM=4 QCOM_SIGNING_KEY_INDEX=2
assert_grep "key overrides are passed" "--keys-path /keys --fmp-path /keys/demoCA --security-profile .* --root-cert-totalnum 4 --signing-key-index 2 " "$CALLS"

# --- gen-fuse-blower ----------------------------------------------------
FUSES="QCOM_FUSE_OEM_HW_ID=0x1 QCOM_FUSE_OEM_PRODUCT_ID=0x2 QCOM_FUSE_SEC_KEY_DERIVATION_KEY=0x3"
# shellcheck disable=SC2086
assert_ok "gen-fuse-blower succeeds" run_make gen-fuse-blower QCOM_SEC_PROFILE=$PROFILE $FUSES
assert_grep "secure.sh creates sec.elf" "^secure.sh --create-sec-elf --sectoolv2 $SANDBOX/sectools " "$CALLS"
assert_grep "secure.sh gets fuse ids" "--fuse-oem-hw-id 0x1 --fuse-oem-product-id 0x2 --fuse-sec-key-derivation-key 0x3 " "$CALLS"
assert_grep "secure.sh gets profile" "--security-profile $SANDBOX/profiles/$PROFILE " "$CALLS"
assert_file "sec.elf lands in signed build" "$SIGNED/sec.elf"

# --- sign-build-with-fuse-blower ----------------------------------------
# shellcheck disable=SC2086
assert_ok "sign-build-with-fuse-blower succeeds" run_make sign-build-with-fuse-blower QCOM_SEC_PROFILE=$PROFILE QCOM_FLAT_BUILD="$SANDBOX/flat" $FUSES
assert_grep "sec.elf wired into rawprogram" 'label="secdata" filename="sec.elf"' "$SIGNED/rawprogram0.xml"
assert_grep "flat build untouched" 'label="secdata" filename=""' "$SANDBOX/flat/rawprogram0.xml"
assert_file "VIP table generated" "$VIP/DigestsToSign.bin.mbn"
assert_eq "signimages called twice" 2 "$(calls signimages.sh | wc -l)"
sign_l=$(line_of "^signimages.sh .*--out-dir $SIGNED")
sec_l=$(line_of "^secure.sh ")
qdl_l=$(line_of "^qdl .*--create-digests")
vip_l=$(line_of "^signimages.sh .*--out-dir $VIP")
if [ "$sign_l" -lt "$sec_l" ] && [ "$sec_l" -lt "$qdl_l" ] && [ "$qdl_l" -lt "$vip_l" ]; then
    pass "order: sign, sec.elf, digests, VIP sign"
else
    fail "order: sign, sec.elf, digests, VIP sign" "$(cat "$CALLS")"
fi

# --- flash --------------------------------------------------------------
assert_ok "flash with VIP table succeeds" run_make flash
assert_grep "flash passes VIP table and storage" "^qdl --allow-fusing --storage ufs --vip-table-path=$VIP prog_firehose_ddr.elf rawprogram0.xml patch0.xml\$" "$CALLS"
assert_ok "flash with VIP disabled succeeds" run_make flash QCOM_VIP_DISABLE=1 QCOM_STORAGE=emmc
assert_grep "flash honours storage" "^qdl --allow-fusing --storage emmc prog_firehose_ddr.elf" "$CALLS"
assert_not_grep "flash omits VIP table when disabled" "--vip-table-path" "$CALLS"
rm -rf "$VIP"
assert_ok "flash without VIP table succeeds" run_make flash
assert_not_grep "flash omits missing VIP table" "--vip-table-path" "$CALLS"
assert_grep "flash reports missing table" "without VIP table" "$OUT"

# --- other targets ------------------------------------------------------
assert_ok "generate-keys succeeds" run_make generate-keys QCOM_FMP_KEY_PASSWORD=s3cret
assert_grep "genkeys gets password" "^genkeys.sh --fmp-key-password s3cret\$" "$CALLS"
assert_ok "gen-capsule succeeds" run_make gen-capsule QCOM_FLAT_BUILD="$SANDBOX/flat"
assert_grep "gencapsule gets keys and out-dir" "^gencapsule.sh --keys-path OEM-KEYS --out-dir $SANDBOX/flat\$" "$CALLS"

assert_ok "clean succeeds" run_make clean
assert_no_file "clean removes signed build" "$SIGNED"
assert_fails "flash without signed build fails" run_make flash
assert_grep "flash asks for sign-build" "run 'make sign-build' first" "$OUT"

mkdir -p "$SANDBOX/.sectools" "$SANDBOX/.qdl" "$SANDBOX/.security-profiles"
assert_ok "deps-clean succeeds" run_make deps-clean
assert_no_file "deps-clean removes sectools" "$SANDBOX/.sectools"
assert_no_file "deps-clean removes qdl" "$SANDBOX/.qdl"
assert_no_file "deps-clean removes profiles" "$SANDBOX/.security-profiles"

# --- .env ---------------------------------------------------------------
assert_ok "config creates .env" run_make config
assert_file ".env exists" "$SANDBOX/.env"
assert_ok ".env matches .env.sample" cmp -s "$SANDBOX/.env" "$SANDBOX/.env.sample"
echo "# marker" >> "$SANDBOX/.env"
assert_ok "config again succeeds" run_make config
assert_grep "config keeps existing .env" "already exists" "$OUT"
assert_grep ".env left untouched" "# marker" "$SANDBOX/.env"

cat > "$SANDBOX/.env" <<ENV
QCOM_SEC_PROFILE=$PROFILE
QCOM_FLAT_BUILD=$SANDBOX/flat
QCOM_SIGNED_BUILD=out
QCOM_VIP_DISABLE=1
ENV
assert_ok "sign-build from .env succeeds" run_make sign-build
assert_grep ".env values are used" "--out-dir $SANDBOX/out\$" "$CALLS"
assert_ok "command line overrides .env" run_make sign-build QCOM_SIGNED_BUILD=other
assert_grep "override wins" "--out-dir $SANDBOX/other\$" "$CALLS"

summary
