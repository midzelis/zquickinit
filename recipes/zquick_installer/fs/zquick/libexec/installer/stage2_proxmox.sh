#!/bin/bash
: "${DEBUG:=}"

# If we are debugging, enable trace
if [ "${DEBUG,,}" = "true" ]; then
  set -x
fi

configure() {

	# Enable root login over ssh with a password
	if [ -f /etc/ssh/sshd_config ]; then
		echo "NOTICE! Modifying /etc/ssh/sshd_config to allow root login"
		sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
		systemctl enable ssh.service || true
	fi

	[ -e /etc/network/interfaces.new ] && interfaces_conf=/etc/network/interfaces.new || interfaces_conf=/etc/network/interfaces
	if [ -e "${interfaces_conf}" ]; then
		# add a newline, to be safe
		echo "">>"${interfaces_conf}"
		function insert_config() {
			echo -e "auto lo\niface lo inet loopback\n"
			for i in /sys/class/net/*; do
				ID_NET_NAME=$(udevadm test-builtin net_id "$i" 2>/dev/null | grep '^ID_NET_NAME_PATH' | awk -F '=' '{print $2}')
				[[ -n ${ID_NET_NAME} ]] && echo -e "auto ${ID_NET_NAME}\niface ${ID_NET_NAME} inet dhcp\n" 
			done
		}
		function update_interfaces() {
			# Flips to 1 when first non-preserved line is found
			plainline=0
			# Read the file line by line
			while IFS= read -r line; do
				# Check if the line starts with a comment character '#'
				if [[ ${line} == \#* ]]; then
					# Preserve the comment line as is
					echo "${line}"
				elif [[ $line == source* ]]; then
					echo "${line}"
				else
					# insert config 
					if (( plainline==0 )); then insert_config; fi 
					plainline=1
				fi
			done < "$interfaces_conf"
		}
		new_conf=$(update_interfaces)
		printf "%s\n" "${new_conf}" > /etc/network/interfaces
		rm /etc/network/interfaces.new
		echo -e "Updated /etc/network/interfaces with:\n"
		cat /etc/network/interfaces
	else  
		echo "Could not configure network: /etc/network/interfaces not found"
	fi

	ip_address=$(ip -o -4 route show to default | awk '{print $5}' | head -n1 | xargs -I{} ip addr show {} | awk '/inet /{print $2}' | cut -d/ -f1)
	if [ -n "${interfaces_conf}" ]; then 
		[ -e /etc/hostname ] && host=$(cat /etc/hostname) || host=$(hostname)
		echo "$ip_address ${host}" >> /etc/hosts
		echo -e "Updated /etc/hosts with:\n$ip_address ${host}"
	else 
		echo "Could not configure network: /etc/network/interfaces not found"
	fi

	# # Remove build tools
	apt-get --yes autoremove

	# If not using /tmp/cache, clean the cache
	[ -d /tmp/cache ] || apt-get clean

}

install() {
	: "${RELEASE:=bookworm}"
	: "${APT_REPOS:=main contrib}"

	cat <<-EOF > /etc/apt/sources.list
		deb http://deb.debian.org/debian ${RELEASE} ${APT_REPOS}
		deb-src http://deb.debian.org/debian ${RELEASE} ${APT_REPOS}
		EOF

	# Prevent terminal stupidity and interactive prompts
	export TERM=xterm-256color
	export DEBIAN_FRONTEND=noninteractive
	export DEBCONF_NONINTERACTIVE_SEEN=true

	[ -e /root/hostname.conf ] && cat /root/hostname.conf > /etc/hostname && rm /root/hostname.conf
	[ -e /root/passwd.conf ] && echo "root:$(cat /root/passwd.conf)" | chpasswd -c SHA256 && rm /root/passwd.conf

	# https://jpetazzo.github.io/2013/10/06/policy-rc-d-do-not-start-services-automatically/
	echo "exit 101" > /usr/sbin/policy-rc.d
	chmod +x /usr/sbin/policy-rc.d

	# Post debootstrap update apt repos
	echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list
	wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg 
	# this directory is not created by ifupdown2 and install fails without it
	mkdir -p /run/network
	# Do the upgrade
	apt-get update --yes && apt-get full-upgrade --yes
	apt-get remove -- yes os-prober linux-image-amd64 'linux-image-6.1*'
	# Install the kernel, and ensure zfs is part of initramfs
	apt-get install --yes pve-kernel-6.2 proxmox-ve postfix open-iscsi chrony zfs-initramfs console-setup
	# optional: pve-headers-6.2 

	# The next 3 lines not needed, since proxmox ships custom kernel that includes zfs. But if you were doing
	# plain-debian, this would be required. 
	# Make sure the kernel is installed and configured before ZFS
	# apt-get install --yes linux-{headers,image}-amd64 
	# apt-get install --yes zfs-dkms zfsutils-linux zfs-initramfs

	configure

	rm /usr/sbin/policy-rc.d
}


install