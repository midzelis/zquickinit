#!/bin/bash

set -euo pipefail

. /zquick/libexec/utils.sh

if [[ ! -r /var/lib/tailscale/tailscaled.state || ! -r /etc/zquickinit.conf ]]; then
    qdebug "ttyd.sh not starting: missing tailscaled.state or zquickinit.conf"
    exit 0
fi

PUSHOVER_APP_TOKEN=$(sed -rn '/^PUSHOVER_APP_TOKEN=/s/.*=(.*)/\1/p' "/etc/zquickinit.conf")
PUSHOVER_USER_KEY=$(sed -rn '/^PUSHOVER_USER_KEY=/s/.*=(.*)/\1/p' "/etc/zquickinit.conf")

if [ -z "${PUSHOVER_APP_TOKEN}" ] || [ -z "${PUSHOVER_USER_KEY}" ]; then
    qdebug "ttyd.sh not starting: PUSHOVER_APP_TOKEN or PUSHOVER_USER_KEY"
    exit 0
fi

curl -s \
    --form-string "token=$PUSHOVER_APP_TOKEN" \
    --form-string "user=$PUSHOVER_USER_KEY" \
    --form-string "message=ZQuickInit: $(hostname) has started, webauth available shortly" \
    --form-string "sound=intermission" \
    https://api.pushover.net/1/messages >>/dev/null

#!/bin/bash

wait_for_ts() {
    # Maximum time to wait (in seconds)
    MAX_WAIT_TIME=1800
    # Poll interval (in seconds)
    POLL_INTERVAL=1

    start_time=$(date +%s)

    while true; do
        ts_status=$(tailscale status --json)
        [[ -z ${ts_status} ]] && exit 1

        dnsname=$(echo "${ts_status}" | yq e '.Self.DNSName | .. |= sub("\.$", "")' -oy || :)

        if [[ -n ${dnsname} ]]; then
            qdebug "DNS Name found: ${dnsname}"
            break
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [[ $elapsed_time -ge $MAX_WAIT_TIME ]]; then
            qdebug "Timed out waiting for DNS Name."
            exit 1
        fi

        sleep $POLL_INTERVAL
    done
}

start() {
    qdebug "Waiting 30 seconds for tailscale to start"
    sleep 30

    wait_for_ts

    randompath=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) || :
    url="https://${dnsname}/$randompath"

    curl -s \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=ZQuickInit: $(hostname) web auth is available (Click link)" \
        --form-string "url_title=Unlock URL" \
        --form-string "url=$url" \
        --form-string "sound=intermission" \
        https://api.pushover.net/1/messages >>/dev/null

    mkdir -p /var/log
    tailscale funnel --bg --https=443 "http://localhost:80/" >>/var/log/ttyd.log
    # only keep the funnel URL up for 30 minutes
    timeout -k 1s 30m ttyd -i 127.0.0.1 -p 80 -b "/$randompath" tmux new-session -A -s ZFSBootMenu >>/var/log/ttyd.log 2>&1

    curl -s \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=ZQuickInit: $(hostname) web auth has been shutdown due to timeout." \
        --form-string "sound=intermission" \
        https://api.pushover.net/1/messages >>/dev/null

    tailscale funnel --https=443 off

}

start
