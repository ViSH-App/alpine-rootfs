# Alpine Root Filesystem

A minimal Alpine Linux root filesystem for 64-bit ARM systems. The build starts
from an official, version-pinned Alpine minirootfs and produces plain compressed
tar archives without container image metadata.

## Artifacts

Each release provides:

- `alpine-aarch64-rootfs.tar.gz`
- `alpine-aarch64-rootfs.tar.gz.sha256`
- `alpine-aarch64-rootfs.tar.zst`
- `alpine-aarch64-rootfs.tar.zst.sha256`

The root filesystem includes Bash, common editors, Git, SSH and network tools,
TLS certificates, timezone data, and other small command-line utilities listed
in [`build/packages.txt`](build/packages.txt). No system services are enabled.

## Download

Use the stable latest-release URLs:

```text
https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.gz
https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.gz.sha256
https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.zst
https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.zst.sha256
```

Verify an artifact before use:

```sh
shasum -a 256 -c alpine-aarch64-rootfs.tar.gz.sha256
```

## Build

Docker is required. Building on a non-ARM64 host also requires ARM64 emulation
through QEMU/binfmt.

```sh
./build/build.sh
```

To select a specific Alpine release:

```sh
ALPINE_VERSION=3.23.3 ./build/build.sh
```

Artifacts are written to `dist/`. Only the `aarch64` target is currently
supported.

## Releases

GitHub Actions builds and publishes releases from `main`, on a weekly schedule,
or when manually triggered. Release tags use the format
`v<alpine-version>-<UTC-timestamp>`.
