# SPDX-License-Identifier: GPL-3.0-or-later

SHELL := /bin/bash
COMPOSE := docker compose --env-file refs.env

.PHONY: help init fetch source config kernel dkms-npu dkms-vpu \
	firmware firmware-pkg repo-pkg repo all validate

help:
	@printf '%s\n' \
	  'Gate 2 scaffold (no build has run)' \
	  '' \
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
	  '  make validate      run static checks only'

init:
	@./scripts/00-init-workspace.sh

fetch: init
	@$(COMPOSE) run --rm source ./scripts/10-fetch-upstream.sh

source: fetch
	@$(COMPOSE) run --rm source ./scripts/20-assemble-source.sh

config: source
	@$(COMPOSE) run --rm source ./scripts/21-kernel-config.sh

kernel: config
	@$(COMPOSE) run --rm kernel ./scripts/30-build-kernel.sh

dkms-npu: kernel
	@$(COMPOSE) run --rm dkms ./scripts/40-build-dkms.sh npu
	@$(COMPOSE) run --rm dkms ./scripts/41-verify-dkms.sh npu

dkms-vpu: kernel
	@$(COMPOSE) run --rm dkms ./scripts/40-build-dkms.sh vpu
	@$(COMPOSE) run --rm dkms ./scripts/41-verify-dkms.sh vpu

firmware: init
	@$(COMPOSE) run --rm source ./scripts/45-fetch-firmware.sh

firmware-pkg: firmware
	@$(COMPOSE) run --rm dkms ./scripts/46-build-firmware-pkg.sh

repo-pkg: init
	@$(COMPOSE) run --rm dkms ./scripts/47-build-repo-pkg.sh

repo: kernel dkms-npu dkms-vpu firmware-pkg repo-pkg
	@$(COMPOSE) run --rm repo-builder ./scripts/50-make-repo.sh

all: repo

validate:
	@./scripts/90-validate-scaffold.sh
