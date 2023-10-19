#!/bin/bash

log() {
  echo "zquick: $1" > /dev/kmsg
}

log "QEMU Loading shared directories"

mount -m -t 9p -o trans=virtio qemuhost /mnt/qemu-host -oversion=9p2000.L,posixacl,msize=104857600 >/dev/null 2>&1
mount -m -t 9p -o trans=virtio qemucache /mnt/cache -oversion=9p2000.L,posixacl,msize=104857600 >/dev/null 2>&1

log "QEMU OK"