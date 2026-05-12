# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.

# docker build -t genkeys:latest .
# docker run --rm -it -v $(pwd)/OEM-KEYS:/src/OEM-KEYS genkeys:latest

# OpenSSL 3.3.3
# FROM alpine:3.21.3
# OpenSSL 1.1.1w
FROM alpine:3.16.9

RUN apk add openssl coreutils

RUN mkdir /src/

# https://docs.qualcomm.com/bundle/publicresource/topics/80-70015-11/appendix-openssl-configuration.html
COPY opensslroot.cfg /src/
# https://docs.qualcomm.com/bundle/publicresource/topics/80-70015-11/generate-local-insecure-root-key-and-certificates.html
COPY v3.ext /src/
COPY v3_attest.ext /src/

# script to run the 
COPY genkeys.sh /src/
RUN chmod 755 /src/genkeys.sh

WORKDIR /src/
ENTRYPOINT ["/src/genkeys.sh"]
