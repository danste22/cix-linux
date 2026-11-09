O6N firmware sources
====================

This project does not redistribute firmware bytes.

The CIX DSP and VPU firmware is downloaded at installation time from the
public cixtech/cix_proprietary__cix_proprietary repository at commit:

  6260fd1a596a6135a198f0f220e6ed70f3210532

Every file must match the sha256 recorded in manifest.txt before any file is
installed. The transaction is all-or-nothing.

The Mali CSF firmware is not downloaded by this project. Debian's
firmware-misc-nonfree package installs:

  /usr/lib/firmware/arm/mali/arch12.8/mali_csffw.bin

Review the source repository and Debian package copyright files before use.
