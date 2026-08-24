#!/bin/sh
set -eu

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "expected '$2', got '$1': $3"
}

assert_contains() {
	case "$1" in
		*"$2"*) ;;
		*) fail "missing '$2': $3" ;;
	esac
}

HELPERS=/usr/libexec/haproxy-manager
MOCK_BIN=/tmp/haproxy-manager-test-bin
mkdir -p "$MOCK_BIN" /var/lock

cat > "$MOCK_BIN/ubus" <<'EOF'
#!/bin/sh
case "$*" in
	*network.interface.wan*status*)
		printf '{"ipv4-address":[{"address":"%s"}]}\n' "$(cat /tmp/haproxy-manager-test-wan)"
	;;
	*network.interface.lan*status*)
		printf '{"ipv4-address":[{"address":"192.168.1.1"}]}\n'
	;;
	*) printf '{}\n' ;;
esac
EOF
chmod 755 "$MOCK_BIN/ubus"
export PATH="$MOCK_BIN:$PATH"

printf 'original\n' > /tmp/haproxy-manager-atomic-target
printf 'replacement\n' > /tmp/haproxy-manager-atomic-source
cat > "$MOCK_BIN/cp" <<'EOF'
#!/bin/sh
case "${2:-}" in
	*.haproxy-manager.*)
		printf 'partial\n' > "$2"
		exit 1
	;;
esac
exec /bin/cp "$@"
EOF
chmod 755 "$MOCK_BIN/cp"
if (
	. "$HELPERS/common.sh"
	atomic_install_file /tmp/haproxy-manager-atomic-source /tmp/haproxy-manager-atomic-target
); then
	fail "atomic install unexpectedly succeeded during a forced copy failure"
fi
assert_eq "$(cat /tmp/haproxy-manager-atomic-target)" original "atomic write preserved destination"
rm -f "$MOCK_BIN/cp"

for service in haproxy uhttpd firewall; do
	[ ! -e "/etc/init.d/$service" ] || mv "/etc/init.d/$service" "/etc/init.d/$service.real"
done

cat > /etc/init.d/haproxy <<'EOF'
#!/bin/sh
case "${1:-}" in
	enabled) [ -f /tmp/haproxy-manager-test-enabled ] ;;
	enable) touch /tmp/haproxy-manager-test-enabled ;;
	disable) rm -f /tmp/haproxy-manager-test-enabled ;;
	status) [ -f /tmp/haproxy-manager-test-running ] ;;
	stop) rm -f /tmp/haproxy-manager-test-running ;;
	check) haproxy -c -f /etc/haproxy.cfg >/dev/null ;;
	restart|start)
		[ ! -f /tmp/haproxy-manager-test-restart-fail ] || {
			rm -f /tmp/haproxy-manager-test-running
			exit 1
		}
		haproxy -c -f /etc/haproxy.cfg >/dev/null
		touch /tmp/haproxy-manager-test-running
	;;
	*) exit 0 ;;
esac
EOF

cat > /etc/init.d/uhttpd <<'EOF'
#!/bin/sh
exit 0
EOF

cat > /etc/init.d/firewall <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 /etc/init.d/haproxy /etc/init.d/uhttpd /etc/init.d/firewall

touch /etc/config/firewall
uci -q delete uhttpd.main || true
uci set uhttpd.main=uhttpd
uci add_list uhttpd.main.listen_http='0.0.0.0:80'
uci add_list uhttpd.main.listen_http='[::]:80'
uci add_list uhttpd.main.listen_https='0.0.0.0:443'
uci add_list uhttpd.main.listen_https='[::]:443'
uci commit uhttpd

zone="$(uci add firewall zone)"
uci set "firewall.$zone.name=wan"
uci set "firewall.$zone.input=REJECT"
redirect="$(uci add firewall redirect)"
uci set "firewall.$redirect.name=Existing HTTP"
uci set "firewall.$redirect.src=wan"
uci set "firewall.$redirect.proto=tcp"
uci set "firewall.$redirect.src_dport=80"
uci set "firewall.$redirect.dest_ip=192.168.1.20"
uci set "firewall.$redirect.dest_port=80"
uci set "firewall.$redirect.enabled=1"
uci commit firewall

