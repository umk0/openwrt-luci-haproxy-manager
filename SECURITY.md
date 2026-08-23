# Security Policy

## Supported versions

Security fixes are made for the latest release. The CI matrix tracks maintained
OpenWrt 24.10 and 25.12 patch releases.

## Trust model

LuCI administrators already control the router. The application still limits
its rpcd ACL to the `haproxy_manager` UCI package, named helper executables, the
HAProxy configuration, and package-owned temporary files. Server-side helpers
validate paths and identifiers independently of browser-side validation.

Generated and raw applies validate HAProxy syntax, create a snapshot, serialize
mutations, and restore the snapshot after a failed apply. Firewall and uHTTPd
changes use explicit ownership markers so unrelated state is not removed.

Standalone GitHub release files are unsigned development artifacts and require
the package manager's explicit untrusted-package option. Official OpenWrt feed
inclusion is the intended trusted distribution path.

Webhook notifications are disabled by default. Their bounded payload excludes
configuration, IP addresses, and diagnostics. The configured URL may contain a
secret and is stored in the root-readable UCI configuration.

## Reporting a vulnerability

Use GitHub private vulnerability reporting when it is available for this
repository. Otherwise send the report to `job@umk0.ru` with affected versions,
reproduction steps, and expected impact. Do not include router passwords,
private keys, public IP addresses, domain names, or configuration backups in a
public issue. Acknowledgement is targeted within seven days.
