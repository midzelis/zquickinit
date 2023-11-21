#!/bin/bash

name=$(basename "$0")
log() {
   logger -p user.notice -t "${name}" "$1"
}

log "QEMU Loading shared directories"

mkdir -p /mnt/qemu-host
mount -t 9p -o trans=virtio qemuhost /mnt/qemu-host -oversion=9p2000.L,posixacl,msize=104857600 >/dev/null 2>&1 || rmdir /mnt/qemu-host
mkdir -p /mnt/cache
mount -t 9p -o trans=virtio qemucache /mnt/cache -oversion=9p2000.L,posixacl,msize=104857600 >/dev/null 2>&1 || rmdir /mnt/cache

log "QEMU OK"