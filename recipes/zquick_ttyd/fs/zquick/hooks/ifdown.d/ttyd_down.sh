#!/bin/bash

if [[ -n "${PUSHOVER_APP_TOKEN}" ]] && [[ -n "${PUSHOVER_USER_KEY}" ]]; then

    curl -s \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "message=$(hostname) is booting selected env" \
        --form-string "sound=intermission" \
        https://api.pushover.net/1/messages >> /dev/null

fi

