# Contributing

Issues and pull requests are welcome. Keep changes focused and explain any
effect on HAProxy, firewall, uHTTPd, or existing UCI configuration.

Keep changes compatible with the modern JavaScript LuCI framework and BusyBox
`ash`. Do not broaden rpcd ACLs when a package-scoped helper can perform the
operation.

Before opening a pull request, run:

```sh
python3 scripts/check.py
python3 scripts/build-ipk.py
python3 scripts/check.py --dist
```

GitHub Actions additionally builds the package with current OpenWrt 24.10 and
25.12 SDKs for x86_64, ARM64, and MIPS, then runs runtime lifecycle and failure
injection tests in matching OpenWrt root filesystems.

Changes to routing, apply/rollback, or package lifecycle behavior should also be
tested on an OpenWrt router before release.

All user-facing strings must use `_()` and be present in every maintained PO
catalog. The base package remains English-only; translations are built as
separate LuCI language packages.

Commits submitted to `openwrt/luci` must follow its component-prefixed subject,
line length, and real-name `Signed-off-by` requirements. Once accepted upstream,
translations are maintained through OpenWrt Weblate.
