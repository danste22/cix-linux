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

Use a Debian 13 netinstall. Secure Boot stays off. Trixie `main` is already
present. Add `contrib` there, and add backports with `contrib` and
`non-free-firmware`. Copy `artifacts/repo` to `/var/tmp/o6n-repo` on the board.
The package names match the current `refs.env` pin.

```bash
printf '%s\n' 'deb http://deb.debian.org/debian trixie-backports main contrib non-free-firmware' \
  > /etc/apt/sources.list.d/backports.list
install -d /etc/apt/keyrings
cp /var/tmp/o6n-repo/o6n-local-repo.asc /etc/apt/keyrings/o6n-local.asc
cat > /etc/apt/sources.list.d/o6n-local.sources <<'EOF'
Types: deb
URIs: file:/var/tmp/o6n-repo
Suites: ./
Signed-By: /etc/apt/keyrings/o6n-local.asc
EOF
apt-get update
apt-get install -y -t trixie-backports linux-base firmware-misc-nonfree
apt-get install -y \
  linux-image-7.2.12+deb13o6n.1-arm64 \
  linux-headers-7.2.12+deb13o6n.1-arm64 \
  linux-kbuild-7.2.12+deb13o6n.1 \
  cix-npu-driver-dkms \
  cix-vpu-driver-dkms \
  cix-o6n-firmware-install
printf '%s\n' 'GRUB_CMDLINE_LINUX="clk_ignore_unused"' > /etc/default/grub.d/o6n-clk.cfg
update-grub
reboot
```

After the second boot into `7.2.12+deb13o6n.1-arm64`, run
`scripts/board/boot-evidence.sh` and `scripts/board/accelerator-test.sh` as
root.

## Board requirements

- UEFI hardware description: ACPI
- Kernel command line: `clk_ignore_unused`
- Secure Boot: disabled for the initial unsigned build
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

This test runs on the O6N after the local kernel, headers, NPU, and VPU
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

## OBS repository key

Before installing `cix-o6n-repo`, verify its embedded key fingerprint:

```text
153D A567 0563 C430 55B8  2A20 8F66 A7C1 646C C2EA
```

## Licences

Files written for this project are GPL-3.0-or-later unless their SPDX header
says otherwise. Imported or modified Linux/Debian kernel material remains
GPL-2.0-only.
