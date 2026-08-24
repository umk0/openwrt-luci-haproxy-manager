# Operations Guide

## First run

1. Install the base package and at most one optional language package.
2. Open `Services -> HAProxy -> Settings`.
3. Select the logical WAN interface that receives public connections.
4. Enable managed configuration. Enable firewall automation if OpenWrt should
   open the listener ports itself.
5. Enable LAN-only LuCI binding when HAProxy must own public ports 80 or 443.
6. Add services, then use **Check configuration** before the first apply.

The package creates a recovery point before every apply. It only modifies its
own firewall rule and redirects explicitly marked as temporarily disabled by
HAProxy Manager.

## Configuration modes

Generated mode is selected after applying Services or Settings. WAN hotplug
events may regenerate this configuration when an automatically detected address
changes.

Raw mode is selected after applying the expert editor. Automatic recovery may
restart a stopped raw configuration, but never regenerates or overwrites it.
Applying Services or Settings again explicitly returns to generated mode.

## Dynamic WAN and multi-WAN

With `WAN bind address` set to Automatic, the package reads the first IPv4
address from the selected logical interface. On `ifup` and `ifupdate`, it
generates and validates a candidate configuration. A changed candidate is
installed transactionally; a failed restart restores the previous snapshot.

One logical ingress interface is managed at a time. In a multi-WAN setup,
select the interface that receives the published connections. Use a fixed bind
address when policy routing exposes one stable address. Multiple simultaneous
public listener addresses require Raw Config, because automatically choosing
across several uplinks would be ambiguous and could expose services on an
unintended WAN.

## Firewall conflicts

`Stop and show conflicts` leaves existing redirects untouched and rejects the
apply. `Disable conflicting forwards during apply` disables only conflicting
TCP redirects and prefixes their names with the package ownership marker. They
are restored when the ports are no longer needed, managed mode is disabled, or
the package is removed.

UDP is not handled by HAProxy. Keep UDP redirects in OpenWrt Firewall.

## Recovery and incidents

The Status page lists the seven latest recovery points and automatic recovery
incidents. Service and configuration failures contain bounded local diagnostics;
routine WAN-address reconciliation stores a lightweight metadata record. Reports
and recovery points default to:

```text
/root/haproxy-manager-incidents
/root/haproxy-manager-backups
```

Optional webhooks contain only the incident ID, result, action, interface, and
reason. They do not include IP addresses, HAProxy configuration, or logs. Use an
HTTPS endpoint whenever it is reachable from the router. Webhook delivery uses
an installed `uclient-fetch` or compatible `wget` implementation.

Router-side recovery is not external availability monitoring. Monitor a public
health endpoint from another network and alert when it fails.

## Upgrade

Install the new package over the existing one. The package manager preserves
`/etc/config/haproxy_manager`; the post-install migration is idempotent and
creates a recovery point before schema changes that affect routes.

OpenWrt 24.10:

```sh
opkg install /tmp/luci-app-haproxy-manager_*.ipk
```

OpenWrt 25.12:

```sh
apk add --allow-untrusted /tmp/luci-app-haproxy-manager-*.apk
```

`--allow-untrusted` is needed only for unsigned standalone release files. It is
not used after the package is available from an official or otherwise trusted
signed feed.

## Removal

Remove an installed language package before or together with the base package.
During a real removal, the pre-removal hook:

- creates a final recovery point when storage is available;
- restores the uHTTPd listeners captured before HAProxy Manager took ownership;
- restores redirects disabled by the package and removes its WAN firewall rule;
- stops and disables HAProxy when either generated or raw mode was active.

The active `/etc/haproxy.cfg`, recovery points, and incident reports are
retained deliberately. A retained raw configuration is not left running, so it
cannot conflict with the restored LuCI listeners after the manager is removed.

OpenWrt 24.10:

```sh
opkg remove luci-i18n-haproxy-manager-ru luci-app-haproxy-manager
```

OpenWrt 25.12:

```sh
apk del luci-i18n-haproxy-manager-ru luci-app-haproxy-manager
```

## Emergency recovery

Restore the latest snapshot over SSH:

```sh
/usr/libexec/haproxy-manager/rollback last
```

Inspect service and listener state:

```sh
/etc/init.d/haproxy check
/etc/init.d/haproxy status
netstat -lntp | grep -E ':(80|443)[[:space:]]'
logread | grep -i haproxy
```

To stop generated publishing without removing the package, disable managed
configuration in Settings and save. The same transaction restores owned LuCI
and firewall state.
