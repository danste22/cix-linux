# SPDX-License-Identifier: GPL-3.0-or-later

SHELL := /bin/bash
COMPOSE := docker compose --env-file refs.env
STAMP_DIR := artifacts/stamps

.PHONY: help init fetch source config kernel dkms-npu dkms-vpu \
	firmware firmware-pkg repo-pkg repo all validate

help:
	@printf '%s\n' \
	  '  make init          create project-local workspace directories' \
	  '  make fetch         download and verify Debian/CIX source inputs' \
	  '  make source        assemble the patched Debian source tree' \
	  '  make config        prepare the Debian + CIX kernel config' \
	  '  make kernel        build the arm64 O6N kernel packages' \
	  '  make dkms-npu      build the NPU DKMS package' \
	  '  make dkms-vpu      build the VPU DKMS and uAPI header packages' \
	  '  make firmware      fetch and verify the CIX firmware set' \
	  '  make firmware-pkg build the strict firmware installer package' \
	  '  make repo-pkg     build the OBS repository bootstrap package' \
	  '  make repo          create the signed local apt repository' \
	  '  make validate      run static checks only' \
	  '' \
	  'Stamps live in artifacts/stamps. A finished step is not repeated while its stamp is newer than its inputs.' \
	  'Delete artifacts/stamps to run the chain again.'

init: $(STAMP_DIR)/init
fetch: $(STAMP_DIR)/fetch
source: $(STAMP_DIR)/source
config: $(STAMP_DIR)/config
kernel: $(STAMP_DIR)/kernel
dkms-npu: $(STAMP_DIR)/dkms-npu
dkms-vpu: $(STAMP_DIR)/dkms-vpu
firmware: $(STAMP_DIR)/firmware
firmware-pkg: $(STAMP_DIR)/firmware-pkg
repo-pkg: $(STAMP_DIR)/repo-pkg
repo: $(STAMP_DIR)/repo

all: repo

validate:
	@./scripts/90-validate-scaffold.sh

$(STAMP_DIR)/init: scripts/00-init-workspace.sh refs.env
	./scripts/00-init-workspace.sh
	mkdir -p $(STAMP_DIR)
	touch $@

$(STAMP_DIR)/fetch: $(STAMP_DIR)/init scripts/10-fetch-upstream.sh refs.env
	$(COMPOSE) run --rm source ./scripts/10-fetch-upstream.sh
	touch $@

$(STAMP_DIR)/source: $(STAMP_DIR)/fetch scripts/20-assemble-source.sh \
		scripts/lib/rewrite-cix-0013-context.py \
		$(wildcard patches/o6n/*.patch) refs.env
	$(COMPOSE) run --rm source ./scripts/20-assemble-source.sh
	touch $@

$(STAMP_DIR)/config: $(STAMP_DIR)/source scripts/21-kernel-config.sh \
		config/cix-7.2-delta.config refs.env
	$(COMPOSE) run --rm source ./scripts/21-kernel-config.sh
	touch $@

$(STAMP_DIR)/kernel: $(STAMP_DIR)/config scripts/30-build-kernel.sh refs.env
	$(COMPOSE) run --rm kernel ./scripts/30-build-kernel.sh
	touch $@

$(STAMP_DIR)/dkms-npu: $(STAMP_DIR)/kernel scripts/40-build-dkms.sh \
		scripts/41-verify-dkms.sh
	$(COMPOSE) run --rm dkms ./scripts/40-build-dkms.sh npu
	$(COMPOSE) run --rm dkms ./scripts/41-verify-dkms.sh npu
	touch $@

$(STAMP_DIR)/vpu-package: $(STAMP_DIR)/kernel scripts/40-build-dkms.sh \
		scripts/22-strip-vpu-firmware.sh
	$(COMPOSE) run --rm dkms ./scripts/40-build-dkms.sh vpu
	touch $@

$(STAMP_DIR)/firmware: $(STAMP_DIR)/init scripts/45-fetch-firmware.sh refs.env
	$(COMPOSE) run --rm source ./scripts/45-fetch-firmware.sh
	touch $@

$(STAMP_DIR)/firmware-pkg: $(STAMP_DIR)/firmware scripts/46-build-firmware-pkg.sh
	$(COMPOSE) run --rm dkms ./scripts/46-build-firmware-pkg.sh
	touch $@

$(STAMP_DIR)/dkms-vpu: $(STAMP_DIR)/vpu-package $(STAMP_DIR)/firmware-pkg \
		scripts/41-verify-dkms.sh
	$(COMPOSE) run --rm dkms ./scripts/41-verify-dkms.sh vpu
	touch $@

$(STAMP_DIR)/repo-pkg: $(STAMP_DIR)/init scripts/47-build-repo-pkg.sh
	$(COMPOSE) run --rm dkms ./scripts/47-build-repo-pkg.sh
	touch $@

$(STAMP_DIR)/repo: $(STAMP_DIR)/dkms-npu $(STAMP_DIR)/dkms-vpu \
		$(STAMP_DIR)/repo-pkg scripts/50-make-repo.sh keys/pubring.kbx
	$(COMPOSE) run --rm repo-builder ./scripts/50-make-repo.sh
	touch $@
