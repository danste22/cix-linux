#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Userspace accelerator check for an installed O6N kernel. Run on the board
# as root. The board can be a minimal Debian system with no desktop.
#
# Installs the trixie-backports Mesa stack used by Panthor. Removes
# cix-gpu-umd and cix-mesa when they are installed: those packages put
# /opt/cixgpu-pro and /opt/cixgpu-compat ahead of Debian's libgbm, and the
# closed loader then looks for libmali.so. Panthor firmware stays in
# firmware-misc-nonfree (arm/mali/arch12.8/mali_csffw.bin). NPU inference
# and VPU bitstream decode need userspace this repository does not ship.
# Their device nodes are the kernel check.

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  printf 'run as root\n' >&2
  exit 1
fi

failures=0

pass() {
  printf 'pass  %s\n' "$1"
}

fail() {
  printf 'fail  %s\n' "$1" >&2
  failures=$((failures + 1))
}

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y -t trixie-backports \
  libegl1 \
  libegl-mesa0 \
  libgbm1 \
  libgles2 \
  libgl1-mesa-dri \
  mesa-utils \
  kmscube

remove=()
if dpkg -s cix-gpu-umd >/dev/null 2>&1; then
  remove+=(cix-gpu-umd)
fi
if dpkg -s cix-mesa >/dev/null 2>&1; then
  remove+=(cix-mesa)
fi
if [[ "${#remove[@]}" -gt 0 ]]; then
  apt-get remove --purge -y "${remove[@]}"
fi
ldconfig

gbm="$(ldconfig -p | awk '/libgbm\.so\.1 / { print $NF; exit }')"
printf 'libgbm %s\n' "${gbm}"
if [[ -z "${gbm}" || "${gbm}" == /opt/cixgpu-* ]]; then
  fail "linker still selects ${gbm:-no libgbm.so.1}"
else
  pass "linker selects ${gbm}"
fi

egl_log="$(mktemp)"
if /usr/bin/eglinfo -B -p gbm >"${egl_log}" 2>&1 \
   && grep -q 'Mali-G720' "${egl_log}" \
   && grep -q 'Panfrost' "${egl_log}"; then
  grep -E 'renderer:|version:' "${egl_log}"
  pass "eglinfo GBM renderer is Mali-G720"
else
  cat "${egl_log}" >&2
  fail "eglinfo did not report Mali-G720 on the GBM platform"
fi
rm -f "${egl_log}"

display=""
for status in /sys/class/drm/card*-DP-*/status; do
  [[ -f "${status}" ]] || continue
  if [[ "$(cat "${status}")" == connected ]]; then
    name="$(basename "${status%/status}")"
    display="/dev/dri/${name%%-*}"
    break
  fi
done
if [[ -z "${display}" ]]; then
  fail "no connected DisplayPort output for kmscube"
else
  kms_log="$(mktemp)"
  set +e
  # stdout is fully buffered when redirected. The frame lines would otherwise
  # stay in the buffer when timeout stops kmscube.
  timeout --signal=INT 8 stdbuf -oL -eL kmscube -D "${display}" >"${kms_log}" 2>&1
  set -e
  if grep -q 'Mali-G720' "${kms_log}" && grep -q '^Rendered ' "${kms_log}"; then
    grep '^Rendered ' "${kms_log}" | tail -n 1
    pass "kmscube rendered on ${display}"
  else
    cat "${kms_log}" >&2
    fail "kmscube did not render on ${display}"
  fi
  rm -f "${kms_log}"
fi

if [[ "${failures}" -eq 0 ]]; then
  printf 'accelerator test passed\n'
  exit 0
fi
printf 'accelerator test failed: %s check(s)\n' "${failures}" >&2
exit 1
