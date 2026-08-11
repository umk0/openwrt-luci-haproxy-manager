# LuCI HAProxy Manager

[![Build and release packages](https://github.com/umk0/openwrt-luci-haproxy-manager/actions/workflows/build.yml/badge.svg)](https://github.com/umk0/openwrt-luci-haproxy-manager/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/umk0/openwrt-luci-haproxy-manager)](https://github.com/umk0/openwrt-luci-haproxy-manager/releases/latest)

LuCI application for publishing Web and TCP services through HAProxy on
OpenWrt. The interface uses service presets while retaining an expert editor
for `/etc/haproxy.cfg`.

## Features

- One Web service publishes HTTP Host and HTTPS SNI together, with separate
  backend ports.
- SSH and Remote Desktop presets with sensible port defaults.
- Custom TCP services with multiple `public:destination` port mappings.
- Optional WAN firewall rule synchronization and conflict detection.
- Syntax validation before HAProxy restarts.
- Named recovery points with one-click restore for HAProxy, firewall, and
  uHTTPd state.
- Optional uHTTPd binding to the LAN address so HAProxy can own WAN ports 80/443.
- Responsive LuCI views built from standard theme classes.
- English base package with optional Russian, Spanish, Korean, Japanese, and
  Simplified Chinese packages.
- Native LuCI packaging and PO catalogs compatible with the official
  `openwrt/luci` build system and Weblate.

HAProxy does not proxy UDP. Continue to use OpenWrt firewall redirects for UDP
port forwarding.

## Supported OpenWrt versions

| OpenWrt series | Package manager | Package format | CI targets |
| --- | --- | --- | --- |
| 24.10 | `opkg` | `.ipk` | x86_64, ARM64, MIPS |
| 25.12 | `apk` | `.apk` | x86_64, ARM64, MIPS |

The application package is architecture-independent. SDK builds still need to
target the same OpenWrt release as the router so package metadata and
dependencies match. GitHub Actions resolves the newest patch release in both
maintained series directly from the official OpenWrt download index. End-of-life
OpenWrt releases are not part of the compatibility matrix.

## Install

Copy the base package and, optionally, one language package to `/tmp`.

OpenWrt 24.10:

```sh
opkg update
opkg install /tmp/luci-app-haproxy-manager_*.ipk
opkg install /tmp/luci-i18n-haproxy-manager-ru_*.ipk
/etc/init.d/rpcd restart
```

OpenWrt 25.12 and newer:

```sh
apk add --no-network --allow-untrusted /tmp/luci-app-haproxy-manager-*.apk
apk add --no-network --allow-untrusted /tmp/luci-i18n-haproxy-manager-ru-*.apk
/etc/init.d/rpcd restart
```

Local packages are unsigned, which is why `--allow-untrusted` is required for
`apk`. Packages from a signed repository should be installed without that flag.

The application appears under `Services -> HAProxy`. The Services page is the
default screen.

## Routing modes

| Service | Public match | Backend |
| --- | --- | --- |
| Web | One domain on shared HTTP and HTTPS ports | Host with separate HTTP and HTTPS ports |
| SSH | Dedicated public TCP port | Host and SSH port |
| Remote Desktop | Dedicated public TCP port | Host and RDP port |
| Custom TCP | One or more dedicated public TCP ports | Host and mapped ports |

Each public TCP port must be unique. The generator rejects conflicts with the
shared Web listeners and with other TCP services. Firewall automation manages
only rules marked as owned by HAProxy Manager. Existing redirects are reported
or disabled during apply according to the selected conflict policy.

## Build

Run source checks and build architecture-independent `.ipk` files:

```sh
python3 scripts/check.py
python3 scripts/build-ipk.py
python3 scripts/check.py --dist
```

Build through an extracted OpenWrt SDK:

```sh
sh scripts/build-openwrt-sdk.sh /path/to/openwrt-sdk
```

On Windows with Docker Desktop:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-openwrt-sdk-docker.ps1 `
  -SdkArchive .\openwrt-sdk-25.12.5-mediatek-mt7622_gcc-14.3.0_musl.Linux-x86_64.tar.zst
```

Build outputs are copied to `dist/`. GitHub Actions validates the latest 24.10
and 25.12 SDKs on x86_64, ARM64, and MIPS for pushes, pull requests, manual runs,
and a weekly schedule. Tags matching `v*` create a GitHub Release containing:

- individual base and language packages;
- separate IPK and APK ZIP bundles;
- installation instructions and SHA-256 checksums.

The build helper fetches the matching official LuCI release branch and stages
the application under `feeds/luci/applications/`. The same `luci.mk` used by
the official LuCI repository builds both the base and translation packages.

## Configuration safety

Before applying a generated or manually edited configuration, the package:

1. Generates or writes a temporary file.
2. Runs `haproxy -c` against that file.
3. Saves the current HAProxy, firewall, uHTTPd, and UCI configuration.
4. Installs the validated file and restarts the affected services.

Emergency rollback over SSH:

```sh
/usr/libexec/haproxy-manager/rollback last
```

Backups are stored in `/root/haproxy-manager-backups` by default. Only the seven
newest recovery points are retained; older snapshots are removed automatically.

## Development

Package sources live in `luci-app-haproxy-manager/`. Keep UI strings in the
locale JSON catalogs; `scripts/check.py` reports missing translations. The
build regenerates LuCI `.lmo` files before packaging.

Licensed under the MIT License.
