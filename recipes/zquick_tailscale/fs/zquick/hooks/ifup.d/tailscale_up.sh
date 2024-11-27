#!/bin/bash

# shellcheck disable=SC1091
. /zquick/libexec/utils.sh

if [ ! -r /var/lib/tailscale/tailscaled.state ]; then 
	qinitlog "tailscaled [ Not Configured ]"
	exit 0
fi

qinitlog_start "tailscaled"

# create pts if not available
if [ ! -d /dev/pts ]; then
	mkdir -p /dev/pts
	mount -t devpts devpts /dev/pts
fi

# shellcheck disable=SC1091
[ -r /etc/tailscale/tailscaled.conf ] && . /etc/tailscale/tailscaled.conf

mkdir -p /var/log
modprobe tun
(exec setsid tailscaled --statedir=/var/lib/tailscale > /var/log/tailscale.log 2>&1 &)

if status=$(tailscale up --reset --ssh --timeout="${tailscale_timeout:-20s}" ${tailscale_args:-} 2>&1); then
	  qinitlog_end "[ OK ]"
else
	  qinitlog_end "[ FAILED ] ($status)"
fi