# OBS packaging

OBS project: `home:danste22:o6n-debian-13`

The project repository is named `backports`. Its public apt URL is:

```text
https://download.opensuse.org/repositories/home:/danste22:/o6n-debian-13/backports/
```

`obs/_config` is the project configuration to apply. It contains `Keep: linux-libc-dev` and no `Prefer:` line. These files do not upload or trigger a build.

Source services download the pinned inputs. The build itself has no network. `debian/rules` at the repository root runs the existing kernel scripts for the `linux-cix` package. The Debian `.dsc` is stored as `linux_7.3.4-1~bpo13+1.dsc.download` because a top-level `*.dsc` would make obs-build compile that source instead of this package. The NPU and VPU packages unpack the downloaded upstream archive, and the firmware and repository packages build from `packaging/`.

Published kernel binaries are the `+deb13o6n` ABI packages plus `linux-image-o6n-arm64` and `linux-headers-o6n-arm64`. The build does not publish `linux-image-arm64`, `linux-headers-arm64`, `linux-base-arm64`, `linux-bpf-dev`, `linux-libc-dev`, debug packages, or installer udebs.
