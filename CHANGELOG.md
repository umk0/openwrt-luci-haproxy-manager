# Changelog

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
