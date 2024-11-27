#!/bin/bash

if [[ "0" == "$(zpool list -H 2>/dev/null | wc | awk '{print $1}')" ]]; then
    gum style --foreground="#daa520" "Note: no zfs pools found"
    #/zquick/zbootstrap.sh
fi
gum format -- "## zbootstrap.sh" "- install/upgrade Zquickinit" "- install Proxmox" "- convert LVM boot to ZFS root datasets" "- encrypt ZFS root datasets" ""
echo