while uci -q delete 'haproxy_manager.@route[0]'; do :; done
route="$(uci add haproxy_manager route)"
uci set "haproxy_manager.$route.enabled=1"
uci set "haproxy_manager.$route.name=Example Web"
uci set "haproxy_manager.$route.kind=web"
uci set "haproxy_manager.$route.host=example.org"
uci set "haproxy_manager.$route.backend_host=192.168.1.10"
uci set "haproxy_manager.$route.web_http=1"
uci set "haproxy_manager.$route.web_https=1"
uci set "haproxy_manager.$route.backend_http_port=80"
uci set "haproxy_manager.$route.backend_https_port=443"
tcp_route="$(uci add haproxy_manager route)"
uci set "haproxy_manager.$tcp_route.enabled=1"
uci set "haproxy_manager.$tcp_route.name=Example TCP"
uci set "haproxy_manager.$tcp_route.kind=custom"
uci set "haproxy_manager.$tcp_route.backend_host=192.168.1.11"
uci add_list "haproxy_manager.$tcp_route.port_map=2222:22"
uci add_list "haproxy_manager.$tcp_route.port_map=3390:3389"
uci set haproxy_manager.main.enabled=1
uci set haproxy_manager.main.wan_interface=wan
uci set haproxy_manager.main.wan_bind_ip=auto
uci set haproxy_manager.main.manage_uhttpd_bind=1
uci set haproxy_manager.main.lan_bind_ip=192.168.1.1
uci set haproxy_manager.main.manage_firewall=1
uci set haproxy_manager.main.firewall_zone=wan
uci set haproxy_manager.main.firewall_conflict_mode=disable
uci set haproxy_manager.main.auto_recover=1
uci set haproxy_manager.main.webhook_enabled=0
uci commit haproxy_manager

mkdir -p /tmp/haproxy-manager-web-root
printf 'host-port-route-ok\n' > /tmp/haproxy-manager-web-root/index.html
uci set "haproxy_manager.$route.web_https=0"
uci set "haproxy_manager.$route.backend_host=127.0.0.1"
uci set "haproxy_manager.$route.backend_http_port=18081"
uci set haproxy_manager.main.http_port=18080
uci set haproxy_manager.main.wan_bind_ip=127.0.0.1
uci commit haproxy_manager
$HELPERS/generate /tmp/haproxy-manager-host-port.cfg >/dev/null
$HELPERS/validate /tmp/haproxy-manager-host-port.cfg >/dev/null
uhttpd -f -h /tmp/haproxy-manager-web-root -p 127.0.0.1:18081 >/tmp/haproxy-manager-uhttpd.log 2>&1 &
probe_uhttpd_pid=$!
haproxy -db -f /tmp/haproxy-manager-host-port.cfg >/tmp/haproxy-manager-haproxy.log 2>&1 &
probe_haproxy_pid=$!
sleep 2
if ! kill -0 "$probe_haproxy_pid" 2>/dev/null || ! kill -0 "$probe_uhttpd_pid" 2>/dev/null; then
	cat /tmp/haproxy-manager-haproxy.log /tmp/haproxy-manager-uhttpd.log >&2 || true
	fail "HTTP Host route probe services did not start"
fi
if ! probe_response="$(printf 'GET / HTTP/1.1\r\nHost: example.org:18080\r\nConnection: close\r\n\r\n' | nc 127.0.0.1 18080)"; then
	kill "$probe_haproxy_pid" "$probe_uhttpd_pid" 2>/dev/null || true
	fail "HTTP Host route on a non-standard public port failed"
