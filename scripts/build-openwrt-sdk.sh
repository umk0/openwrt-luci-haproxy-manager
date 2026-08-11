#!/bin/sh
set -eu

SDK="${1:-}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
	echo "Usage: $0 /path/to/openwrt-sdk" >&2
	exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PKG_SRC="$ROOT/luci-app-haproxy-manager"
PKG_DST="$SDK/package/luci-app-haproxy-manager"
DIST="$ROOT/dist"

rm -rf "$PKG_DST"
mkdir -p "$(dirname "$PKG_DST")"
cp -R "$PKG_SRC" "$PKG_DST"
mkdir -p "$DIST"

cd "$SDK"
make defconfig
make package/luci-app-haproxy-manager/clean V=s
make package/luci-app-haproxy-manager/compile V=s

if find "$SDK/bin" -type f -name 'luci-app-haproxy-manager*.apk' -print -quit | grep -q .; then
	find "$DIST" -maxdepth 1 -type f \( \
		-name 'luci-app-haproxy-manager*.apk' -o \
		-name 'luci-i18n-haproxy-manager*.apk' \
	\) -delete
fi

if find "$SDK/bin" -type f -name 'luci-app-haproxy-manager*.ipk' -print -quit | grep -q .; then
	find "$DIST" -maxdepth 1 -type f \( \
		-name 'luci-app-haproxy-manager*.ipk' -o \
		-name 'luci-i18n-haproxy-manager*.ipk' \
	\) -delete
fi

find "$SDK/bin" -type f \( \
	-name 'luci-app-haproxy-manager*.ipk' -o \
	-name 'luci-app-haproxy-manager*.apk' -o \
	-name 'luci-i18n-haproxy-manager*.ipk' -o \
	-name 'luci-i18n-haproxy-manager*.apk' \
\) -exec cp -f {} "$DIST/" \;

find "$DIST" -maxdepth 1 -type f \( \
	-name 'luci-app-haproxy-manager*.ipk' -o \
	-name 'luci-app-haproxy-manager*.apk' -o \
	-name 'luci-i18n-haproxy-manager*.ipk' -o \
	-name 'luci-i18n-haproxy-manager*.apk' \
\) -print
