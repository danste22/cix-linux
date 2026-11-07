# OBS packaging

OBS project: `home:danste22:o6n-debian-13`

Repository: `backports`, build architecture: `aarch64`.

The Gate 2 scaffold does not upload or trigger OBS packages. `_service` files,
package metadata, watcher workflows, failure polling, and the scoped runservice
token belong to the later OBS gate.

Project configuration currently requires:

```text
Keep: linux-libc-dev
```
