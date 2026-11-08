# O6N Debian kernel

Debian trixie-backports kernel and companion packages for the Radxa Orion O6N.

This repository contains build tooling and packaging only. It does not contain
proprietary firmware. See
`docs/adr/0001-firmware-fetched-at-install-not-shipped.md` for the firmware
decision.

## Gate status

- Gate 2: repository scaffold complete.
- Gate 3: all 17 pinned CIX firmware files downloaded and independently
  SHA-256 verified (6,193,664 bytes total).

No kernel, DKMS module, firmware package, or container image has been built.

## Local workspace

Firmware downloads stay inside the project and are ignored by git:

```text
/Users/daniel/IdeaProjects/cix-linux/downloads/firmware/
```

Large generated kernel source, build artifacts and upstream working copies use
the external build root configured in `refs.env`.

Use `make help` to list the staged commands. Build targets are intentionally
guarded until their later execution gates are approved.

## Board requirements

- UEFI hardware description: ACPI
- Kernel command line: `clk_ignore_unused`
- Secure Boot: disabled for the initial unsigned build
- Debian trixie-backports with `non-free-firmware` enabled

## Existing CIX VPU package replacement

The vendor DKMS package depends on `cix-vpu-firmware`, which owns the same
paths managed by this project's verified installer. Replace both packages
explicitly:

```sh
sudo apt remove cix-vpu-driver-dkms cix-vpu-firmware
sudo apt install cix-o6n-firmware-install cix-vpu-driver-dkms cix-vpu-libc-dev
```

Do not let the two firmware ownership models coexist.

## OBS repository key

Before installing `cix-o6n-repo`, verify its embedded key fingerprint:

```text
153D A567 0563 C430 55B8  2A20 8F66 A7C1 646C C2EA
```

## Licences

Files written for this project are GPL-3.0-or-later unless their SPDX header
says otherwise. Imported or modified Linux/Debian kernel material remains
GPL-2.0-only.
