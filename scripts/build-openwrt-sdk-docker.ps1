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
/work/scripts/build-openwrt-sdk.sh /build/sdk
"@

docker run --rm `
    -v "${ProjectMount}:/work" `
    -v "${ArchiveMount}:/archive/${ArchiveName}:ro" `
    -w /build `
    $Image `
    bash -lc $script
