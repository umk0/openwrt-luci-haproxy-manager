#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import urllib.request


INDEX_URL = "https://downloads.openwrt.org/releases/"
SERIES = (("24.10", "ipk"), ("25.12", "apk"))
TARGETS = (
    ("x86/64", "x86-64", "x86_64", True),
    ("mediatek/mt7622", "mediatek-mt7622", "ARM64", False),
    ("ramips/mt7621", "ramips-mt7621", "MIPS", False),
)


def fetch_index(url):
    request = urllib.request.Request(url, headers={"User-Agent": "luci-haproxy-manager-ci"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


def latest_release(index, series):
    versions = {
        match.group(1)
        for match in re.finditer(rf'href="({re.escape(series)}\.\d+)/"', index)
    }
    if not versions:
        raise RuntimeError(f"No final OpenWrt {series} release found at {INDEX_URL}")
    return max(versions, key=lambda value: tuple(int(part) for part in value.split(".")))


def release_data(index):
    versions = {series: latest_release(index, series) for series, _ in SERIES}
    matrix = []
    for series, package_format in SERIES:
        for target, target_id, processor, publish in TARGETS:
            matrix.append(
                {
                    "series": series,
                    "version": versions[series],
                    "format": package_format,
                    "target": target,
                    "target_id": target_id,
                    "processor": processor,
                    "publish": publish,
                }
            )
    return versions, {"include": matrix}


def main():
    parser = argparse.ArgumentParser(description="Resolve maintained OpenWrt patch releases")
    parser.add_argument("--github-output", type=pathlib.Path)
    parser.add_argument("--index-url", default=INDEX_URL)
    args = parser.parse_args()

    versions, matrix = release_data(fetch_index(args.index_url))
    values = {
        "matrix": json.dumps(matrix, separators=(",", ":")),
        "legacy_version": versions["24.10"],
        "modern_version": versions["25.12"],
    }

    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(f"{key}={value}\n")
    else:
        print(json.dumps(values, indent=2))


if __name__ == "__main__":
    main()
