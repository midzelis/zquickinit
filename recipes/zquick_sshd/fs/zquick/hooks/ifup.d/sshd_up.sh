#!/bin/bash

log() {
  echo "zquick: $1" > /dev/kmsg
}

if [[ -r /etc/ssh/sshd_config && -r /root/.ssh/authorized_keys ]]; then
    mkdir -p /var/chroot/ssh 
    /usr/sbin/sshd > /dev/null 2>&1
    log "sshd OK"
else
    log "sshd SKIPPED"
fi