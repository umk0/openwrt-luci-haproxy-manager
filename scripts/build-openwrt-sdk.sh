#!/bin/sh
set -eu

SDK="${1:-}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
	echo "Usage: $0 /path/to/openwrt-sdk" >&2
	exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PKG_SRC="$ROOT/luci-app-haproxy-manager"
LUCI_FEED="$SDK/feeds/luci"
PKG_DST="$LUCI_FEED/applications/luci-app-haproxy-manager"
PKG_LINK="$SDK/package/feeds/luci/luci-app-haproxy-manager"
DIST="$ROOT/dist"

if [ ! -f "$LUCI_FEED/luci.mk" ]; then
	echo "The SDK does not contain the LuCI feed sources: $LUCI_FEED" >&2
	exit 2
fi

rm -rf "$PKG_DST"
mkdir -p "$(dirname "$PKG_DST")"
cp -R "$PKG_SRC" "$PKG_DST"
rm -rf "$PKG_LINK"
mkdir -p "$(dirname "$PKG_LINK")"
ln -s "../../../feeds/luci/applications/luci-app-haproxy-manager" "$PKG_LINK"
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
