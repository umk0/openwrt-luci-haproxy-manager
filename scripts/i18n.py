#!/usr/bin/env python3
import argparse
import ast
import json
import pathlib
import struct


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "luci-app-haproxy-manager"
LANGUAGES = (
    ("ru", "ru", "Russian"),
    ("es", "es", "Spanish"),
    ("ko", "ko", "Korean"),
    ("ja", "ja", "Japanese"),
    ("zh_Hans", "zh-cn", "Simplified Chinese"),
)


def parse_po(path):
    catalog = {}
    msgid = None
    msgstr = None
    active = None

    def finish():
        nonlocal msgid, msgstr, active
        if msgid and msgstr is not None:
            catalog[msgid] = msgstr
        msgid = None
        msgstr = None
        active = None

    for raw_line in path.read_text(encoding="utf-8-sig").splitlines() + [""]:
        line = raw_line.strip()
        if not line:
            finish()
        elif line.startswith("#"):
            continue
        elif line.startswith("msgid "):
            if msgid is not None:
                finish()
            msgid = ast.literal_eval(line[6:].strip())
            active = "msgid"
        elif line.startswith("msgstr "):
            msgstr = ast.literal_eval(line[7:].strip())
            active = "msgstr"
        elif line.startswith('"'):
            value = ast.literal_eval(line)
            if active == "msgid":
                msgid = (msgid or "") + value
            elif active == "msgstr":
                msgstr = (msgstr or "") + value
        elif line.startswith(("msgctxt ", "msgid_plural ", "msgstr[")):
            raise ValueError(f"unsupported plural or context entry in {path}: {raw_line}")

    return catalog


def write_po(catalog, language, path):
    lines = [
        'msgid ""',
        'msgstr ""',
        f'"Language: {language}\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        "",
    ]

    for msgid in sorted(catalog, key=str.casefold):
        lines.extend((
            f"msgid {json.dumps(msgid, ensure_ascii=False)}",
            f"msgstr {json.dumps(catalog[msgid], ensure_ascii=False)}",
            "",
        ))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


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

    result = length
    pos = 0
    remainder = length & 3

    for _ in range(length >> 2):
        result = u32(result + sfh_get16(data, pos))
        temporary = u32((sfh_get16(data, pos + 2) << 11) ^ result)
        result = u32((result << 16) ^ temporary)
        pos += 4
        result = u32(result + (result >> 11))

    if remainder == 3:
        result = u32(result + sfh_get16(data, pos))
        result = u32(result ^ (result << 16))
        result = u32(result ^ (signed_byte(data[pos + 2]) << 18))
        result = u32(result + (result >> 11))
    elif remainder == 2:
        result = u32(result + sfh_get16(data, pos))
        result = u32(result ^ (result << 11))
        result = u32(result + (result >> 17))
    elif remainder == 1:
        result = u32(result + signed_byte(data[pos]))
        result = u32(result ^ (result << 10))
        result = u32(result + (result >> 1))

    result = u32(result ^ (result << 3))
    result = u32(result + (result >> 5))
    result = u32(result ^ (result << 4))
    result = u32(result + (result >> 17))
    result = u32(result ^ (result << 25))
    return u32(result + (result >> 6))


def write_lmo(catalog, output):
    data = bytearray()
    entries = []

    for key in sorted(catalog):
        value = catalog[key]
        if not key or not value or key == value:
            continue

        value_bytes = value.encode("utf-8")
        offset = len(data)
        data.extend(value_bytes)
        data.extend(b"\0" * ((4 - (len(value_bytes) % 4)) % 4))
        entries.append((sfh_hash(key), 1, offset, len(value_bytes)))

    output.parent.mkdir(parents=True, exist_ok=True)
    entries.sort(key=lambda item: item[0])
    index_offset = len(data)

    for entry in entries:
        data.extend(struct.pack("!IIII", *entry))

    data.extend(struct.pack("!I", index_offset))
    output.write_bytes(data)


def compile_catalogs(output_root):
    outputs = {}
    for po_language, package_language, _ in LANGUAGES:
        source = PACKAGE / "po" / po_language / "haproxy-manager.po"
        output = output_root / package_language / "usr" / "lib" / "lua" / "luci" / "i18n" / f"haproxy-manager.{package_language}.lmo"
        write_lmo(parse_po(source), output)
        outputs[package_language] = output_root / package_language
    return outputs


def main():
    parser = argparse.ArgumentParser(description="Manage HAProxy Manager translation catalogs")
    parser.add_argument("command", choices=("compile",))
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / ".build" / "i18n")
    args = parser.parse_args()

    for output in compile_catalogs(args.output.resolve()).values():
        print(output)


if __name__ == "__main__":
    main()
