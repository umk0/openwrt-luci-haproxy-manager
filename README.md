# LuCI HAProxy Manager

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

HAProxy does not proxy UDP. Continue to use OpenWrt firewall redirects for UDP
port forwarding.

## Supported OpenWrt versions

- OpenWrt 24.10 uses `.ipk` packages and `opkg`.
- OpenWrt 25.12 and newer use `.apk` packages and `apk`.

The application package is architecture-independent. SDK builds still need to
target the same OpenWrt release as the router so package metadata and
dependencies match.

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
apk update
apk add --allow-untrusted /tmp/luci-app-haproxy-manager-*.apk
apk add --allow-untrusted /tmp/luci-i18n-haproxy-manager-ru-*.apk
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

Build outputs are copied to `dist/`. GitHub Actions builds `.ipk` files on every
push and can build OpenWrt 25.12 `.apk` files on tagged or manually dispatched
runs.

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
