#!/bin/bash

status+="#[fg=colour255,bg=colour25]$(hostname)"
status+="#[fg=colour255,bg=colour17] | Tailscale [#[fg=colour0,bg=colour25]"
if which tailscale >/dev/null && [[ -r /var/lib/tailscale/tailscaled.state ]]; then
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
if pgrep ttyd; then
    status+=" UP "
else    
    status+=" DOWN "
fi
status+="#[fg=colour255,bg=colour17]]"
echo "$status"

