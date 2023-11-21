#!/bin/bash

if [[ "0" == "$(zpool list -H | wc | awk '{print $1}')" ]]; then
    gum style --foreground="#ff9770" "No ROOT zpools found: running zquick_installer.sh"
    /zquick/zquick_installer.sh
fi

