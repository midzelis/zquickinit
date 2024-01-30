#!/bin/bash

# shellcheck disable=SC1091
. /zquick/libexec/utils.sh

qinitlog_start "sshd"
if [[ -r /etc/ssh/sshd_config && -r /root/.ssh/authorized_keys ]]; then
    mkdir -p /var/chroot/ssh 
    mkdir -p /run/sshd
    /usr/sbin/sshd > /dev/null 2>&1
    qinitlog_end "[ OK ]"
else
    qinitlog_end "[ Not Configured ]"
fi

