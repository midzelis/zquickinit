#!/bin/bash
[[  -r "/etc/hostname" ]] && cat /etc/hostname > /proc/sys/kernel/hostname
