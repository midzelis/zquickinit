#!/bin/bash
name=$(basename "$0")
log() {
   logger -p user.notice -t "${name}" "$1"
}

# this is a one time task
[[ -f /zquick/run/ifup ]] && exit 0
mkdir -p /zquick/run
touch /zquick/run/ifup

mkdir -p /var/lib/dhcp
mkdir -p /etc/dhcp
[[ ! -e /etc/fstab ]] && rm -f /etc/fstab; touch /etc/fstab
[[ ! -e /etc/resolv.conf ]] && rm -f /etc/resolv.conf; touch /etc/resolv.conf

cat > /etc/dhcp/dhclient.conf <<-EOF
	timeout 30;
	option classless-static-routes code 121 = array of unsigned integer 8;
	send dhcp-client-identifier = hardware;
	request subnet-mask, broadcast-address, time-offset, routers,
		domain-name, domain-name-servers, domain-search, host-name,
		root-path, interface-mtu, classless-static-routes,
		netbios-name-servers, netbios-scope, ntp-servers,
		dhcp6.domain-search, dhcp6.fqdn,
		dhcp6.name-servers, dhcp6.sntp-servers;
	EOF

# Get a list of all network interfaces
interfaces=$(ip link show | awk -F': ' '{print $2}')

# Bring up each interface and get a DHCP IP address
for interface in $interfaces; do
		log "[$interface] Bringing up..."
		if ip link set "$interface" up > /dev/kmsg; then
				log "[$interface] Link OK"
		else
				log "[$interface] Link FAILED"
		fi
		[[ $interface == 'lo' ]] && continue
		log "Getting IP address using DHCP"

		# only keep the funnel URL up for 30 minutes
		dhclient "$interface" -lf /var/lib/dhcp/dhclient.leases || true
done

/zquick/libexec/run_hooks.sh ifup.d