# O6N Debian kernel

Debian trixie-backports kernel and companion packages for the Radxa Orion O6N.

This repository contains build tooling and packaging only. It does not contain
proprietary firmware. See `PLAN.md` for the approved design and
`docs/adr/0001-firmware-fetched-at-install-not-shipped.md` for the firmware
decision.

## Gate 2 status

The repository is scaffolded, but no kernel, DKMS module, firmware package, or
container image has been built yet.

## Local workspace

Generated source, downloads and artifacts live under:

```text
/Volumes/M1 MBP/cix-linux
```

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
