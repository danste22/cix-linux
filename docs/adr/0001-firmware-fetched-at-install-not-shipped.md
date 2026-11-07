# Firmware is fetched at install time, not shipped

The CIX DSP and VPU firmware has no clear redistribution licence, and OBS only hosts OSI-licensed packages. So none of our packages contain firmware bytes: `cix-o6n-firmware-install` downloads the 17 files (`dsp_fw.bin` and 16 `.fwb`) from the pinned commit of `cixtech/cix_proprietary__cix_proprietary` at install time and installs them only if their sha256 matches. The Mali CSF firmware comes from Debian's `firmware-misc-nonfree` through `Depends`, so Debian stays the distributor.

## Considered Options

- Bundle the firmware in our `.deb`: rejected because of the licence situation and OBS policy.
- Mirror the firmware in our own repo or apt host: rejected for the same reason; it is still redistribution.
