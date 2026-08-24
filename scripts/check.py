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

        for path in (PACKAGE / "root" / "etc" / "hotplug.d").rglob("*"):
            if not path.is_file():
                continue
            result = subprocess.run([shell, "-n", str(path)], capture_output=True, text=True)
            if result.returncode:
                errors += fail(f"shell syntax error in {path.relative_to(ROOT)}: {result.stderr.strip()}")

        result = subprocess.run([shell, "-n", str(ROOT / "scripts" / "build-openwrt-sdk.sh")], capture_output=True, text=True)
        if result.returncode:
            errors += fail(f"shell syntax error in scripts/build-openwrt-sdk.sh: {result.stderr.strip()}")

        for path in (ROOT / "tests").glob("*.sh"):
            result = subprocess.run([shell, "-n", str(path)], capture_output=True, text=True)
            if result.returncode:
                errors += fail(f"shell syntax error in {path.relative_to(ROOT)}: {result.stderr.strip()}")

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
    for required in (
        "--backup",
        "LOCK_BUSY_EXIT=75",
        "restore_on_error",
        "haproxy-manager.apply",
        "capture_uhttpd_bindings",
        "restore_uhttpd_bindings",
        "rollback --sync",
    ):
        if required not in apply_source:
            errors += fail(f"apply helper is missing transaction contract marker: {required}")

    rollback_source = (
        PACKAGE / "root" / "usr" / "libexec" / "haproxy-manager" / "rollback"
    ).read_text(encoding="utf-8")
    if "sleep 2" not in rollback_source or ") >/dev/null 2>&1 &" not in rollback_source:
        errors += fail("rollback must defer connection-affecting service restarts")
    if "while ! operation_lock_acquire \"$LOCK_DIR\"" not in rollback_source:
        errors += fail("rollback must serialize against apply operations")

    for helper in ("apply", "apply-raw-file", "recover", "rollback"):
        source = (PACKAGE / "root/usr/libexec/haproxy-manager" / helper).read_text(encoding="utf-8")
        if "atomic_install_file" not in source:
            errors += fail(f"configuration writer is not atomic: {helper}")

    ui_source = (resources / "haproxy-manager" / "ui.js").read_text(encoding="utf-8")
    if "error.code !== APPLY_LOCK_BUSY" not in ui_source:
        errors += fail("frontend must only restore UCI when apply did not acquire its lock")

    routes_source = (resources / "view" / "haproxy-manager" / "routes.js").read_text(encoding="utf-8")
    if "currentTarget.querySelector('.drag-over-above" in routes_source:
        errors += fail("drag-and-drop apply guard must inspect the target row itself")
    if "s.handleSort =" in routes_source:
        errors += fail("route sorting must use the upstream TableSection implementation")

    backup_source = (
        PACKAGE / "root" / "usr" / "libexec" / "haproxy-manager" / "backup"
    ).read_text(encoding="utf-8")
    if "attempt\" -lt" not in backup_source:
        errors += fail("recovery-point creation retries must be bounded")

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

    recover_source = (
        PACKAGE / "root" / "usr" / "libexec" / "haproxy-manager" / "recover"
    ).read_text(encoding="utf-8")
    for required in ("auto_recover", "haproxy-manager.apply", "haproxy restart", "INCIDENT_LIMIT"):
        if required not in recover_source:
            errors += fail(f"automatic recovery is missing contract marker: {required}")
    if 'create_incident "$REASON" || exit 1' in recover_source or "DIAGNOSTICS=/dev/null" not in recover_source:
        errors += fail("incident storage failures must not prevent automatic recovery")

    for helper in ("generate", "validate", "apply-raw-file"):
        source = (PACKAGE / "root/usr/libexec/haproxy-manager" / helper).read_text(encoding="utf-8")
        if "is_safe_temp_path" not in source:
            errors += fail(f"RPC-facing helper does not constrain temporary paths: {helper}")

    uninstall_source = (
        PACKAGE / "root/usr/libexec/haproxy-manager/uninstall"
    ).read_text(encoding="utf-8")
    for required in ("restore_uhttpd_bindings", "firewall-sync --disable", "active_mode"):
        if required not in uninstall_source:
            errors += fail(f"uninstall helper is missing ownership cleanup marker: {required}")

    makefile = (PACKAGE / "Makefile").read_text(encoding="utf-8")
    if "Package/luci-app-haproxy-manager/prerm" not in makefile or "PKG_UPGRADE" not in makefile:
        errors += fail("package removal must clean runtime state without doing so during upgrades")
    if 'Package runtime cleanup failed"\n\t\texit 1' in makefile:
        errors += fail("best-effort runtime cleanup must not block package removal")

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

        control_member = outer.extractfile("./control.tar.gz")
        if control_member is None:
            return errors + fail("ipk control.tar.gz cannot be read")
        with tarfile.open(fileobj=io.BytesIO(control_member.read()), mode="r:gz") as control_tar:
            control_names = set(control_tar.getnames())
            if "./prerm" not in control_names:
                errors += fail("portable ipk is missing the removal cleanup script")
            else:
                prerm_member = control_tar.extractfile("./prerm")
                prerm_source = prerm_member.read().decode("utf-8") if prerm_member else ""
                if 'Package runtime cleanup failed"\n        exit 1' in prerm_source:
                    errors += fail("portable ipk cleanup can block package removal")

            control_file = control_tar.extractfile("./control")
            control_source = control_file.read().decode("utf-8") if control_file else ""
            depends = next(
                (line for line in control_source.splitlines() if line.startswith("Depends:")),
                "",
            )
            if "uclient-fetch" in depends:
                errors += fail("portable ipk must not require the optional webhook client")

        with tarfile.open(fileobj=io.BytesIO(data_member.read()), mode="r:gz") as data_tar:
            payload = set(data_tar.getnames())
            executable_payload = {
                name for name in payload
                if name.startswith("./usr/libexec/haproxy-manager/")
                or name.startswith("./etc/hotplug.d/")
            }
            for name in executable_payload:
                try:
                    member = data_tar.getmember(name)
                    extracted = data_tar.extractfile(member)
                except KeyError:
                    continue
                if member.mode & 0o111 == 0:
                    errors += fail(f"package script is not executable: {name}")
                if extracted is not None and b"\r\n" in extracted.read():
                    errors += fail(f"package script contains CRLF line endings: {name}")

    required_payload = {
        "./usr/libexec/haproxy-manager/apply",
        "./usr/libexec/haproxy-manager/backups",
        "./usr/libexec/haproxy-manager/firewall-plan",
        "./usr/libexec/haproxy-manager/firewall-sync",
        "./usr/libexec/haproxy-manager/incident",
        "./usr/libexec/haproxy-manager/incidents",
        "./usr/libexec/haproxy-manager/migrate",
        "./usr/libexec/haproxy-manager/notify",
        "./usr/libexec/haproxy-manager/recover",
        "./usr/libexec/haproxy-manager/status",
        "./usr/libexec/haproxy-manager/uninstall",
        "./etc/hotplug.d/iface/95-haproxy-manager",
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
