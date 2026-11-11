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
- Gate 4: local Docker chain builds the 7.2.12 O6N kernel, NPU, VPU, and
  firmware installer, signs the apt repository, and boots on a virgin Debian
  13 O6N. On 2026-11-09 the board smoke test passed, including `zfs/2.4.4`
  for `7.2.12+deb13o6n.1-arm64` (`modinfo` `2.4.4-1~bpo13+1`) and a file-backed
  pool scrub that repaired 0B with 0 errors.

## Local workspace

All generated state stays inside the project and is ignored by git:

```text
/Users/daniel/IdeaProjects/cix-linux/
├── artifacts/
├── build/
├── ccache/
├── downloads/
├── keys/
├── logs/
├── src/
├── tmp/
└── upstream/
```

`make help` lists the targets. Each build target records a stamp under
`artifacts/stamps/` and skips that step while the stamp is newer than its
inputs. Delete `artifacts/stamps` to run a finished chain again.

## Build from a fresh checkout

Host requirements: an arm64 machine, Docker with Compose v2, and git. The
Compose file builds `linux/arm64` images. Nothing under `artifacts/`, `build/`,
`ccache/`, `downloads/`, `keys/`, `logs/`, `src/`, `tmp/`, or `upstream/` is in
git. A fresh clone has none of them.

From the clone:

```bash
make init
```

Create the local repository key once. `scripts/50-make-repo.sh` signs with an
empty passphrase, and `gpg-agent` cannot keep its socket on the macOS bind
mount, so the key is generated on the container's own disk and then copied to
`keys/`:

```bash
docker compose run --rm --entrypoint bash repo-builder -lc '
set -euo pipefail
sign_home=$(mktemp -d /tmp/o6n-gpg.XXXXXX)
chmod 700 "$sign_home"
gpg --batch --pinentry-mode loopback --passphrase "" \
  --homedir "$sign_home" \
  --quick-generate-key "O6N local repo <repo@o6n.invalid>" ed25519 default never
mkdir -p /workspace/keys
chmod 700 /workspace/keys
cp -a "$sign_home"/. /workspace/keys/
find /workspace/keys -type s -delete
gpg --batch --homedir "$sign_home" --list-secret-keys --with-colons
'
```

Keep `keys/`. The signing script uses `/workspace/keys` and the fingerprint of
its single secret key. Set `LOCAL_REPO_GPG_KEY_ID` only when that directory
holds more than one secret key.

```bash
make repo
```

The signed repository is `artifacts/repo/`.

## Install on a fresh board

`artifacts/repo/` is the local development repository from `make repo`. A
board installs from the public OBS repository.

Use a Debian 13 netinstall. Secure Boot stays off. Add `contrib` to trixie,
and add backports with `contrib` and `non-free-firmware`:

```bash
printf '%s\n' \
  'deb http://deb.debian.org/debian trixie main contrib' \
  'deb http://deb.debian.org/debian trixie-backports main contrib non-free-firmware' \
  > /etc/apt/sources.list.d/backports.list
apt-get update
apt-get install -y -t trixie-backports linux-base firmware-misc-nonfree
```

Download `cix-o6n-repo` and read its key before trusting it. Stop if the
fingerprint is not `153D A567 0563 C430 55B8 2A20 8F66 A7C1 646C C2EA`.

```bash
curl -fsSLO https://download.opensuse.org/repositories/home:/danste22:/o6n-debian-13/backports/all/cix-o6n-repo_1.0.0+o6n1_all.deb
mkdir -p /tmp/o6n-repo-check
dpkg-deb -x cix-o6n-repo_1.0.0+o6n1_all.deb /tmp/o6n-repo-check
gpg --show-keys --with-fingerprint /tmp/o6n-repo-check/usr/share/keyrings/o6n-debian-13.asc
dpkg -i cix-o6n-repo_1.0.0+o6n1_all.deb
apt-get update
apt-get install -y \
  linux-image-o6n-arm64 \
  linux-headers-o6n-arm64 \
  cix-npu-driver-dkms \
  cix-vpu-driver-dkms \
  cix-vpu-libc-dev \
  cix-o6n-firmware-install
printf '%s\n' 'GRUB_CMDLINE_LINUX="clk_ignore_unused"' > /etc/default/grub.d/o6n-clk.cfg
update-grub
reboot
```

