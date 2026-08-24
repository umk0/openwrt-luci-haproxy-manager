param(
    [Parameter(Mandatory = $true)]
    [string]$SdkArchive,

    [string]$Image = "ubuntu:24.04"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ArchivePath = (Resolve-Path $SdkArchive).Path
$ArchiveName = Split-Path $ArchivePath -Leaf
$SeriesMatch = [regex]::Match($ArchiveName, '^openwrt-sdk-(\d+\.\d+)')
if (-not $SeriesMatch.Success) {
    throw "Cannot determine the OpenWrt release series from $ArchiveName"
}
$LuciBranch = "openwrt-$($SeriesMatch.Groups[1].Value)"
$Dist = Join-Path $ProjectRoot "dist"
$PackageExtension = if ($SeriesMatch.Groups[1].Value -eq "24.10") { ".ipk" } else { ".apk" }

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Get-ChildItem -Path $Dist -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "luci-app-haproxy-manager*$PackageExtension" -or
        $_.Name -like "luci-i18n-haproxy-manager*$PackageExtension"
    } |
    Remove-Item -Force

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
/work/scripts/build-openwrt-sdk.sh /build/sdk "$LuciBranch"
"@
$script = $script -replace "`r`n", "`n"

docker run --rm `
    -v "${ProjectMount}:/work" `
    -v "${ArchiveMount}:/archive/${ArchiveName}:ro" `
    -w /build `
    $Image `
    bash -lc $script

if ($LASTEXITCODE -ne 0) {
    throw "OpenWrt SDK build failed with exit code $LASTEXITCODE"
}

$BasePackages = @(Get-ChildItem -Path $Dist -File |
    Where-Object { $_.Name -like "luci-app-haproxy-manager*$PackageExtension" })
if ($BasePackages.Count -ne 1 -or $BasePackages[0].Length -eq 0) {
    throw "OpenWrt SDK did not produce exactly one non-empty base $PackageExtension package"
}
