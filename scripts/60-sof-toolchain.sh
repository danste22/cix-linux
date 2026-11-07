#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
printf '%s\n' \
  'SOF is excluded from the first implementation pass.' \
  'Cadence/Xtensa licensing must be reviewed before this stage is enabled.' >&2
exit 2
