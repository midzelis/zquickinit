#!/bin/bash
set -euo pipefail

# Depends on: dosfstools, mtools, qemu
uki=$(ls ../output/ez-zbm*.efi -tp | tac |  grep -v /\$ | head -1)
kernel="$(ls ../output/vmlinuz* -tp | tac | grep -v /\$ | head -1)"
initrd="$(ls ../output/ez-zfs*.img -tp | tac | grep -v /\$ | head -1)"

# The following isn't technically needed for this invocation of QEMU
# However, if you want to use ProxMox's web interface to test, it 
# does not allow you to direct-boot kernel images. So, here we generate
# a FAT-partioned image and copy the EFI to the standard boot image location
# (/EFI/BOOT/BOOTX64.EFI) 
# So, just drop this generate raw image onto a QEMU managed by ProxMox
# and boot from it to test it out
read -ra size <<<$(du --apparent-size --block-size=1M "$uki")
out="../output/efi-partitioneda.raw"
echo "Generating raw file image for VM as $out"
rm -f $out
dd if=/dev/zero of="$out" bs="${size[0]}"M count=1
mformat -i "$out" ::
mmd -i "$out" ::/EFI
mmd -i "$out" ::/EFI/BOOT
mcopy -i "$out" "$uki" ::/EFI/BOOT/BOOTX64.EFI


APPEND=("loglevel=7 zbm.show console=ttyS0")

LINES="$( tput lines 2>/dev/null )"
COLUMNS="$( tput cols 2>/dev/null )"
[ -n "${LINES}" ] && APPEND+=( "zbm.lines=${LINES}" )
[ -n "${COLUMNS}" ] && APPEND+=( "zbm.columns=${COLUMNS}" )

qemu-system-x86_64 \
	-m 2G \
	-smp cores=1,threads=32 \
	-display default,show-cursor=on \
	-machine q35,vmport=off,i8042=off,hpet=off,accel=kvm \
	-device virtio-scsi-pci,id=scsi0 \
	-drive file=main-os.qcow2,if=none,discard=unmap,id=drive1 \
	-device scsi-hd,drive=drive1,bus=scsi0.0,bootindex=1 \
	-drive if=none,format=raw,file=../output/efi-partitioned.raw,id=drive2 \
	-net nic,model=virtio \
	-net user \
	-kernel "$kernel" \
	-initrd "$initrd" \
	-nographic \
	-serial "mon:stdio" \
	-append "${APPEND[*]}"