`linux-headers-o6n-arm64` pulls the matching headers, kbuild, and common
headers. Configuring `cix-o6n-firmware-install` downloads the 17 CIX firmware
files. After the next boot into `7.2.12+deb13o6n.1-arm64`, run
`scripts/board/boot-evidence.sh` and `scripts/board/accelerator-test.sh` as
root.

## Unattended kernel upgrades

A newer `linux-image-o6n-arm64` in OBS is not an accepted board kernel.
Debian's default unattended-upgrades origins do not include this OBS
repository. Leave the origin out of `Unattended-Upgrade::Allowed-Origins`.
Blacklist the metapackages as well:

```bash
cat > /etc/apt/apt.conf.d/51o6n-unattended-upgrades <<'EOF'
Unattended-Upgrade::Package-Blacklist {
    "linux-image-o6n-arm64";
    "linux-headers-o6n-arm64";
};
EOF
```

Install the next O6N kernel by hand after the board gate passes. The previous
O6N kernel stays selectable in GRUB.

## Firmware files

This repository, the OBS packages, and the GitHub Release do not contain the
17 CIX firmware files. `cix-o6n-firmware-install` downloads them when the
package is configured. The postinst runs `/usr/sbin/cix-o6n-firmware-fetch`.
Run that command again as root to repeat the download. Every file must match
`manifest.txt` before any file is installed.

