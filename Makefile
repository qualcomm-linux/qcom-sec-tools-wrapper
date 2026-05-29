# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Convenience front-end for the qcom-sec-tools-wrapper scripts.  Configuration
# lives in a .env file (see .env.sample); run `make config` to create one.

ifneq (,$(wildcard ./.env))
include .env
export
endif

# Defaults (used only when not already set in the environment or .env).
QCOM_ROT_KEYS           ?= OEM-KEYS
QCOM_FMP_KEYS           ?= $(QCOM_ROT_KEYS)/demoCA
QCOM_ROOT_CERT_TOTALNUM ?= 1
QCOM_SIGNING_KEY_INDEX  ?= 0
QCOM_SECTOOLS_VERSION   ?= 1.45
QCOM_SECTOOLS_DIR       ?= .sectools
QCOM_QDL_VERSION        ?= master
QCOM_QDL_DIR            ?= .qdl
QCOM_SIGNED_BUILD       ?= signed-build
QCOM_VIP_DIR            ?= $(QCOM_SIGNED_BUILD)/vip-tables
QCOM_FIREHOSE           ?= prog_firehose_ddr.elf
QCOM_STORAGE            ?= ufs

SIGN    := ./signimages.sh
SECURE  := ./secure.sh
GENK    := ./genkeys.sh
GENC    := ./gencapsule.sh
FETCH   := ./fetch-sectools.sh
FETCHQDL:= ./fetch-qdl.sh

# Optional UEFI signing keys: only add the flag when a path is configured.
UEFI_ARG := $(if $(QCOM_UEFI_KEYS),--uefi-keys-path $(QCOM_UEFI_KEYS),)

.DEFAULT_GOAL := help
.PHONY: help config deps deps-clean generate-keys sign-build sign-build-with-fuse-blower flash gen-fuse-blower gen-capsule clean

help: ## Show this help
	@echo "qcom-sec-tools-wrapper -- make targets:"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration comes from .env (see .env.sample).  Start with: make config"

# Abort with a helpful message when a required variable is empty.
guard-%:
	@if [ -z '$($*)' ]; then \
		echo "ERROR: required variable $* is not set (set it in .env)"; \
		exit 1; \
	fi

config: ## Create .env from .env.sample (if it does not exist yet)
	@if [ -f .env ]; then \
		echo ".env already exists; leaving it untouched."; \
	else \
		cp .env.sample .env && \
		echo "Created .env from .env.sample - edit it to set your paths."; \
	fi

deps: ## Ensure external tools are available (sectools, and qdl unless QCOM_VIP_DISABLE)
	@SECTOOL="$$($(FETCH))" && echo "sectools: $$SECTOOL"
	@if [ -z "$(QCOM_VIP_DISABLE)" ]; then QDL="$$($(FETCHQDL))" && echo "qdl: $$QDL"; fi

generate-keys: guard-QCOM_FMP_KEY_PASSWORD ## Generate OEM signing + FMP keys into ./OEM-KEYS
	$(GENK) --fmp-key-password "$(QCOM_FMP_KEY_PASSWORD)"

# Sign a build end to end: stage a copy of the flat build into QCOM_SIGNED_BUILD,
# sign the images there, then (unless QCOM_VIP_DISABLE) generate and sign a VIP
# table of digests under QCOM_SIGNED_BUILD/vip-tables.  All inline, one recipe.
sign-build: guard-QCOM_SEC_PROFILE guard-QCOM_FLAT_BUILD deps ## Stage, sign and (unless QCOM_VIP_DISABLE) VIP-sign a build
	@set -e; \
	signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	vipdir="$(abspath $(QCOM_VIP_DIR))"; \
	SECTOOL="$$($(FETCH))"; \
	echo "==> Staging build into $$signdir"; \
	rm -rf "$$signdir"; \
	mkdir -p "$$signdir"; \
	cp -aL "$(QCOM_FLAT_BUILD)/." "$$signdir"/; \
	echo "==> Signing images in $$signdir"; \
	$(SIGN) --sectoolv2 "$$SECTOOL" \
		--keys-path "$(QCOM_ROT_KEYS)" \
		--fmp-path "$(QCOM_FMP_KEYS)" \
		--security-profile "$(QCOM_SEC_PROFILE)" \
		--root-cert-totalnum "$(QCOM_ROOT_CERT_TOTALNUM)" \
		--signing-key-index "$(QCOM_SIGNING_KEY_INDEX)" \
		--out-dir "$$signdir" \
		$(UEFI_ARG); \
	if [ -n "$(QCOM_VIP_DISABLE)" ]; then \
		echo "==> QCOM_VIP_DISABLE set; skipping VIP table generation"; \
		exit 0; \
	fi; \
	QDL="$$($(FETCHQDL))"; \
	echo "==> Creating VIP table of digests in $$vipdir"; \
	rm -rf "$$vipdir"; mkdir -p "$$vipdir"; \
	( cd "$$signdir" && "$$QDL" --allow-fusing --dry-run --create-digests="$$vipdir" \
		$(QCOM_FIREHOSE) rawprogram*.xml patch*.xml ); \
	"$$SECTOOL" mbn-tool generate --data "$$vipdir/DigestsToSign.bin" \
		--mbn-version 6 --outfile "$$vipdir/DigestsToSign.bin.mbn"; \
	echo "==> Signing VIP table"; \
	$(SIGN) --sectoolv2 "$$SECTOOL" \
		--keys-path "$(QCOM_ROT_KEYS)" \
		--fmp-path "$(QCOM_FMP_KEYS)" \
		--security-profile "$(QCOM_SEC_PROFILE)" \
		--root-cert-totalnum "$(QCOM_ROOT_CERT_TOTALNUM)" \
		--signing-key-index "$(QCOM_SIGNING_KEY_INDEX)" \
		--out-dir "$$vipdir"

