# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Front-end for the qcom-sec-tools-wrapper scripts, configured via .env
# (see .env.sample).  Run `make config` to create one.

ifneq (,$(wildcard ./.env))
include .env
export
endif

QCOM_ROT_KEYS           ?= OEM-KEYS
QCOM_FMP_KEYS           ?= $(QCOM_ROT_KEYS)/demoCA
QCOM_ROOT_CERT_TOTALNUM ?= 1
QCOM_SIGNING_KEY_INDEX  ?= 0
QCOM_SECTOOLS_VERSION   ?= 1.50.0
QCOM_SECTOOLS_DIR       ?= .sectools
QCOM_SEC_PROFILES_DIR   ?= .security-profiles
QCOM_QDL_VERSION        ?= v2.8
QCOM_QDL_DIR            ?= .qdl
QCOM_SIGNED_BUILD       ?= signed-build
QCOM_VIP_DIR            ?= $(QCOM_SIGNED_BUILD)/vip-tables
QCOM_FIREHOSE           ?= prog_firehose_ddr.elf
QCOM_STORAGE            ?= ufs

SIGN         := ./signimages.sh
SECURE       := ./secure.sh
GENK         := ./genkeys.sh
GENC         := ./gencapsule.sh
FETCH        := ./fetch-sectools.sh
FETCHQDL     := ./fetch-qdl.sh
FETCHPROFILE := ./fetch-security-profile.sh

UEFI_ARG := $(if $(QCOM_UEFI_KEYS),--uefi-keys-path $(QCOM_UEFI_KEYS),)

# Signing flags shared by every signimages.sh invocation.
SIGN_ARGS = --sectoolv2 "$$SECTOOL" \
	--keys-path "$(QCOM_ROT_KEYS)" \
	--fmp-path "$(QCOM_FMP_KEYS)" \
	--security-profile "$$SECPROFILE" \
	--root-cert-totalnum "$(QCOM_ROOT_CERT_TOTALNUM)" \
	--signing-key-index "$(QCOM_SIGNING_KEY_INDEX)"

# Generate and sign the VIP digest table for $$signdir into $$vipdir.
define vip_sign
	echo "==> Creating VIP table of digests in $$vipdir"; \
	rm -rf "$$vipdir"; mkdir -p "$$vipdir"; \
	( cd "$$signdir" && "$$QDL" --allow-fusing --dry-run --create-digests="$$vipdir" \
		$(QCOM_FIREHOSE) rawprogram*.xml patch*.xml ); \
	"$$SECTOOL" mbn-tool generate --data "$$vipdir/DigestsToSign.bin" \
		--mbn-version 6 --outfile "$$vipdir/DigestsToSign.bin.mbn"; \
	echo "==> Signing VIP table"; \
	$(SIGN) $(SIGN_ARGS) --out-dir "$$vipdir"
endef

.DEFAULT_GOAL := help
.PHONY: help config deps deps-clean generate-keys sign-build sign-build-with-fuse-blower flash gen-fuse-blower gen-capsule clean test

help: ## Show this help
	@echo "qcom-sec-tools-wrapper -- make targets:"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  %-30s %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration comes from .env (see .env.sample).  Start with: make config"

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

deps: ## Fetch sectools, the security profile and (unless QCOM_VIP_DISABLE) qdl
	@SECTOOL="$$($(FETCH))" && echo "sectools: $$SECTOOL"
	@if [ -n "$(QCOM_SEC_PROFILE)" ]; then SECPROFILE="$$($(FETCHPROFILE))" && echo "security profile: $$SECPROFILE"; fi
	@if [ -z "$(QCOM_VIP_DISABLE)" ]; then QDL="$$($(FETCHQDL))" && echo "qdl: $$QDL"; fi

generate-keys: guard-QCOM_FMP_KEY_PASSWORD ## Generate OEM signing + FMP keys into ./OEM-KEYS
	$(GENK) --fmp-key-password "$(QCOM_FMP_KEY_PASSWORD)"

