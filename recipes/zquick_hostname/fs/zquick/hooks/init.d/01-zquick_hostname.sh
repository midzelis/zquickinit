#!/bin/bash
source /zquick/libexec/utils.sh

if [[ -r "/etc/hostname" ]]; then
    qinitlog "Setting hostname to \"$(cat /etc/hostname)\""
    cat /etc/hostname >/proc/sys/kernel/hostname
fi