# Same as sign-build but with the signed sec.elf integrated into rawprogram*.xml
# BEFORE the VIP table is generated, so the digest table covers sec.elf and the
# device can attest the secdata partition during VIP-validated programming.
sign-build-with-fuse-blower: guard-QCOM_SEC_PROFILE guard-QCOM_FLAT_BUILD guard-QCOM_FUSE_OEM_HW_ID guard-QCOM_FUSE_OEM_PRODUCT_ID guard-QCOM_FUSE_SEC_KEY_DERIVATION_KEY deps ## sign-build + gen-fuse-blower + integrate sec.elf into rawprogram*.xml + VIP-sign (sec.elf covered)
	@$(MAKE) --no-print-directory sign-build QCOM_VIP_DISABLE=1
	@$(MAKE) --no-print-directory gen-fuse-blower
	@set -e; \
	signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	vipdir="$(abspath $(QCOM_VIP_DIR))"; \
	SECTOOL="$$($(FETCH))"; \
	QDL="$$($(FETCHQDL))"; \
	echo "==> Integrating sec.elf into rawprogram*.xml under $$signdir"; \
	sed -i '/label="secdata"/s/filename=""/filename="sec.elf"/g' "$$signdir"/rawprogram*.xml; \
	echo "==> Creating VIP table of digests in $$vipdir"; \
	rm -rf "$$vipdir"; mkdir -p "$$vipdir"; \
	( cd "$$signdir" && "$$QDL" --allow-fusing --dry-run --create-digests="$$vipdir" \
		$(QCOM_FIREHOSE) rawprogram*.xml patch*.xml ); \
	"$$SECTOOL" mbn-tool generate --data "$$vipdir/DigestsToSign.bin" \
		--mbn-version 6 --outfile "$$vipdir/DigestsToSign.bin.mbn"; \
	echo "==> Signing VIP table"; \
	$(SIGN) --sectoolv2 "$$SECTOOL" \
		--keys-path "$(QCOM_ROT_KEYS)" \
		--fmp-path "$(QCOM_FMP_KEYS)" \
		--security-profile "$(QCOM_SEC_PROFILE)" \
		--root-cert-totalnum "$(QCOM_ROOT_CERT_TOTALNUM)" \
		--signing-key-index "$(QCOM_SIGNING_KEY_INDEX)" \
		--out-dir "$$vipdir"

flash: ## Flash QCOM_SIGNED_BUILD to a connected device via qdl (uses the signed VIP table)
	@signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	vipdir="$(abspath $(QCOM_VIP_DIR))"; \
	if [ ! -d "$$signdir" ]; then \
		echo "ERROR: $$signdir not found; run 'make sign-build' first."; exit 1; \
	fi; \
	QDL="$$($(FETCHQDL))"; \
	vip_arg=""; \
	if [ -z "$(QCOM_VIP_DISABLE)" ] && [ -f "$$vipdir/DigestsToSign.bin.mbn" ]; then \
		vip_arg="--vip-table-path=$$vipdir"; \
		echo "==> Flashing $$signdir (storage=$(QCOM_STORAGE)) with VIP table $$vipdir"; \
	else \
		echo "==> Flashing $$signdir (storage=$(QCOM_STORAGE)) without VIP table"; \
	fi; \
	( cd "$$signdir" && "$$QDL" --allow-fusing --storage "$(QCOM_STORAGE)" $$vip_arg \
		$(QCOM_FIREHOSE) rawprogram*.xml patch*.xml )

gen-fuse-blower: guard-QCOM_SEC_PROFILE guard-QCOM_FUSE_OEM_HW_ID guard-QCOM_FUSE_OEM_PRODUCT_ID guard-QCOM_FUSE_SEC_KEY_DERIVATION_KEY deps ## Generate the signed sec.elf fuse-blower image into QCOM_SIGNED_BUILD
	@SECTOOL="$$($(FETCH))"; \
	signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	mkdir -p "$$signdir"; \
	$(SECURE) --create-sec-elf --sectoolv2 "$$SECTOOL" \
		--keys-path "$(QCOM_ROT_KEYS)" \
		--security-profile "$(QCOM_SEC_PROFILE)" \
		--root-cert-totalnum "$(QCOM_ROOT_CERT_TOTALNUM)" \
		--signing-key-index "$(QCOM_SIGNING_KEY_INDEX)" \
		--fuse-oem-hw-id "$(QCOM_FUSE_OEM_HW_ID)" \
		--fuse-oem-product-id "$(QCOM_FUSE_OEM_PRODUCT_ID)" \
		--fuse-sec-key-derivation-key "$(QCOM_FUSE_SEC_KEY_DERIVATION_KEY)" \
		--out-dir "$$signdir" \
		$(UEFI_ARG)

gen-capsule: guard-QCOM_ROT_KEYS guard-QCOM_FLAT_BUILD ## Generate a UEFI capsule from the FMP keys (needs the cbsp-boot-utilities submodule)
	$(GENC) --keys-path "$(QCOM_ROT_KEYS)" --out-dir "$(QCOM_FLAT_BUILD)"

deps-clean: ## Remove fetched tools (.sectools/ and .qdl/)
	rm -rf "$(QCOM_SECTOOLS_DIR)" "$(QCOM_QDL_DIR)"

clean: ## Remove the build staging folder (QCOM_SIGNED_BUILD and QCOM_VIP_DIR)
	rm -rf "$(QCOM_SIGNED_BUILD)" "$(QCOM_VIP_DIR)"
