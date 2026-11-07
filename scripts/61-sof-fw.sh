#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
printf '%s\n' \
  'SOF is excluded from the first implementation pass.' \
  'Build sof-sky1 only after the dedicated legal and implementation gate.' >&2
exit 2
