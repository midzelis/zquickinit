#!/bin/bash

# this is a one time task
[[ -f /var/run/ez_ifup ]] && exit 0
touch /var/run/ez_ifup

log() {
  echo "ez_net: $1" > /dev/kmsg
}

mkdir -p /var/lib/dhcp
mkdir -p /etc/dhcp
touch /etc/fstab
touch /etc/resolv.conf

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

    mkdir -p /var/log
    # only keep the funnel URL up for 30 minutes
	if  dhclient -1 "$interface" -lf /var/lib/dhcp/dhclient.leases -v > /var/log/dhclient.log 2>&1 ; then
		log "[$interface] DHCP OK"
	else 
		log "[$interface] DHCP FAILED"
	fi
done

# Start any lazy net hooks, if present
for f in /ez_recipes/ez_ifup.d/*; do
	if [[ -x $f ]]; then 
		"$f" 
	fi
done

