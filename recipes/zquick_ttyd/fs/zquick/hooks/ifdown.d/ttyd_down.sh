#!/bin/bash

PUSHOVER_APP_TOKEN=
PUSHOVER_USER_KEY=
if [ -r /zquick/etc/ttyd_pushover.conf ]; then
    source /zquick/etc/ttyd_pushover.conf
fi

if [ -n "${PUSHOVER_APP_TOKEN}" ] && [ -n "${PUSHOVER_USER_KEY}" ]; then

    curl -s \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=$(hostname) is booting selected env" \
        --form-string "sound=intermission" \
        https://api.pushover.net/1/messages >> /dev/null

fi
