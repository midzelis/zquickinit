#!/bin/bash

name="${0##*/}"
log() {
   logger -p user.notice -t "${name}" "$1"
}

if [[ -r /etc/ssh/sshd_config && -r /root/.ssh/authorized_keys ]]; then
    mkdir -p /var/chroot/ssh 
    mkdir -p /run/sshd
    /usr/sbin/sshd > /dev/null 2>&1
    log "sshd OK"
else
    log "sshd SKIPPED"
fi
