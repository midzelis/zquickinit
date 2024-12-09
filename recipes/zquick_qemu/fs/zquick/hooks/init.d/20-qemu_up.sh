#!/bin/bash

source /zquick/libexec/utils.sh

if grep -q "hypervisor" /proc/cpuinfo; then

    qinitlog "Detected KVM: QEMU mounting shared directories /mnt/qemu-host, /mnt/cache"

    mkdir -p /mnt/qemu-host
    mount -t 9p -o trans=virtio qemuhost /mnt/qemu-host -oversion=9p2000.L,posixacl,msize=104857600 >/dev/null 2>&1 || rmdir /mnt/qemu-host
    mkdir -p /mnt/cache
    mount -t 9p -o trans=virtio qemucache /mnt/cache -oversion=9p2000.L,posixacl,msize=104857600 >/dev/null 2>&1 || rmdir /mnt/cache
fi