sign-build: guard-QCOM_SEC_PROFILE guard-QCOM_FLAT_BUILD deps ## Stage, sign and (unless QCOM_VIP_DISABLE) VIP-sign a build
	@set -e; \
	signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	vipdir="$(abspath $(QCOM_VIP_DIR))"; \
	SECTOOL="$$($(FETCH))"; \
	SECPROFILE="$$($(FETCHPROFILE))"; \
	echo "==> Staging build into $$signdir"; \
	rm -rf "$$signdir"; \
	mkdir -p "$$signdir"; \
	cp -aL "$(QCOM_FLAT_BUILD)/." "$$signdir"/; \
	echo "==> Signing images in $$signdir"; \
	$(SIGN) $(SIGN_ARGS) --out-dir "$$signdir" $(UEFI_ARG); \
	if [ -n "$(QCOM_VIP_DISABLE)" ]; then \
		echo "==> QCOM_VIP_DISABLE set; skipping VIP table generation"; \
		exit 0; \
	fi; \
	QDL="$$($(FETCHQDL))"; \
	$(vip_sign)

# The VIP table must be generated after sec.elf is wired into rawprogram*.xml
# so its digest is covered.
sign-build-with-fuse-blower: guard-QCOM_SEC_PROFILE guard-QCOM_FLAT_BUILD guard-QCOM_FUSE_OEM_HW_ID guard-QCOM_FUSE_OEM_PRODUCT_ID guard-QCOM_FUSE_SEC_KEY_DERIVATION_KEY deps ## sign-build + gen-fuse-blower, with sec.elf in rawprogram*.xml and the VIP table
	@$(MAKE) --no-print-directory sign-build QCOM_VIP_DISABLE=1
	@$(MAKE) --no-print-directory gen-fuse-blower
	@set -e; \
	signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	vipdir="$(abspath $(QCOM_VIP_DIR))"; \
	SECTOOL="$$($(FETCH))"; \
	SECPROFILE="$$($(FETCHPROFILE))"; \
	QDL="$$($(FETCHQDL))"; \
	echo "==> Integrating sec.elf into rawprogram*.xml under $$signdir"; \
	sed -i '/label="secdata"/s/filename=""/filename="sec.elf"/g' "$$signdir"/rawprogram*.xml; \
	$(vip_sign)

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
	SECPROFILE="$$($(FETCHPROFILE))"; \
	signdir="$(abspath $(QCOM_SIGNED_BUILD))"; \
	mkdir -p "$$signdir"; \
	$(SECURE) --create-sec-elf --sectoolv2 "$$SECTOOL" \
		--keys-path "$(QCOM_ROT_KEYS)" \
		--security-profile "$$SECPROFILE" \
		--root-cert-totalnum "$(QCOM_ROOT_CERT_TOTALNUM)" \
		--signing-key-index "$(QCOM_SIGNING_KEY_INDEX)" \
		--fuse-oem-hw-id "$(QCOM_FUSE_OEM_HW_ID)" \
		--fuse-oem-product-id "$(QCOM_FUSE_OEM_PRODUCT_ID)" \
		--fuse-sec-key-derivation-key "$(QCOM_FUSE_SEC_KEY_DERIVATION_KEY)" \
		--out-dir "$$signdir" \
		$(UEFI_ARG)

gen-capsule: guard-QCOM_ROT_KEYS guard-QCOM_FLAT_BUILD ## Generate a UEFI capsule from the FMP keys (needs the cbsp-boot-utilities submodule)
	$(GENC) --keys-path "$(QCOM_ROT_KEYS)" --out-dir "$(QCOM_FLAT_BUILD)"

deps-clean: ## Remove fetched tools and security profiles
	rm -rf "$(QCOM_SECTOOLS_DIR)" "$(QCOM_QDL_DIR)" "$(QCOM_SEC_PROFILES_DIR)"

clean: ## Remove the staged signed build (QCOM_SIGNED_BUILD and QCOM_VIP_DIR)
	rm -rf "$(QCOM_SIGNED_BUILD)" "$(QCOM_VIP_DIR)"

# Run with a clean environment so a local .env cannot leak into the tests.
test: ## Run the test suite
	@for t in tests/test-*.sh; do env -i PATH="$$PATH" HOME="$$HOME" sh "$$t" || exit 1; done
