#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Read-only boot evidence for an installed O6N kernel. Run on the board as
# root after the kernel, DKMS modules, and firmware package are installed.
# This script does not install packages and does not load modules.

set -u

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

need_path() {
  if [[ -e "$1" ]]; then
    pass "$1"
  else
    fail "missing $1"
  fi
}

need_text() {
  local label="$1"
  local pattern="$2"
  if dmesg | grep -F -q -- "$pattern"; then
    pass "${label}: ${pattern}"
  else
    fail "${label}: dmesg lacks ${pattern}"
  fi
}

release="$(uname -r)"
printf 'uname %s\n' "${release}"
if [[ "${release}" == *+deb13o6n* ]]; then
  pass "running an O6N ABI"
else
  fail "uname -r does not contain +deb13o6n"
fi

cmdline="$(cat /proc/cmdline)"
printf 'cmdline %s\n' "${cmdline}"
if [[ " ${cmdline} " == *" clk_ignore_unused "* ]]; then
  pass "clk_ignore_unused"
else
  fail "kernel command line lacks clk_ignore_unused"
fi

if dmesg | grep -E -q 'Kernel panic|Oops:'; then
  fail "dmesg contains a panic or oops"
else
  pass "no panic or oops in dmesg"
fi

need_text clocks "protected critical clock scmi-clk-7"
need_text clocks "protected critical clock scmi-clk-170"
need_text clocks "clk: Not disabling unused clocks"
need_text gpu "Mali-G720"
need_text gpu "CSF FW using interface"
need_text npu "zhouyi-v3"
need_text vpu "Linlon v5276"

for node in /dev/dri/card0 /dev/dri/card1 /dev/dri/renderD128 /dev/aipu; do
  need_path "${node}"
done

connected=0
for status in /sys/class/drm/card*-DP-*/status; do
  [[ -f "${status}" ]] || continue
  state="$(cat "${status}")"
  printf 'drm   %s %s\n' "${status}" "${state}"
  if [[ "${state}" == connected ]]; then
    connected=$((connected + 1))
  fi
done
if [[ "${connected}" -ge 1 ]]; then
  pass "a DisplayPort output is connected"
else
  fail "no connected DisplayPort output"
fi

declare -A video_names=(
  [video0]=mvxdec
  [video1]=mvxenc
  [video2]=mvxjpegdec
  [video3]=mvxjpegenc
)
for node in "${!video_names[@]}"; do
  sysfs="/sys/class/video4linux/${node}/name"
  expected="${video_names[${node}]}"
  if [[ -f "${sysfs}" && "$(cat "${sysfs}")" == "${expected}" ]]; then
    pass "${node} ${expected}"
  else
    fail "${node} is not ${expected}"
  fi
done

for module in aipu amvx; do
  if lsmod | awk '{print $1}' | grep -x -q "${module}"; then
    pass "module ${module}"
  else
    fail "module ${module} is not loaded"
  fi
done

firmware_files=(
  dsp_fw.bin
  av1dec.fwb
  avs2dec.fwb
  avsdec.fwb
  h264dec.fwb
  h264enc.fwb
  hevcdec.fwb
  hevcenc.fwb
  jpegdec.fwb
  jpegenc.fwb
  mpeg2dec.fwb
  mpeg4dec.fwb
  vc1dec.fwb
  vp8dec.fwb
  vp8enc.fwb
  vp9dec.fwb
  vp9enc.fwb
)
for name in "${firmware_files[@]}"; do
  need_path "/lib/firmware/${name}"
done
need_path /lib/firmware/arm/mali/arch12.8/mali_csffw.bin

printf 'audio supplier bind:\n'
audio_bound=0
audio_total=0
for device in CIXH6062:00 CIXH6000:00 CIXH1006:00 \
              CIXH6011:02 CIXH6011:03 CIXH6011:06; do
  audio_total=$((audio_total + 1))
  link="/sys/bus/platform/devices/${device}/driver"
  if [[ -L "${link}" ]]; then
    printf '  %s %s\n' "${device}" "$(basename "$(readlink "${link}")")"
    audio_bound=$((audio_bound + 1))
  else
    printf '  %s unbound\n' "${device}"
  fi
done
if [[ "${audio_bound}" -eq "${audio_total}" ]]; then
  pass "audio reset, DSP, DMA, and I2S are bound"
else
  printf 'note  audio nodes unbound (%s/%s). CIXH6062 needs CONFIG_RESET_SKY1_AUDSS in the booted kernel.\n' \
    "${audio_bound}" "${audio_total}"
fi

if [[ "${failures}" -eq 0 ]]; then
  printf 'boot evidence passed\n'
  exit 0
fi
printf 'boot evidence failed: %s check(s)\n' "${failures}" >&2
exit 1
