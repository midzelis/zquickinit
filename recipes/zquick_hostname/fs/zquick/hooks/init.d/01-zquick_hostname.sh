#!/bin/bash
source /zquick/libexec/utils.sh

[[  -r "/etc/hostname" ]] && qinitlog "Setting hostname to \"$(cat /etc/hostname)\"" && cat /etc/hostname > /proc/sys/kernel/hostname

