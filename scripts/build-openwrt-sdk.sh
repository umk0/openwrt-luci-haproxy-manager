#!/bin/sh
set -eu

SDK="${1:-}"
LUCI_BRANCH="${2:-}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
	echo "Usage: $0 /path/to/openwrt-sdk [openwrt-XX.XX]" >&2
	exit 2
fi

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PKG_SRC="$ROOT/luci-app-haproxy-manager"
LUCI_FEED="$SDK/feeds/luci"
PKG_DST="$LUCI_FEED/applications/luci-app-haproxy-manager"
LINK_DIR="$SDK/package/feeds/luci"
DIST="$ROOT/dist"

if [ ! -f "$LUCI_FEED/luci.mk" ]; then
	if [ -z "$LUCI_BRANCH" ]; then
		series="$(basename "$SDK" | sed -n 's/^openwrt-sdk-\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
		LUCI_BRANCH="openwrt-$series"
	fi
	if [ "$LUCI_BRANCH" = "openwrt-" ]; then
		echo "Cannot determine the matching LuCI release branch for $SDK" >&2
		exit 2
	fi
	rm -rf "$LUCI_FEED"
	git clone --depth 1 --branch "$LUCI_BRANCH" https://github.com/openwrt/luci.git "$LUCI_FEED"
fi

rm -rf "$PKG_DST"
mkdir -p "$(dirname "$PKG_DST")"
cp -R "$PKG_SRC" "$PKG_DST"
mkdir -p "$LINK_DIR"
rm -rf "$LINK_DIR/luci-app-haproxy-manager" "$LINK_DIR/luci-base" "$LINK_DIR/csstidy"
ln -s "../../../feeds/luci/applications/luci-app-haproxy-manager" "$LINK_DIR/luci-app-haproxy-manager"
mkdir -p "$DIST"

make -C "$LUCI_FEED/modules/luci-base/src" clean po2lmo
mkdir -p "$SDK/staging_dir/hostpkg/bin"
install -m 0755 "$LUCI_FEED/modules/luci-base/src/po2lmo" "$SDK/staging_dir/hostpkg/bin/po2lmo"

cd "$SDK"
make defconfig
make package/luci-app-haproxy-manager/clean V=s
pkg_version="$(sed -n 's/^PKG_VERSION:=//p' "$PKG_DST/Makefile")"
pkg_release="$(sed -n 's/^PKG_RELEASE:=//p' "$PKG_DST/Makefile")"
make package/luci-app-haproxy-manager/compile V=s \
	CONFIG_LUCI_JSMIN= CONFIG_LUCI_CSSTIDY= \
	PKG_PO_VERSION="${pkg_version}-r${pkg_release}"

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
