#!/usr/bin/env python3
import gzip
import io
import os
import pathlib
import re
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PKG = ROOT / "luci-app-haproxy-manager"
DIST = ROOT / "dist"
NAME = "luci-app-haproxy-manager"
ARCH = "all"

LANG_PACKAGES = (
    ("ru", "Russian"),
    ("es", "Spanish"),
    ("ko", "Korean"),
    ("ja", "Japanese"),
    ("zh-cn", "Simplified Chinese"),
)


def package_version():
    makefile = (PKG / "Makefile").read_text(encoding="utf-8")
    version_match = re.search(r"^PKG_VERSION:=(.+)$", makefile, re.MULTILINE)
    release_match = re.search(r"^PKG_RELEASE:=(.+)$", makefile, re.MULTILINE)

    if not version_match or not release_match:
        raise RuntimeError("PKG_VERSION or PKG_RELEASE is missing from the package Makefile")

    return f"{version_match.group(1).strip()}-{release_match.group(1).strip()}"


VERSION = package_version()


def tar_bytes(entries):
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.GNU_FORMAT) as tar:
            for entry in entries:
                if len(entry) == 5:
                    arcname, path, mode, data, kind = entry
                else:
                    arcname, path, mode, data = entry
                    kind = "file"

                if kind == "dir":
                    info = tarfile.TarInfo(arcname.rstrip("/") + "/")
                    info.type = tarfile.DIRTYPE
                    info.mode = mode
                    info.mtime = 0
                    info.uid = 0
                    info.gid = 0
                    info.uname = "root"
                    info.gname = "root"
                    tar.addfile(info)
                    continue

                if data is None:
                    st = path.stat()
                    payload = path.read_bytes()
                    size = len(payload)
                else:
                    payload = data
                    size = len(payload)

                info = tarfile.TarInfo(arcname)
                info.size = size
                info.mode = mode
                info.mtime = 0
                info.uid = 0
                info.gid = 0
                info.uname = "root"
                info.gname = "root"
                tar.addfile(info, io.BytesIO(payload))
    return buf.getvalue()


def walk_payload(roots):
    dirs = set(["."])
    files = []

    for base, prefix in roots:
        if not base.exists():
            continue

        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue

            rel = path.relative_to(base).as_posix()
            arcname = f"{prefix}/{rel}" if prefix != "." else f"./{rel}"
            parts = arcname.strip("./").split("/")
            for i in range(1, len(parts)):
                dirs.add("./" + "/".join(parts[:i]))

            mode = 0o644
            if "/usr/libexec/haproxy-manager/" in arcname:
                mode = 0o755
            files.append((arcname, path, mode, None))

    for dirname in sorted(dirs, key=lambda d: (d.count("/"), d)):
        yield (dirname, pathlib.Path(), 0o755, b"", "dir")

    yield from files


def control_file(name, depends, description):
    return f"""Package: {name}
Version: {VERSION}
Architecture: {ARCH}
Maintainer: HAProxy Manager contributors
Section: luci
Priority: optional
Depends: {depends}
Description: {description}
"""


def build_package(name, depends, description, roots, conffiles=None, postinst=None, postrm=None):
    control_entries = [
        ("./control", pathlib.Path(), 0o644, control_file(name, depends, description).encode()),
    ]

    if conffiles:
        control_entries.append(("./conffiles", pathlib.Path(), 0o644, conffiles.encode()))

    if postinst:
        control_entries.append(("./postinst", pathlib.Path(), 0o755, postinst.encode()))

    if postrm:
        control_entries.append(("./postrm", pathlib.Path(), 0o755, postrm.encode()))

    control_tar = tar_bytes(control_entries)
    data_tar = tar_bytes(list(walk_payload(roots)))

    out = DIST / f"{name}_{VERSION}_{ARCH}.ipk"
    package = tar_bytes([
        ("./debian-binary", pathlib.Path(), 0o644, b"2.0\n"),
        ("./data.tar.gz", pathlib.Path(), 0o644, data_tar),
        ("./control.tar.gz", pathlib.Path(), 0o644, control_tar),
    ])
    out.write_bytes(package)
    print(out)


def main():
    DIST.mkdir(parents=True, exist_ok=True)

    for old in DIST.glob("luci-app-haproxy-manager_*.ipk"):
        old.unlink()
    for old in DIST.glob("luci-i18n-haproxy-manager-*.ipk"):
        old.unlink()

    subprocess.run([sys.executable, str(PKG / "build-lmo.py"), str(PKG)], check=True)

    postinst = """#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
chmod +x /usr/libexec/haproxy-manager/* 2>/dev/null || true
/usr/libexec/haproxy-manager/migrate >/dev/null 2>&1 || logger -t haproxy-manager "Configuration migration failed"
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
"""
    postrm = """#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
"""
    i18n_post = """#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
exit 0
"""
    build_package(
        NAME,
        "luci-base, rpcd, rpcd-mod-file, haproxy",
        "LuCI application for managing HAProxy domain routes, raw config, backups, and rollback.",
        ((PKG / "root", "."), (PKG / "htdocs", "./www")),
        conffiles="/etc/config/haproxy_manager\n",
        postinst=postinst,
        postrm=postrm,
    )

    for lang, title in LANG_PACKAGES:
        build_package(
            f"luci-i18n-haproxy-manager-{lang}",
            "luci-app-haproxy-manager",
            f"{title} translation package for luci-app-haproxy-manager.",
            ((PKG / "i18n" / lang, "."),),
            postinst=i18n_post,
            postrm=i18n_post,
        )


if __name__ == "__main__":
    main()