fi
kill "$probe_haproxy_pid" "$probe_uhttpd_pid" 2>/dev/null || true
wait "$probe_haproxy_pid" "$probe_uhttpd_pid" 2>/dev/null || true
assert_contains "$probe_response" host-port-route-ok "HTTP Host header with a public port"
rm -f /tmp/haproxy-manager-host-port.cfg
uci set "haproxy_manager.$route.web_https=1"
uci set "haproxy_manager.$route.backend_host=192.168.1.10"
uci set "haproxy_manager.$route.backend_http_port=80"
uci set haproxy_manager.main.http_port=80
uci set haproxy_manager.main.wan_bind_ip=auto
uci commit haproxy_manager

echo 198.51.100.10 > /tmp/haproxy-manager-test-wan
printf 'do-not-touch\n' > /tmp/haproxy-manager-symlink-target
ln -s /tmp/haproxy-manager-symlink-target /tmp/haproxy-manager-generated-symlink.cfg
$HELPERS/generate /tmp/haproxy-manager-generated-symlink.cfg >/dev/null
assert_eq "$(cat /tmp/haproxy-manager-symlink-target)" do-not-touch "generated config symlink target"
[ ! -L /tmp/haproxy-manager-generated-symlink.cfg ] || fail "generated config output remained a symlink"
rm -f /tmp/haproxy-manager-generated-symlink.cfg /tmp/haproxy-manager-symlink-target
uci add_list "haproxy_manager.$tcp_route.port_map=80:8080"
uci commit haproxy_manager
if $HELPERS/generate /tmp/haproxy-manager-conflicting.cfg >/dev/null 2>&1; then
	fail "generator accepted duplicate Web and custom TCP listener ports"
fi
uci -q delete "haproxy_manager.$tcp_route.port_map"
uci add_list "haproxy_manager.$tcp_route.port_map=2222:22"
uci add_list "haproxy_manager.$tcp_route.port_map=3390:3389"
uci commit haproxy_manager
mkdir /var/lock/haproxy-manager.apply
backup_id="$(basename "$($HELPERS/backup)")"
echo "$$" > /var/lock/haproxy-manager.apply/pid
set +e
$HELPERS/apply --backup "$backup_id" >/dev/null 2>&1
lock_status=$?
set -e
assert_eq "$lock_status" 75 "apply lock contention exit code"
[ -d /var/lock/haproxy-manager.apply ] || fail "live operation lock was removed"
rm -f /var/lock/haproxy-manager.apply/pid
rmdir /var/lock/haproxy-manager.apply
mkdir /var/lock/haproxy-manager.apply
echo 999999 > /var/lock/haproxy-manager.apply/pid
$HELPERS/apply --backup "$backup_id" >/dev/null
sleep 3
assert_eq "$(uci -q get haproxy_manager.main.active_mode)" generated "generated apply mode"
assert_contains "$(cat /etc/haproxy.cfg)" '198.51.100.10:80' "initial WAN listener"
assert_contains "$(cat /etc/haproxy.cfg)" '198.51.100.10:2222' "custom SSH-like TCP listener"
assert_contains "$(cat /etc/haproxy.cfg)" '192.168.1.11:3389' "custom TCP destination mapping"
assert_eq "$(uci -q get uhttpd.main.listen_http)" '192.168.1.1:80' "LuCI HTTP bind ownership"
assert_eq "$(uci -q get "firewall.$redirect.enabled")" 0 "conflicting redirect disabled"
assert_contains "$(uci -q get "firewall.$redirect.name")" 'HAProxy Manager disabled: ' "redirect ownership marker"

package_hash="$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')"
echo 198.51.100.99 > /tmp/haproxy-manager-test-wan
$HELPERS/recover package install
assert_eq "$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')" "$package_hash" "package recovery rewrote a healthy config"
echo 198.51.100.10 > /tmp/haproxy-manager-test-wan

cat > /tmp/haproxy-manager-raw-test.cfg <<'EOF'
global
  daemon
defaults
  mode tcp
  timeout connect 5s
  timeout client 30s
  timeout server 30s
