#!/bin/sh

CONFIG=haproxy_manager
HAPROXY_CFG=/etc/haproxy.cfg
TMP_CFG=/tmp/haproxy-manager.cfg

uci_get() {
	local section="$1"
	local option="$2"
	local default="${3:-}"
	uci -q get "$CONFIG.$section.$option" 2>/dev/null || printf '%s\n' "$default"
}

backup_dir() {
	uci_get main backup_dir /root/haproxy-manager-backups
}

wan_ip() {
	local configured
	configured="$(uci_get main wan_bind_ip auto)"
	if [ "$configured" != auto ] && [ -n "$configured" ]; then
		printf '%s\n' "$configured"
		return 0
	fi

	ubus call network.interface.wan status 2>/dev/null \
		| jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null \
		| grep -m1 .
}

lan_ip() {
	local configured
	configured="$(uci_get main lan_bind_ip auto)"
	if [ "$configured" != auto ] && [ -n "$configured" ]; then
		printf '%s\n' "$configured"
		return 0
	fi

	ubus call network.interface.lan status 2>/dev/null \
		| jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null \
		| grep -m1 .
}

route_name() {
	printf '%s' "$1" | tr '.:-' '___' | tr -cd 'A-Za-z0-9_'
}

is_valid_host() {
	printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$'
}

is_valid_ip_or_host() {
	printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_.:-]+$'
}

is_valid_port() {
	local port="$1"
	[ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null
}
