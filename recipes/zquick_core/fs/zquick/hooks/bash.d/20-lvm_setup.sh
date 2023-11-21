#!/bin/bash

log() {
   echo "$1"
}

[[ -f /zquick/run/lvm_setup ]] && exit 0
touch /zquick/run/lvm_setup

if command -v lvm >/dev/null 2>&1; then
    log "Scanning for LVM volumes and auto-mounting..."
    count=0
    modprobe dm_thin_pool
    lvm vgscan -v 2>/dev/null
    lvm vgchange -a y 2>/dev/null

    lvm_volumes=$(lvm lvscan 2>/dev/null | awk '{print $2}' | tr -d "'")
    for volume in $lvm_volumes; do
        # Get the logical volume path
        lv_path=$(lvm lvdisplay "${volume}" 2>/dev/null | grep "LV Path" | awk '{print $3}')

        if [[ $(lsblk -no FSTYPE  "${lv_path}") = "swap" ]]; then
            log "Skipping swap: ${lv_path}"
            continue;
        fi

        # Get the volume path
        volume=$(echo "${lv_path}" | awk -F'/' '{for(i=3;i<=NF;i++) printf "/%s", $i}')

        # Create the mount point directory
        mkdir -p "/mnt${volume}"

        # Mount the volume
        log "Mounting ${lv_path} on /mnt${volume}"
        mount "${lv_path}" "/mnt${volume}"
        count=(count+1)
    done
    ((count==0)) && echo "No volumes found"
fi

