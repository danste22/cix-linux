# cix-linux

Debian trixie-backports kernel and companion packages for one specific CIX Sky1 board.

## Language

**O6N**:
The Radxa Orion O6N board, the only hardware this project targets.
_Avoid_: Orion O6, O6, o6n (lowercase is for identifiers only)

**O6N Kernel**:
The Debian trixie-backports kernel with the CIX patch stack and the `+deb13o6n` ABI suffix, built only for the O6N.
_Avoid_: Custom kernel, CIX kernel

**O6N Kernel Metapackage**:
Either `linux-image-o6n-arm64` or `linux-headers-o6n-arm64`; a stable package name that follows the newest O6N Kernel ABI.
_Avoid_: linux-image-arm64, linux-headers-arm64

**O6N Firmware Set**:
The pinned CIX DSP file and 16 VPU files installed transactionally after every file passes its recorded sha256. Mali firmware is not part of this set; Debian supplies it.
_Avoid_: Firmware package, firmware blob package

**Accepted Build**:
An OBS build that has passed the complete manual O6N board smoke gate and has been archived as an immutable GitHub Release.
_Avoid_: Successful build, latest build
