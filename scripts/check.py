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

from i18n import LANGUAGES, parse_po


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "luci-app-haproxy-manager"
DIST = ROOT / "dist"


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def translation_keys():
    pattern = re.compile(r"(?<![A-Za-z0-9_])_\(\s*(['\"])(.*?)\1\s*\)")
    keys = set()

    for path in (PACKAGE / "htdocs" / "luci-static" / "resources").rglob("*.js"):
        keys.update(match.group(2) for match in pattern.finditer(path.read_text(encoding="utf-8")))

    for path in (PACKAGE / "root" / "usr" / "share").rglob("*.json"):
        def collect(value):
            if isinstance(value, dict):
                for name, item in value.items():
                    if name in ("title", "description") and isinstance(item, str):
                        keys.add(item)
                    else:
                        collect(item)
            elif isinstance(value, list):
                for item in value:
                    collect(item)

        collect(json.loads(path.read_text(encoding="utf-8")))
    return keys


def check_translations():
    required = translation_keys()
    errors = 0

    for po_language, _, _ in LANGUAGES:
        path = PACKAGE / "po" / po_language / "haproxy-manager.po"
        try:
            catalog = parse_po(path)
        except (OSError, SyntaxError, ValueError) as exc:
            errors += fail(f"cannot read {path.relative_to(ROOT)}: {exc}")
            continue

        missing = sorted(required - set(catalog))
        if missing:
            errors += fail(f"{po_language} translation is missing: {', '.join(missing)}")

    return errors


def check_syntax():
    errors = 0
    node = shutil.which("node")
    shell = shutil.which("sh")

    for path in (ROOT / "scripts").glob("*.py"):
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except SyntaxError as exc:
            errors += fail(f"Python syntax error in {path.relative_to(ROOT)}: {exc}")

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


def check_workflow_contracts():
    errors = 0
    resources = PACKAGE / "htdocs" / "luci-static" / "resources"

    for path in resources.rglob("*.js"):
        source = path.read_text(encoding="utf-8")
        if "uci.apply(" in source:
            errors += fail(
                f"{path.relative_to(ROOT)} uses global rollback-protected uci.apply(); "
                "use the package-scoped saveAndApply workflow"
            )

    apply_source = (
        PACKAGE / "root" / "usr" / "libexec" / "haproxy-manager" / "apply"
    ).read_text(encoding="utf-8")
    for required in ("--backup", "restore_on_error", "haproxy-manager.apply"):
        if required not in apply_source:
            errors += fail(f"apply helper is missing transaction contract marker: {required}")

    rollback_source = (
        PACKAGE / "root" / "usr" / "libexec" / "haproxy-manager" / "rollback"
    ).read_text(encoding="utf-8")
    if "sleep 2" not in rollback_source or ") >/dev/null 2>&1 &" not in rollback_source:
        errors += fail("rollback must defer connection-affecting service restarts")

    acl = json.loads(
        (PACKAGE / "root/usr/share/rpcd/acl.d/luci-app-haproxy-manager.json").read_text(encoding="utf-8")
    )
    methods = acl["luci-app-haproxy-manager"]["write"]["ubus"].get("uci", [])
    if methods != ["commit"]:
        errors += fail("ACL must grant package-scoped UCI commit access")

    file_exec = acl["luci-app-haproxy-manager"]["write"]["file"]
    for helper in ("firewall-sync", "migrate", "ports"):
        path = f"/usr/libexec/haproxy-manager/{helper}"
        if path in file_exec:
            errors += fail(f"internal helper must not be directly executable through rpcd: {helper}")

    read_ubus = acl["luci-app-haproxy-manager"]["read"]["ubus"]
    if "service" in read_ubus:
        errors += fail("unused service/list rpcd permission must not be granted")

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

    for _, package_language, _ in LANGUAGES:
        if not list(DIST.glob(f"luci-i18n-haproxy-manager-{package_language}_*.ipk")):
            errors += fail(f"missing {package_language} translation ipk")

    return errors


def main():
    parser = argparse.ArgumentParser(description="Check LuCI HAProxy Manager sources and packages")
    parser.add_argument("--dist", action="store_true", help="also inspect built ipk artifacts")
    args = parser.parse_args()

    errors = check_translations() + check_syntax() + check_workflow_contracts()
    if args.dist:
        errors += check_package_contents()

    if errors:
        return 1

    print("All checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
