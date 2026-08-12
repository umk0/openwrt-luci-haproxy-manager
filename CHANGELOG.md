# Changelog

## 0.5.1 - 2026-08-12

- Commit LuCI form changes before running HAProxy helper scripts.
- Treat non-zero helper exit codes as errors throughout the interface.
- Reload uHTTPd only when its bind addresses change and preserve the RPC response.
- Replace custom firewall marker options with supported rule-name prefixes.
- Tighten rpcd permissions, input validation, backup creation, and cache cleanup.

## 0.5.0 - 2026-08-11

- Adopt the native OpenWrt LuCI `luci.mk` packaging layout.
- Replace the custom browser-side JSON translator with standard LuCI `_()`
  translations and PO catalogs compatible with Weblate.
- Build standalone language packages from the same PO sources used upstream.

## 0.4.1 - 2026-08-11

- Mark the base package as architecture-independent in the OpenWrt package
  definition, producing one `all` IPK for every supported processor.
- Update GitHub artifact handling to its current Node.js 24 runtime.

## 0.4.0 - 2026-08-11

- Keep only the seven newest recovery points and prune older snapshots automatically.
- Build current OpenWrt 24.10 and 25.12 packages on x86_64, ARM64, and MIPS,
  with tagged GitHub Releases, language bundles, and checksums.
- Replace protocol records with service presets for Web, SSH, Remote Desktop,
  and custom TCP mappings.
- Combine HTTP and HTTPS into one Web service with separate backend ports.
- Migrate compatible legacy HTTP/HTTPS pairs without changing routing behavior.
- Add optional firewall rule synchronization and conflict detection.
- Replace backup paths with named recovery points and one-click restore.
- Clarify shared Web listeners versus per-service TCP listeners.
- Restyle the service filter and compact service table across LuCI themes.

## 0.3.0 - 2026-08-11

- Make routes the primary screen and move listener settings to a separate page.
- Replace the wide route table with compact endpoint and destination columns.
- Add route filtering and protocol-aware modal fields.
- Replace raw status output with a service summary and listener table.
- Show every HAProxy and uHTTPd TCP listener, including custom TCP routes.
- Add confirmation dialogs for rollback and raw configuration apply.
- Add theme-neutral responsive styles and repository checks.
- Reject duplicate HAProxy listener ports before generating a configuration.

## 0.2.0 - 2026-07-09

- Add HTTP Host, HTTPS SNI passthrough, combined HTTP/HTTPS, and plain TCP routes.
- Add separate Russian, Spanish, Korean, Japanese, and Simplified Chinese packages.
- Add OpenWrt `ipk` and `apk` build helpers.
