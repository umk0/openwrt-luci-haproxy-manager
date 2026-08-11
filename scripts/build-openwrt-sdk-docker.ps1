param(
    [Parameter(Mandatory = $true)]
    [string]$SdkArchive,

    [string]$Image = "ubuntu:24.04"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ArchivePath = (Resolve-Path $SdkArchive).Path
$ArchiveName = Split-Path $ArchivePath -Leaf
$Dist = Join-Path $ProjectRoot "dist"

New-Item -ItemType Directory -Force -Path $Dist | Out-Null

$ProjectMount = ($ProjectRoot -replace "\\", "/")
$ArchiveMount = ($ArchivePath -replace "\\", "/")

$script = @"
set -eux
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential ca-certificates zstd file gawk gettext git python3 unzip \
  rsync wget perl libncurses-dev >/dev/null

rm -rf /build/sdk
mkdir -p /build /work/dist
tar --zstd -xf "/archive/$ArchiveName" -C /build
sdk_dir=`$(find /build -maxdepth 1 -type d -name 'openwrt-sdk-*' | head -1)
test -n "`$sdk_dir"
mv "`$sdk_dir" /build/sdk
rm -rf /build/sdk/package/luci-app-haproxy-manager
cp -R /work/luci-app-haproxy-manager /build/sdk/package/
cd /build/sdk
make defconfig
make package/luci-app-haproxy-manager/compile V=s
if find /build/sdk/bin -type f -name 'luci-app-haproxy-manager*.apk' -print -quit | grep -q .; then
  find /work/dist -maxdepth 1 -type f \( \
    -name 'luci-app-haproxy-manager*.apk' -o \
    -name 'luci-i18n-haproxy-manager*.apk' \
  \) -delete
fi
if find /build/sdk/bin -type f -name 'luci-app-haproxy-manager*.ipk' -print -quit | grep -q .; then
  find /work/dist -maxdepth 1 -type f \( \
    -name 'luci-app-haproxy-manager*.ipk' -o \
    -name 'luci-i18n-haproxy-manager*.ipk' \
  \) -delete
fi
find /build/sdk/bin -type f \( \
  -name 'luci-app-haproxy-manager*.ipk' -o \
  -name 'luci-app-haproxy-manager*.apk' -o \
  -name 'luci-i18n-haproxy-manager*.ipk' -o \
  -name 'luci-i18n-haproxy-manager*.apk' \
\) -exec cp -v {} /work/dist/ \;
find /work/dist -maxdepth 1 -type f \( \
  -name 'luci-app-haproxy-manager*.ipk' -o \
  -name 'luci-app-haproxy-manager*.apk' -o \
  -name 'luci-i18n-haproxy-manager*.ipk' -o \
  -name 'luci-i18n-haproxy-manager*.apk' \
\) -print
"@

docker run --rm `
    -v "${ProjectMount}:/work" `
    -v "${ArchiveMount}:/archive/${ArchiveName}:ro" `
    -w /build `
    $Image `
    bash -lc $script
