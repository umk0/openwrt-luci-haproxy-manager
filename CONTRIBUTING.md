# Contributing

Issues and pull requests are welcome. Keep changes focused and explain any
effect on HAProxy, firewall, uHTTPd, or existing UCI configuration.

## Checks

Run the source and package checks before submitting a pull request:

```sh
python3 scripts/check.py
python3 scripts/build-ipk.py
python3 scripts/check.py --dist
```

Changes to routing or apply/rollback behavior should also be tested on an
OpenWrt router or in an OpenWrt SDK environment.

## Translations

English strings belong in the LuCI JavaScript views. Optional translations live
in `luci-app-haproxy-manager/i18n/<language>/` and are distributed as separate
packages. Every language catalog must contain all keys reported by
`scripts/check.py`.

## OpenWrt upstream

An eventual contribution to `openwrt/luci` will use its native `luci.mk` and PO
translation layout. Upstream commits must follow the OpenWrt contribution rules,
including a package-prefixed subject and a real-name `Signed-off-by` line.
