#!/bin/bash

source /zquick/libexec/utils.sh

# this is a one time task
[[ -f /zquick/run/ifup ]] && exit 0
qinitlog "Starting network interfaces"

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
		qinitlog_start "Set link up: $interface"
		if status=$(ip link set "$interface" up); then
			qinitlog_end " [ OK ]"
		else
			qinitlog_end " [ FAILED ] ${status}"
		fi
		[[ $interface == 'lo' ]] && continue
		qinitlog "DHCP client (dhclient): [$interface]"
		dhclient "$interface" -lf /var/lib/dhcp/dhclient.leases -nw || :
done

qinitlog "Starting network services"
/zquick/libexec/run_hooks.sh ifup.d
