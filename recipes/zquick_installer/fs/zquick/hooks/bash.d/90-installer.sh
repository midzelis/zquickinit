#!/bin/bash

if [[ "0" == "$(zpool list -H 2>/dev/null | wc | awk '{print $1}')" ]]; then
    gum style --foreground="#daa520" "Note: no zfs pools found"
    #/zquick/zquick_installer.sh
fi
gum format -t template -- "{{ Foreground \"#ff9770\" \"'zbootstrap.sh'\"}} will let you install Proxmon, convert LVM boot to ZFS root datasets, encrypt ZFS root datasets" ""