frontend test
  bind 127.0.0.1:18080
  default_backend test_backend
backend test_backend
  server test 127.0.0.1:18081
EOF
$HELPERS/apply-raw-file /tmp/haproxy-manager-raw-test.cfg >/dev/null
assert_eq "$(uci -q get haproxy_manager.main.active_mode)" raw "raw apply mode"
raw_hash="$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')"
echo 198.51.100.11 > /tmp/haproxy-manager-test-wan
$HELPERS/recover ifupdate wan
assert_eq "$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')" "$raw_hash" "raw config changed during WAN event"

backup_id="$(basename "$($HELPERS/backup)")"
$HELPERS/apply --backup "$backup_id" >/dev/null
assert_eq "$(uci -q get haproxy_manager.main.active_mode)" generated "return to generated mode"
assert_contains "$(cat /etc/haproxy.cfg)" '198.51.100.11:80' "generated WAN listener"

echo 198.51.100.12 > /tmp/haproxy-manager-test-wan
$HELPERS/recover ifupdate wan
assert_contains "$(cat /etc/haproxy.cfg)" '198.51.100.12:80' "reconciled WAN listener"
assert_contains "$($HELPERS/incidents)" "reconciled" "successful WAN incident"
latest_incident="$(cat /root/haproxy-manager-incidents/LAST)"
if grep -q 'Kernel OOM messages' "/root/haproxy-manager-incidents/$latest_incident/diagnostics.log"; then
	fail "routine WAN reconciliation wrote full incident diagnostics"
fi

before_failure="$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')"
echo 198.51.100.13 > /tmp/haproxy-manager-test-wan
touch /tmp/haproxy-manager-test-restart-fail
if $HELPERS/recover ifupdate wan; then
	fail "WAN reconciliation unexpectedly succeeded during forced restart failure"
fi
assert_eq "$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')" "$before_failure" "failed WAN reconciliation rollback"
assert_contains "$($HELPERS/incidents)" "rollback-failed" "failed WAN incident result"
rm -f /tmp/haproxy-manager-test-restart-fail
echo 198.51.100.12 > /tmp/haproxy-manager-test-wan
$HELPERS/recover network test
assert_contains "$($HELPERS/incidents)" "recovered" "stopped service recovery"
latest_incident="$(cat /root/haproxy-manager-incidents/LAST)"
assert_contains "$(cat "/root/haproxy-manager-incidents/$latest_incident/diagnostics.log")" \
	"Kernel OOM messages" "stopped service full diagnostics"

rm -f /tmp/haproxy-manager-test-running
uci set haproxy_manager.main.incident_dir=/etc/haproxy-manager-incidents
uci commit haproxy_manager
$HELPERS/recover network unsafe-incident-storage
[ -f /tmp/haproxy-manager-test-running ] || fail "incident storage failure prevented service recovery"
uci set haproxy_manager.main.incident_dir=/root/haproxy-manager-incidents
uci commit haproxy_manager

echo 198.51.100.14 > /tmp/haproxy-manager-test-wan
cat > "$MOCK_BIN/haproxy" <<'EOF'
#!/bin/sh
case "$*" in
	*haproxy-manager-recover*) exit 1 ;;
esac
exec /usr/sbin/haproxy "$@"
EOF
chmod 755 "$MOCK_BIN/haproxy"
before_invalid="$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')"
if $HELPERS/recover ifupdate wan; then
	fail "WAN reconciliation accepted an invalid generated configuration"
fi
assert_eq "$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')" "$before_invalid" "invalid candidate preserved active config"
assert_contains "$($HELPERS/incidents)" "invalid-generated-config" "invalid generated incident result"
rm -f "$MOCK_BIN/haproxy"

: > /tmp/haproxy-manager-test-wan
if $HELPERS/recover ifupdate wan; then
	fail "WAN reconciliation succeeded without an address"
