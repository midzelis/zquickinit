#!/bin/bash

set -euo pipefail

if [[ ! -r /var/lib/tailscale/tailscaled.state || ! -r /etc/zquickinit.conf ]]; then 
	exit 0
fi

start() {
    ts_status=$(tailscale status --json)
    [[ -z ${ts_status} ]] && exit 1
    dnsname=$(echo "${ts_status}" | yq e '.Self.DNSName | .. |= sub("\.$", "")' -oy || :)
    [[ -z ${dnsname} ]] && exit 1

    randompath=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) || :

    url="https://${dnsname}/$randompath"

    PUSHOVER_APP_TOKEN=$(sed -rn '/^PUSHOVER_APP_TOKEN=/s/.*=(.*)/\1/p' "/etc/zquickinit.conf")
    PUSHOVER_USER_KEY=$(sed -rn '/^PUSHOVER_USER_KEY=/s/.*=(.*)/\1/p' "/etc/zquickinit.conf")

    if [ -n "${PUSHOVER_APP_TOKEN}" ] && [ -n "${PUSHOVER_USER_KEY}" ]; then
        curl -s \
            --form-string "token=$PUSHOVER_APP_TOKEN" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$(hostname) web auth is available (Click link)" \
            --form-string "url_title=Unlock URL" \
            --form-string "url=$url" \
            --form-string "sound=intermission" \
            https://api.pushover.net/1/messages >> /dev/null

        mkdir -p /var/log
        tailscale funnel --bg --https=443 "http://localhost:80/$randompath" >> /var/log/ttyd.log
        # only keep the funnel URL up for 30 minutes
        timeout -k 1s 30m ttyd -i 127.0.0.1 -p 80 -b "/$randompath" tmux new-session -A -s ZFSBootMenu >> /var/log/ttyd.log 2>&1 

        curl -s \
            --form-string "token=$PUSHOVER_APP_TOKEN" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$(hostname) web auth has been shutdown due to timeout." \
            --form-string "sound=intermission" \
            https://api.pushover.net/1/messages >> /dev/null

        tailscale funnel --https=443 off
    fi
}

start

