#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Exercise fetch-sectools.sh resolution and a file:// download.

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
new_sandbox

FETCH="$ROOT/fetch-sectools.sh"
ERR="$SANDBOX/err.log"
cd "$SANDBOX" || exit 1

run() { OUTPUT="$("$@" 2> "$ERR")"; }

# Explicit binary.
touch bin.sh; chmod +x bin.sh
assert_ok "explicit binary is accepted" run env QCOM_SECTOOLS="$SANDBOX/bin.sh" "$FETCH"
assert_eq "explicit binary is printed" "$SANDBOX/bin.sh" "$OUTPUT"
assert_fails "non-executable QCOM_SECTOOLS is rejected" run env QCOM_SECTOOLS="$SANDBOX/missing" "$FETCH"
assert_grep "error names QCOM_SECTOOLS" "QCOM_SECTOOLS=" "$ERR"

# Already downloaded, per-arch layout.
mkdir -p vendored/1.50.0/1.50/Linux_aarch64
touch vendored/1.50.0/1.50/Linux_aarch64/sectools; chmod +x vendored/1.50.0/1.50/Linux_aarch64/sectools
assert_ok "vendored aarch64 binary is found" run env QCOM_SECTOOLS_ARCH=aarch64 QCOM_SECTOOLS_DIR=vendored "$FETCH"
assert_eq "vendored path is absolute" "$SANDBOX/vendored/1.50.0/1.50/Linux_aarch64/sectools" "$OUTPUT"
assert_not_grep "no download for vendored binary" "Downloading" "$ERR"
assert_fails "unsupported arch is rejected" run env QCOM_SECTOOLS_ARCH=mips QCOM_SECTOOLS_DIR=vendored "$FETCH"

# Download from a local archive laid out like the Software Center zip.
mkdir -p zip/1.50/Linux zip/1.50/Linux_aarch64
echo '#!/bin/sh' > zip/1.50/Linux/sectools
echo '#!/bin/sh' > zip/1.50/Linux_aarch64/sectools
(cd zip && zip -q -r ../1.50.zip 1.50)
SUM="$(sha256sum 1.50.zip | cut -d' ' -f1)"
URL="file://$SANDBOX/1.50.zip"

assert_ok "download installs x86_64 binary" run env QCOM_SECTOOLS_ARCH=x86_64 QCOM_SECTOOLS_DIR=dl QCOM_SECTOOLS_URL="$URL" QCOM_SECTOOLS_SHA256="$SUM" "$FETCH"
assert_eq "installed path" "$SANDBOX/dl/1.50.0/1.50/Linux/sectools" "$OUTPUT"
assert_ok "installed binary is executable" test -x dl/1.50.0/1.50/Linux/sectools
assert_ok "second run reuses download" run env QCOM_SECTOOLS_ARCH=x86_64 QCOM_SECTOOLS_DIR=dl QCOM_SECTOOLS_URL="$URL" "$FETCH"
assert_not_grep "no second download" "Downloading" "$ERR"

assert_fails "sha256 mismatch is rejected" run env QCOM_SECTOOLS_ARCH=x86_64 QCOM_SECTOOLS_DIR=bad QCOM_SECTOOLS_URL="$URL" QCOM_SECTOOLS_SHA256=deadbeef "$FETCH"
assert_grep "mismatch is reported" "sha256 mismatch" "$ERR"
assert_no_file "nothing installed on mismatch" bad/1.50.0

# Version to archive name mapping: 2.0.1 -> 2.0.zip -> 2.0/.
mkdir -p zip2/2.0/Linux; echo '#!/bin/sh' > zip2/2.0/Linux/sectools
(cd zip2 && zip -q -r ../2.0.zip 2.0)
assert_ok "other version installs" run env QCOM_SECTOOLS_ARCH=x86_64 QCOM_SECTOOLS_DIR=dl QCOM_SECTOOLS_VERSION=2.0.1 QCOM_SECTOOLS_URL="file://$SANDBOX/2.0.zip" "$FETCH"
assert_eq "version dir uses full version, archive dir major.minor" "$SANDBOX/dl/2.0.1/2.0/Linux/sectools" "$OUTPUT"
assert_fails "archive without binary is rejected" run env QCOM_SECTOOLS_ARCH=aarch64 QCOM_SECTOOLS_DIR=dl2 QCOM_SECTOOLS_VERSION=2.0.1 QCOM_SECTOOLS_URL="file://$SANDBOX/2.0.zip" "$FETCH"
assert_grep "missing binary is reported" "not found in the archive" "$ERR"

# Default URL follows the Software Center pattern.
assert_fails "default URL download fails offline" run env QCOM_SECTOOLS_DIR=none QCOM_SECTOOLS_VERSION=1.50.0 PATH="$SANDBOX/nobin" "$FETCH"
mkdir -p nobin
cat > nobin/curl <<'STUB'
#!/bin/sh
echo "$@" >&2; exit 22
STUB
chmod +x nobin/curl
ln -s "$(command -v unzip)" nobin/unzip; ln -s "$(command -v uname)" nobin/uname
ln -s "$(command -v mktemp)" nobin/mktemp; ln -s "$(command -v rm)" nobin/rm
ln -s "$(command -v cut)" nobin/cut; ln -s "$(command -v mkdir)" nobin/mkdir
assert_fails "download failure is reported" run env QCOM_SECTOOLS_DIR=none QCOM_SECTOOLS_VERSION=1.50.0 PATH="$SANDBOX/nobin" "$FETCH"
assert_grep "default URL" "Qualcomm_Security_Tools/All/1.50.0/1.50.zip" "$ERR"

summary
