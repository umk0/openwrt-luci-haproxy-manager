#!/bin/sh

CONFIG=haproxy_manager
HAPROXY_CFG=/etc/haproxy.cfg
TMP_CFG=/tmp/haproxy-manager.cfg
BACKUP_LIMIT=7
FIREWALL_RULE_NAME='HAProxy Manager: WAN listeners'
FIREWALL_DISABLED_PREFIX='HAProxy Manager disabled: '

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
	case "$1" in
		''|[!A-Za-z0-9]*|*[!A-Za-z0-9]) return 1 ;;
		*[!A-Za-z0-9.-]*) return 1 ;;
	esac
	return 0
}

is_valid_ip_or_host() {
	case "$1" in
		''|*[!A-Za-z0-9_.:-]*) return 1 ;;
	esac
	return 0
}

is_valid_backup_id() {
	case "$1" in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;;
		*) return 1 ;;
	esac
}

backend_address() {
	local host="$1"
	local port="$2"

	case "$host" in
		*:*) printf '[%s]:%s\n' "$host" "$port" ;;
		*) printf '%s:%s\n' "$host" "$port" ;;
	esac
}

is_valid_port() {
	local port="$1"
	[ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null
}

route_sections() {
	uci -q show "$CONFIG" \
		| sed -n "s/^$CONFIG\\.\\(@route\\[[0-9][0-9]*\\]\\)=route/\\1/p"
}

route_kind() {
	local section="$1"
	local kind

	kind="$(uci_get "$section" kind)"
	[ -n "$kind" ] || kind="$(uci_get "$section" protocol http)"
	printf '%s\n' "$kind"
}

route_port_maps() {
	local section="$1"
	local kind="$2"
	local public_port backend_port

	case "$kind" in
		ssh)
			public_port="$(uci_get "$section" ssh_listen_port 22)"
			backend_port="$(uci_get "$section" ssh_backend_port 22)"
			printf '%s:%s\n' "$public_port" "$backend_port"
		;;
		rdp)
			public_port="$(uci_get "$section" rdp_listen_port 3389)"
			backend_port="$(uci_get "$section" rdp_backend_port 3389)"
			printf '%s:%s\n' "$public_port" "$backend_port"
		;;
		custom)
			for map in $(uci_get "$section" port_map); do
				printf '%s\n' "$map"
			done
		;;
		tcp)
			public_port="$(uci_get "$section" listen_port "$(uci_get "$section" backend_port)")"
			backend_port="$(uci_get "$section" backend_port)"
			printf '%s:%s\n' "$public_port" "$backend_port"
		;;
	esac
}

is_valid_port_map() {
	local map="$1"
	local public_port backend_port

	case "$map" in
		*:*:*) return 1 ;;
		*:*) ;;
		*) return 1 ;;
	esac

	public_port="${map%%:*}"
	backend_port="${map#*:}"
	is_valid_port "$public_port" && is_valid_port "$backend_port"
}

required_ports() {
	local section enabled kind http_enabled https_enabled map
	local http_port https_port

	http_port="$(uci_get main http_port 80)"
	https_port="$(uci_get main https_port 443)"
	[ "$(uci_get main enabled 0)" = 1 ] || return 0

	for section in $(route_sections); do
		enabled="$(uci_get "$section" enabled 1)"
		[ "$enabled" = 1 ] || continue
		kind="$(route_kind "$section")"

		case "$kind" in
			web)
				http_enabled="$(uci_get "$section" web_http 1)"
				https_enabled="$(uci_get "$section" web_https 1)"
				[ "$http_enabled" != 1 ] || printf '%s\n' "$http_port"
				[ "$https_enabled" != 1 ] || printf '%s\n' "$https_port"
			;;
			http)
				printf '%s\n' "$http_port"
			;;
			https)
				printf '%s\n' "$https_port"
			;;
			both)
				printf '%s\n%s\n' "$http_port" "$https_port"
			;;
			ssh|rdp|custom|tcp)
				for map in $(route_port_maps "$section" "$kind"); do
					printf '%s\n' "${map%%:*}"
				done
			;;
		esac
	done | sort -nu
}

port_spec_contains() {
	local spec="$1"
	local wanted="$2"
	local token first last

	for token in $(printf '%s' "$spec" | tr ',' ' '); do
		case "$token" in
			*-*)
				first="${token%%-*}"
				last="${token#*-}"
				[ "$wanted" -ge "$first" ] 2>/dev/null && [ "$wanted" -le "$last" ] 2>/dev/null && return 0
			;;
			*)
				[ "$token" = "$wanted" ] && return 0
			;;
		esac
	done

	return 1
}