fi
assert_eq "$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')" "$before_invalid" "missing WAN address preserved active config"
assert_contains "$($HELPERS/incidents)" "address-unavailable" "missing WAN address incident result"
echo 198.51.100.13 > /tmp/haproxy-manager-test-wan
$HELPERS/recover ifupdate wan

uci set haproxy_manager.main.webhook_enabled=1
uci set haproxy_manager.main.webhook_url=http://
uci commit haproxy_manager
if $HELPERS/notify 20260101-000000 failed network wan test >/dev/null 2>&1; then
	fail "webhook accepted a URL without a host"
fi
uci set haproxy_manager.main.webhook_enabled=0
uci commit haproxy_manager

if $HELPERS/generate /etc/haproxy-manager-test.cfg >/dev/null 2>&1; then
	fail "generate accepted an unsafe output path"
fi
if $HELPERS/validate /etc/passwd >/dev/null 2>&1; then
	fail "validate accepted an unsafe input path"
fi
uci set haproxy_manager.main.backup_dir=/etc/haproxy-manager-backups
uci commit haproxy_manager
if backup_error="$($HELPERS/backup 2>&1)"; then
	fail "backup accepted an unsafe storage path"
fi
assert_contains "$backup_error" "must be a plain path under /root or /mnt" "unsafe storage path error"
rm -f /root/haproxy-manager-storage-link
ln -s /etc /root/haproxy-manager-storage-link
uci set haproxy_manager.main.backup_dir=/root/haproxy-manager-storage-link
uci commit haproxy_manager
if $HELPERS/backup >/dev/null 2>&1; then
	fail "backup followed a storage symlink outside the allowed roots"
fi
rm -f /root/haproxy-manager-storage-link
uci set haproxy_manager.main.backup_dir=/root/haproxy-manager-backups
uci commit haproxy_manager

for unused in 1 2 3 4 5 6 7 8; do
	$HELPERS/backup >/dev/null
done
assert_eq "$($HELPERS/backups | wc -l | tr -d ' ')" 7 "recovery-point retention"
latest_backup="$(basename "$(sed -n '1p' /root/haproxy-manager-backups/LAST)")"
assert_eq "$(ls -ld "/root/haproxy-manager-backups/$latest_backup" | cut -c1-10)" drwx------ "recovery-point directory permissions"

cat > /tmp/haproxy-manager-raw-test.cfg <<'EOF'
global
  daemon
defaults
  mode tcp
  timeout connect 5s
  timeout client 30s
  timeout server 30s
frontend test
  bind 127.0.0.1:18080
  default_backend test_backend
backend test_backend
  server test 127.0.0.1:18081
EOF
raw_hash="$(sha256sum /tmp/haproxy-manager-raw-test.cfg | awk '{ print $1 }')"
$HELPERS/apply-raw-file /tmp/haproxy-manager-raw-test.cfg >/dev/null
[ ! -e /tmp/haproxy-manager-raw-test.cfg ] || fail "raw apply left its input file in temporary storage"
$HELPERS/uninstall
assert_eq "$(sha256sum /etc/haproxy.cfg | awk '{ print $1 }')" "$raw_hash" "raw config retained after removal cleanup"
assert_contains "$(uci -q get uhttpd.main.listen_http)" '0.0.0.0:80' "original LuCI IPv4 HTTP bind"
assert_contains "$(uci -q get uhttpd.main.listen_http)" '[::]:80' "original LuCI IPv6 HTTP bind"
assert_eq "$(uci -q get "firewall.$redirect.enabled")" 1 "redirect restored on removal"
assert_eq "$(uci -q get "firewall.$redirect.name")" 'Existing HTTP' "redirect name restored on removal"
assert_eq "$(uci -q get haproxy_manager.main.active_mode)" none "mode after removal"
if /etc/init.d/haproxy enabled >/dev/null 2>&1 || /etc/init.d/haproxy status >/dev/null 2>&1; then
	fail "HAProxy service remained enabled after raw removal cleanup"
fi

echo "OpenWrt runtime tests passed."
