#!/bin/bash

getip() {
    interface=$(ip route | grep default | awk '{print $5}')
    # Get the IP address associated with the active interface
    ip_address=$(ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "$ip_address"
}
status+="#[fg=colour255,bg=colour17] Hostname [#[fg=colour255,bg=colour25]$(hostname)"
status+="#[fg=colour255,bg=colour17]] | ip [#[fg=colour255,bg=colour25]$(getip)"
status+="#[fg=colour255,bg=colour17]] | Tailscale [#[fg=colour0,bg=colour25]"
if which tailscale >/dev/null2 >&1 && [[ -r /var/lib/tailscale/tailscaled.state ]]; then
    ts_status=$(tailscale status --json)
    if [[ $(echo "$ts_status" | yq e '.Self.Online' -oy) == "true" ]]; then
        status+=" UP "
    else
        status+=" DOWN "
    fi
    status+="$(echo "$ts_status" | yq e '.Self.DNSName | .. |= sub("\.$", "")' -oy)"
else
    status+=" N/A "
fi
status+="#[fg=colour255,bg=colour17]]#[fg=colour255,bg=colour17] | WebTTYd [#[fg=colour0,bg=colour25]"
if pgrep ttyd >/dev/null; then
    status+=" UP "
else
    status+=" DOWN "
fi
status+="#[fg=colour255,bg=colour17]]"
echo "$status"