The files are in
[cixtech/cix_proprietary__cix_proprietary](https://github.com/cixtech/cix_proprietary__cix_proprietary/tree/cix_p1_k6.6_master)
on branch `cix_p1_k6.6_master`, at commit
`6260fd1a596a6135a198f0f220e6ed70f3210532`. The installer uses that commit.
It does not follow the branch tip. `dsp_fw.bin` is
`cix_proprietary-debs/cix-audio-dsp/usr/lib/firmware/dsp_fw.bin`. The 16
`.fwb` files are in
`cix_proprietary-debs/cix-vpu-umd/usr/lib/firmware/`. Browse that tree to
inspect them. A new firmware commit is a separate pull request.

`watch-firmware.yml` runs daily. It compares branch `cix_p1_k6.6_master` with
`CIX_FIRMWARE_COMMIT` and hashes the same 17 files. One issue opens when the
branch moves. The issue names each file whose sha256 changed. When every file
still matches, the issue says the provisioning pin can stay. The workflow
does not change the manifest or the pin. The issue closes when the pin and
the branch head are the same commit again.

Mali CSF firmware comes from Debian `firmware-misc-nonfree` at
`/usr/lib/firmware/arm/mali/arch12.8/mali_csffw.bin`. The CIX tree also has a
`mali_csffw.bin`. This project does not install that copy.

## Board requirements

- UEFI hardware description: ACPI
- Kernel command line: `clk_ignore_unused`
- Secure Boot: off. The kernel is unsigned (`enable_signed = false`), and the NPU and VPU modules are unsigned DKMS modules. Secure Boot would refuse that kernel. Signing stays parked.
- Debian trixie-backports with `non-free-firmware` enabled

## Board validation

Run these on the O6N as root after the kernel, DKMS modules, and firmware
package are installed. Both scripts exit non-zero when a check fails.

`scripts/board/boot-evidence.sh` is read-only. It records the running ABI,
`clk_ignore_unused`, the protected SCMI clocks, Panthor, the NPU and VPU
device nodes, the connected DisplayPort output, the 17 CIX firmware files,
and Debian's Mali CSF firmware. Audio bind passes when `CIXH6062`, the DSP,
DMA-350, and the three I2S nodes have drivers. Without
`CONFIG_RESET_SKY1_AUDSS` those nodes stay unbound; the script reports that
and still exits zero when every other check passed.

`scripts/board/accelerator-test.sh` installs the trixie-backports Mesa
packages and removes `cix-gpu-umd` and `cix-mesa` if present, because their
`/opt/cixgpu-*` libraries override Debian's `libgbm`. It then runs
`eglinfo` on the GBM platform and `kmscube` on the connected DisplayPort
output. Panthor firmware is the Debian `firmware-misc-nonfree` file and is
not removed with those packages.

## ZFS DKMS board test

This test runs on the O6N after the kernel, headers, NPU, and VPU
packages are installed. It uses Debian's `zfs-dkms` package. This repository
does not build OpenZFS.

Checked 2026-11-08 on packages.debian.org:

| Suite | `zfs-dkms` | OpenZFS tag |
| --- | --- | --- |
| trixie | `2.3.9-0+deb13u1` | `zfs-2.3.9`, stable, 2026-08-21 |
| trixie-backports | `2.4.4-1~bpo13+1` | `zfs-2.4.4`, stable, 2026-08-21 |

The versions differ. Both tags are stable OpenZFS releases. `zfs-2.4.4` is
the current stable series and lists Linux 4.18 through 7.2, which covers
`7.2.12`. Install that backports package. Leave the trixie `2.3.9` package
uninstalled. Refuse a candidate whose upstream version contains `-rc`, or
any package from forky or sid.

`zfs-dkms` is in `contrib`. The O6N needs both of these source entries, with
`contrib` on the backports line:

```text
deb http://deb.debian.org/debian trixie main contrib
deb http://deb.debian.org/debian trixie-backports main contrib non-free-firmware
```

On the board, repeat the version check before installing:

```sh
apt-cache madison zfs-dkms
```

The trixie and trixie-backports lines must still be the two versions in the
table. Then install the backports modules and userland together, against the
headers of the running O6N kernel:

```sh
sudo apt update
sudo apt install -t trixie-backports zfs-dkms zfsutils-linux
dkms status
sudo modprobe zfs
modinfo -F version zfs
```

`dkms status` must show `zfs/2.4.4` installed for the running `uname -r`.
`modinfo` must print `2.4.4`.

The pool test uses a file vdev, so it does not partition a disk:

```sh
truncate -s 1G /var/tmp/zfs-smoke.img
sudo zpool create o6nsmoke /var/tmp/zfs-smoke.img
sudo zfs create o6nsmoke/data
sudo dd if=/dev/urandom of=/o6nsmoke/data/blob bs=1M count=64 status=progress
sudo zpool scrub o6nsmoke
sudo zpool wait -t scrub o6nsmoke
sudo zpool status -v o6nsmoke
sudo zpool export o6nsmoke
sudo zpool import -d /var/tmp o6nsmoke
sudo zpool destroy o6nsmoke
rm -f /var/tmp/zfs-smoke.img
```

Pass requires `errors: No known data errors`, a successful export and import,
and no new kernel oops from the `zfs` module in the journal.

## Existing CIX VPU package replacement

The vendor DKMS package depends on `cix-vpu-firmware`, which owns the same
paths managed by this project's verified installer. Replace both packages
explicitly:

```sh
sudo apt remove cix-vpu-driver-dkms cix-vpu-firmware
sudo apt install cix-o6n-firmware-install cix-vpu-driver-dkms cix-vpu-libc-dev
```

Do not let the two firmware ownership models coexist.

## Debian source watcher

`watch-debian.yml` runs daily. It verifies the signed trixie-backports
source index and compares the newest `linux` source package with
`refs.env`. A newer version opens one pull request on `watch/debian-linux`.
That pull request changes the Debian version, filenames, and sha256 pins,
and resets `O6N_PACKAGE_VERSION` to `+o6n1`. The CIX, NPU, VPU, and firmware
pins stay as they are.

Merging the pull request does not upload anything to OBS. Rebuild the
`linux-cix` source package from the merged pins and upload that `.dsc`.

`watch-obs.yml` reads the public `linux-cix` build status. It opens one
issue when the result is failed or unresolvable, and closes that issue when
the result succeeds.

## Accepted build archive

`release-accepted.yml` runs when you dispatch it with the exact O6N package
version, after that version has passed the board gate. It verifies the signed
OBS repository, downloads the `linux-cix` packages of that version, the
`.dsc`, the Debian tarball, and the public build log, and creates one GitHub
Release. The tag is `o6n-<version>` with each `~` written as `_`, because Git
rejects `~` in a tag. A second dispatch of the same version stops because
that release already exists.

The orig tarball is withheld when it contains firmware bytes. OBS remains the
apt repository. The release is the rollback copy of the accepted packages.

## OBS repository key

Before installing `cix-o6n-repo`, verify its embedded key fingerprint:

```text
153D A567 0563 C430 55B8  2A20 8F66 A7C1 646C C2EA
```

## Licences

Files written for this project are GPL-3.0-or-later unless their SPDX header
says otherwise. Imported or modified Linux/Debian kernel material remains
GPL-2.0-only.
