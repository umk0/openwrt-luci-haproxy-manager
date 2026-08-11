#!/usr/bin/env python3
import json
import pathlib
import struct
import sys


LANGS = ("ru", "es", "ko", "ja", "zh-cn")


def sfh_get16(data, pos):
    return data[pos] | (data[pos + 1] << 8)


def signed_byte(value):
    return value - 256 if value > 127 else value


def u32(value):
    return value & 0xFFFFFFFF


def sfh_hash(data):
    if isinstance(data, str):
        data = data.encode("utf-8")

    length = len(data)
    if length <= 0:
        return 0

    h = length
    pos = 0
    rem = length & 3
    blocks = length >> 2

    for _ in range(blocks):
        h = u32(h + sfh_get16(data, pos))
        tmp = u32((sfh_get16(data, pos + 2) << 11) ^ h)
        h = u32((h << 16) ^ tmp)
        pos += 4
        h = u32(h + (h >> 11))

    if rem == 3:
        h = u32(h + sfh_get16(data, pos))
        h = u32(h ^ (h << 16))
        h = u32(h ^ (signed_byte(data[pos + 2]) << 18))
        h = u32(h + (h >> 11))
    elif rem == 2:
        h = u32(h + sfh_get16(data, pos))
        h = u32(h ^ (h << 11))
        h = u32(h + (h >> 17))
    elif rem == 1:
        h = u32(h + signed_byte(data[pos]))
        h = u32(h ^ (h << 10))
        h = u32(h + (h >> 1))

    h = u32(h ^ (h << 3))
    h = u32(h + (h >> 5))
    h = u32(h ^ (h << 4))
    h = u32(h + (h >> 17))
    h = u32(h ^ (h << 25))
    h = u32(h + (h >> 6))
    return h


def write_lmo(catalog, out_path):
    data = bytearray()
    entries = []

    for key in sorted(catalog):
        value = catalog[key]
        if not isinstance(key, str) or not isinstance(value, str) or key == value:
            continue

        key_id = sfh_hash(key)
        value_bytes = value.encode("utf-8")
        offset = len(data)
        data.extend(value_bytes)
        data.extend(b"\0" * ((4 - (len(value_bytes) % 4)) % 4))
        entries.append((key_id, 1, offset, len(value_bytes)))

    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not entries:
        if out_path.exists():
            out_path.unlink()
        return

    entries.sort(key=lambda item: item[0])
    index_offset = len(data)

    for entry in entries:
        data.extend(struct.pack("!IIII", *entry))

    data.extend(struct.pack("!I", index_offset))
    out_path.write_bytes(data)


def main():
    package_root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent

    for lang in LANGS:
        json_path = package_root / "i18n" / lang / "www" / "luci-static" / "resources" / "i18n" / f"haproxy-manager.{lang}.json"
        lmo_path = package_root / "i18n" / lang / "usr" / "lib" / "lua" / "luci" / "i18n" / f"haproxy-manager.{lang}.lmo"

        if not json_path.exists():
            continue

        catalog = json.loads(json_path.read_text(encoding="utf-8"))
        write_lmo(catalog, lmo_path)
        print(lmo_path)


if __name__ == "__main__":
    main()
