#!/usr/bin/env python3
import argparse
import io
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "luci-app-haproxy-manager"
VIEWS = PACKAGE / "htdocs" / "luci-static" / "resources" / "view" / "haproxy-manager"
I18N = PACKAGE / "i18n"
DIST = ROOT / "dist"
LANGS = ("ru", "es", "ko", "ja", "zh-cn")
DYNAMIC_TRANSLATIONS = {"On", "Off", "Running", "Stopped"}


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def translation_keys():
    pattern = re.compile(r"(?<![A-Za-z0-9_])t\(\s*(['\"])(.*?)\1\s*\)")
    keys = set(DYNAMIC_TRANSLATIONS)

    for path in VIEWS.glob("*.js"):
        keys.update(match.group(2) for match in pattern.finditer(path.read_text(encoding="utf-8")))

    menu = json.loads((PACKAGE / "root" / "usr" / "share" / "luci" / "menu.d" / "luci-app-haproxy-manager.json").read_text(encoding="utf-8"))
    keys.update(item["title"] for item in menu.values() if "title" in item)
    return keys


def check_translations():
    required = translation_keys()
    errors = 0

    for lang in LANGS:
        path = I18N / lang / "www" / "luci-static" / "resources" / "i18n" / f"haproxy-manager.{lang}.json"
        try:
            catalog = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors += fail(f"cannot read {path.relative_to(ROOT)}: {exc}")
            continue

        missing = sorted(required - set(catalog))
        if missing:
            errors += fail(f"{lang} translation is missing: {', '.join(missing)}")

    return errors


def check_syntax():
    errors = 0
    node = shutil.which("node")
    shell = shutil.which("sh")

    if node:
        for path in (PACKAGE / "htdocs").rglob("*.js"):
            result = subprocess.run([node, "--check", str(path)], capture_output=True, text=True)
            if result.returncode:
                errors += fail(f"JavaScript syntax error in {path.relative_to(ROOT)}: {result.stderr.strip()}")

    if shell:
        for path in (PACKAGE / "root" / "usr" / "libexec" / "haproxy-manager").iterdir():
            if not path.is_file():
                continue
            result = subprocess.run([shell, "-n", str(path)], capture_output=True, text=True)
            if result.returncode:
                errors += fail(f"shell syntax error in {path.relative_to(ROOT)}: {result.stderr.strip()}")

        result = subprocess.run([shell, "-n", str(ROOT / "scripts" / "build-openwrt-sdk.sh")], capture_output=True, text=True)
        if result.returncode:
            errors += fail(f"shell syntax error in scripts/build-openwrt-sdk.sh: {result.stderr.strip()}")

    return errors


def check_package_contents():
    errors = 0
    base_packages = sorted(DIST.glob("luci-app-haproxy-manager_*.ipk"))

    if len(base_packages) != 1:
        return fail("expected exactly one base ipk in dist; run scripts/build-ipk.py first")

    with tarfile.open(base_packages[0], mode="r:gz") as outer:
        outer_names = set(outer.getnames())
        required_outer = {"./debian-binary", "./control.tar.gz", "./data.tar.gz"}
        if not required_outer.issubset(outer_names):
            errors += fail(f"malformed ipk archive: {base_packages[0].name}")
            return errors

        data_member = outer.extractfile("./data.tar.gz")
        if data_member is None:
            return errors + fail("ipk data.tar.gz cannot be read")

        with tarfile.open(fileobj=io.BytesIO(data_member.read()), mode="r:gz") as data_tar:
            payload = set(data_tar.getnames())

    required_payload = {
        "./usr/libexec/haproxy-manager/apply",
        "./usr/libexec/haproxy-manager/backups",
        "./usr/libexec/haproxy-manager/firewall-plan",
        "./usr/libexec/haproxy-manager/firewall-sync",
        "./usr/libexec/haproxy-manager/migrate",
        "./usr/libexec/haproxy-manager/status",
        "./www/luci-static/resources/haproxy-manager/style.css",
        "./www/luci-static/resources/view/haproxy-manager/routes.js",
        "./www/luci-static/resources/view/haproxy-manager/settings.js",
        "./www/luci-static/resources/view/haproxy-manager/status.js",
    }
    missing = sorted(required_payload - payload)
    if missing:
        errors += fail(f"base ipk is missing payload files: {', '.join(missing)}")

    for lang in LANGS:
        if not list(DIST.glob(f"luci-i18n-haproxy-manager-{lang}_*.ipk")):
            errors += fail(f"missing {lang} translation ipk")

    return errors


def main():
    parser = argparse.ArgumentParser(description="Check LuCI HAProxy Manager sources and packages")
    parser.add_argument("--dist", action="store_true", help="also inspect built ipk artifacts")
    args = parser.parse_args()

    errors = check_translations() + check_syntax()
    if args.dist:
        errors += check_package_contents()

    if errors:
        return 1

    print("All checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
