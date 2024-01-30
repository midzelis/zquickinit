#!/bin/bash
set -euo pipefail
: "${DEBUG:=}"

# If we are debugging, enable trace
if [ "${DEBUG,,}" = "true" ]; then
  set -x
fi

[ -z "${INSTALLER_DIR}" ] && echo "env var INSTALLER_DIR must be set" && exit 1

export GUM_INPUT_PROMPT_FOREGROUND="#ff9770"
export FOREGROUND="#70D6FF"
export GUM_CHOOSE_ITEM_FOREGROUND="#e9ff70"

INJECT_SCRIPT=/zquick/zquickinit.sh
INSTALL_SCRIPT=${INSTALLER_DIR}/stage1_proxmox.sh
CHROOT_SCRIPT=${INSTALLER_DIR}/stage2_proxmox.sh
POSTINSTALL_SCRIPT=${INSTALLER_DIR}/stage3_proxmox.sh
EXISTING=
CHROOT_MNT=

# INSTALLER_DIR=/mnt/qemu-host/recipes/zquick_installer/fs/zquick/libexec/installer zquick_installer.sh
# zpool create -O acltype=posixacl -o compatibility=openzfs-2.0-linux TMP /dev/sdb

STDOPTS=( "-o compression=zstd" "-o atime=off" "-o acltype=posixacl" "-o aclinherit=passthrough" "-o xattr=sa" "-o mountpoint=/" "-o canmount=noauto")

log() {
    if [ $# -eq 0 ]; then
        cat - | while read -r message; do
            gum style --faint "$message"
        done
    else   
        gum style --faint "$*" 
    fi
}

xlog() {
    "$@" | log
    return "${PIPESTATUS[0]}"
}

xspin() {
    gum style --faint "$*" 
    ret=0
    gum spin --spinner=points --title='' -- bash -c "$* > /tmp/tmp 2>&1" || ret=$?
    out=''
    [[ -e /tmp/tmp ]] && out="$(cat /tmp/tmp)"
    if ((ret!=0)); then
        [[ -n "$out" ]] && gum style --foreground=1 "${out}"
    else
        [[ -n "$out" ]] && gum style --faint --foreground=#ffe2cc "${out}"
    fi
    rm -rf /tmp/tmp
    return "$ret"
}

zpool_export() {
    xspin zpool export "$1"
}

cleanup() {
  ret=$?
  set +u
  if [ -n "${CHROOT_MNT}" ]; then
    echo "Cleaning up chroot mount '${CHROOT_MNT}'"
    mountpoint -q "${CHROOT_MNT}" && umount -R "${CHROOT_MNT}"
    [ -d "${CHROOT_MNT}" ] && rmdir "${CHROOT_MNT}"
    unset CHROOT_MNT
  fi

  if [ -n "${POOLNAME}" ]; then
    echo "Exporting pool '${POOLNAME}'"
    zpool_export "${POOLNAME}"
    unset POOLNAME
  fi

  zpool import -a
  exit $ret
}

confirm() {
    local code=
    gum confirm "$@" && code=$? || code=$? 
    ((code>2)) && exit $code
    return $code
}

choose() {
    local code=0
    var=$(gum choose "$@") || code=$?
    ((code>0)) && exit $code
    echo "$var"
} 

input() {
    local code=0
    var=$(gum input "$@") || code=$?
    ((code>0)) && exit $code
    echo "$var"
} 

mount_esp() {
    if ! mountpoint -q /efi; then 
        mkdir -p /efi
        if ! xspin mount "$1" /efi; then
            echo "Could not mount $1 on /efi"
            exit 1
        fi
    fi
}

import_tmproot_pool() {
    trap cleanup EXIT INT TERM

    # sometimes zfs gets confused on where to find the pools, so specify all devices to help it
    #devs=$(lsblk -no path | awk '{print "-d " $0}')
    CHROOT_MNT="$( mktemp -d )" || exit 1
    if ! xspin zpool import -o cachefile=none -R "${CHROOT_MNT}" "${POOLNAME}"; then
        echo "ERROR: unable to import ZFS pool ${POOLNAME}"
        exit 1
    fi
    export CHROOT_MNT
}

mount_dataset() {
    if encroot="$( be_has_encroot "${DATASET}" )"; then
        log zfs mount "${DATASET}"
        log zfs load-key -L prompt "${encroot}"
        zfs load-key -L prompt "${encroot}"
        zfs mount "${DATASET}"
    else 
        if ! xspin zfs mount "${DATASET}"; then
            echo "ERROR: unable to mount ${DATASET}"
            exit 1
        fi
    fi
    
}

install_esp() {
    if confirm --default=${1:-no} "Install/Update ZFSQuickInit on EFI System Partition?"; then
        gum style "* Install/Update ZFSQuickInit"
        local devs='' esps=''
        esps=$(lsblk -o PATH,SIZE,TYPE,PARTTYPENAME,PARTTYPE -J | yq '.blockdevices.[] | select(.parttype=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b") | .path')
        devs=$(lsblk -n -o PATH,SIZE,TYPE,PARTTYPENAME,PARTLABEL $esps)
        readarray -t choices <<<"$devs"

        if (( ${#choices[@]} == 1 )); then
            ESP=$( printf '%s' "${choices[0]}" | awk '{print $1}')
            gum style --foreground="#ff70a6" "Autoselected only available ESP partition: $ESP"
            gum style ""
        else
            gum style --bold "Select ESP partition:"
            ESP=$(choose "${choices[@]}" | awk '{print $1}')
            gum style "Selected: $ESP"
            gum style ""
        fi
        kind=gummiboot
        if which bootctl > /dev/null; then
            kind=systemd-boot
        fi
        if confirm "Format $ESP with FAT32 and install ${kind}?"; then
            gum style "Format $ESP with FAT32"
            gum style ""
            xspin mkfs.fat -F 32 -v "$ESP"
            mount_esp "$ESP"
            gum style ""
            gum style "Installing ${kind} to /efi"
            if [[ "${kind}" = "gummiboot" ]]; then
                xspin gummiboot install --path=/efi --no-variables
            else 
                xspin bootctl install --path=/efi --no-variables
            fi
            gum style ""
        else    
            gum style --foreground="#ff70a6" "Did not format $ESP"
            gum style ""
        fi
        if confirm "Configure QuickInitZFS gummiboot entries on /efi?"; then
            gum style "Copying QuickInitZFS to /efi"
            gum style ""
            mount_esp "$ESP"
            efi=''
            # start QEMU envs
            if [[ -d /mnt/qemu-host/output ]]; then
                efi=$(find /mnt/qemu-host/output -type f -name '*.efi' -printf '%f\t%p\n' | sort -k1 | cut -d$'\t' -f2 | tail -n1)
            fi
            if [[ -d /mnt/qemu-host ]]; then
                INJECT_SCRIPT=$(find /mnt/qemu-host -type f -name 'zquickinit.sh' -print -quit)
            fi
            # end QEMU envs
            (
                export INSTALLER_MODE=1
                debugopt=
                [ "${DEBUG,,}" = "true" ] && debugopt="-d"
                "$INJECT_SCRIPT" inject --add-loader "$efi" "${debugopt}"
            )
            gum style ""
        fi
        #mountpoint -q /efi && umount /efi
    fi
}

partition_drive() {
    if confirm --default=no "Partition a disk? (GPT style with 3 partitions: BIOS, ESP, ZFS)"; then
        gum style "* Partitioning"
        tput sc
        gum style --bold "Select a disk to auto-partition:"
        local devs
        devs=$(lsblk -p -d -n)
        readarray -t choices <<<"$devs"

        if (( ${#choices[@]} == 1 )); then
             gum style "No disks found!"
             return 1
        fi
        echo "  $(lsblk -p -d | head -n1)"
        DEV=$(choose "${choices[@]}" | awk '{print $1}')
        tput rc
        tput ed
        gum style ""

        tput sc
        gum style --bold "CAUTION!!! ALL DATA WILL BE ERASED"
        if confirm --default=no "Proceed with partitioning $DEV?"; then
            log umount "$DEV"?*
            umount "$DEV"?* >/dev/null 2>&1 || :
            gum spin --spinner=points --title="Clearing partition" -- sgdisk -og "$DEV" > /dev/null
            gum spin --spinner=points --title="Creating BIOS Boot Partition" -- sgdisk -n 1:2048:+1M -c 1:"BIOS Boot Partition" -t 1:ef02 "$DEV" > /dev/null
            gum spin --spinner=points --title="Creating EFI System Partition" -- sgdisk -a 1048576 -n 2:0:+512M -c 2:"EFI System Partition" -t 2:ef00 "$DEV" > /dev/null
            end_position=$(sgdisk -E "$DEV")
            # align end position to nearest 1048576
            end_position=$(( end_position - (end_position + 1) % 2048 ))
            gum spin --spinner=points --title="Creating ZFS Partition" -- sgdisk -a 1048576 -n 3:0:${end_position} -c 3:"ZFS Root Partition" -t 3:bf01 "$DEV" > /dev/null
            tput rc
            tput ed
            log sgdisk -og "$DEV"
            log sgdisk -n 1:2048:+1M -c 1:"BIOS Boot Partition" -t 1:ef02 "$DEV" 
            log sgdisk -a 1048576 -n 2:0:+512M -c 2:"EFI System Partition" -t 2:ef00 "$DEV" 
            log sgdisk -a 1048576 -n 3:0:${end_position} -c 3:"ZFS Root Partition" -t 3:bf01 "$DEV"
            gum style "Partitioning successful"
            gum style ""
            xspin wipefs -a "$DEV"1
            xspin wipefs -a "$DEV"2
            xspin wipefs -a "$DEV"3
            xspin sgdisk -p "$DEV"
            xspin sgdisk -v "$DEV"
            gum style ""
            scan_parts "$DEV"
            return 0
        fi
    fi
    return 1
}

scan_parts() {
    log kpartx -u "$1" 
    kpartx -u "$1" || :
    # dmsetup will try to map these drives, so remove them
    if command -v dmsetup >/dev/null 2>&1; then
        dev=/$(echo "$1" | cut -d/ -f3-)
        log dmsetup remove /dev/mapper/"${dev}"*
        dmsetup remove /dev/mapper/"${dev}"*  >/dev/null 2>&1 || :
    fi
}

create_pool() {
    gum style --bold "Choosing partition for new ZFS root pool"
    local zparts=
    zparts=$(lsblk -o PATH,SIZE,TYPE,PARTTYPENAME,PARTTYPE -J | yq '.blockdevices.[] | select(.parttype=="6a898cc3-1dd2-11b2-99a6-080020736631") | .path')
    if [[ -z "${zparts}" ]]; then
        echo "No suitable ZFS partitions found"
        exit 1
    fi
    devs=$(lsblk -n -o PATH,SIZE,TYPE,PARTTYPENAME,PARTLABEL $zparts)
    readarray -t choices <<<"$devs"
    if (( ${#choices[@]} == 1 )); then
        DEV=$( printf '%s' "${choices[0]}" | awk '{print $1}')
        gum style --foreground="#ff70a6" "Autoselected only available ZFS partition: $DEV"
        gum style ""
    else
        tput sc
        gum style --bold "Select a partition for ZFS root:"
        echo "  $(lsblk -o PATH,SIZE,TYPE,PARTTYPENAME,PARTLABEL $zparts | head -n1)"
        DEV=$(choose "${choices[@]}" | awk '{print $1}')
        tput rc
        tput ed
        gum style --foreground="#ff70a6" "Selected: $DEV"
        gum style ""
    fi
    
    POOLNAME=$(input --value=rpool --prompt="Enter name for pool (i.e rpool)> ")

    gum style --bold "Create ZFS pool ${POOLNAME} on ${DEV}"
    gum style ""
    if confirm; then
        xspin zpool create -f -m none \
            -O compression=zstd \
            -O acltype=posixacl \
            -O aclinherit=passthrough \
            -O xattr=sa \
            -O atime=off \
            -o ashift=12 \
            -o autotrim=on \
            -o cachefile=none \
            -o compatibility=openzfs-2.0-linux \
            "${POOLNAME}" "${DEV}";
        if confirm "Perform zpool secure trim, falling back to non-secure trim if not supported?"; then
            log "Trying zpool secure trim"
            if xspin zpool trim -d -w "${POOLNAME}"; then
                log "Secure trim success"
            else 
                log "Could not perform secure trim, trying regular trim"
                if xspin zpool trim -w "${POOLNAME}"; then
                    log "Zpool trim success"
                else
                    log "Zpool trim did not return successfully: continuing"
                fi
            fi
        fi
        if confirm "Perform zpool initialize? This may take a long time. "; then
            log "Initializing zpool..."
            xspin zpool initialize -w "${POOLNAME}" || :
        fi
    else
        exit 1
    fi

}

select_pool() {
    gum style --bold "Choose ZFS pool:"
    local pools
    pools=$(zpool list -H -o name)
    readarray -t choices < <(printf %s "$pools")
    if (( ${#choices[@]} == 0 )); then
        echo "No existing pools, aborting"
        exit 1
    fi
    POOLNAME=$(choose "${choices[@]}" | awk '{print $1}')
}

pick_or_create_pool() {
    local defaultEsp=no
    if confirm  --default=no --affirmative="Create New Pool" --negative="Select Existing Pool" "Create (and optionally partition) new ZFS root pool?"; then
        gum style "* New Pool"
        partition_drive
        create_pool
        defaultEsp=yes
    else
        gum style "* Existing Pool"
        select_pool
    fi
    install_esp $defaultEsp
}

encrypt_ROOT() {
    if encroot="$( be_has_encroot "${POOLNAME}"/ROOT )"; then
        echo "${POOLNAME}/ROOT is already encrypted"
        exit 1
    fi
    xspin zpool checkpoint "${POOLNAME}"
    xspin zfs snapshot -r "${POOLNAME}"/ROOT@copy
    
    readarray -t sets <<<"$(zfs list | grep ^"${POOLNAME}"/ROOT/ | awk '{print $1}')"
    create_encrypted_dataset "${POOLNAME}"/COPY

    for set in "${sets[@]}"; do
        under_root=${set#"${POOLNAME}"/ROOT/}
        size=$(zfs send -RvnP "${set}@copy" | tail -n1 | awk '{print $NF}')
        log zfs send -R "${set}@copy" | pv -Wpbafte -s "$size" -i 1 | zfs receive -o encryption=on "${POOLNAME}/COPY/${under_root}"
        zfs send -R "${set}@copy" | pv -Wpbafte -s "$size" -i 1 | zfs receive -o encryption=on "${POOLNAME}/COPY/${under_root}"
    done
    xspin zfs destroy -R "${POOLNAME}/ROOT"
    xspin zfs rename "${POOLNAME}/COPY" "${POOLNAME}/ROOT"
    xspin zpool checkpoint -d -w "${POOLNAME}"
}

create_encrypted_dataset() {
    local ret=0
    log zfs create ${2:-} -o encryption=on -o keyformat=passphrase -o keylocation=prompt "$1"
    for i in $(seq 1 3); do
        ((i>1)) && echo "Retrying $i of 3..."
        zfs create ${2:-} -o encryption=on -o keyformat=passphrase -o keylocation=prompt "$1" && ret=$? || ret=$? 
        ((ret==0)) && break
    done
    ((ret > 0)) && exit $ret
    # After setting the passphrase, change keylocation to be a file which doesn't exist. ZFSBootMenu/ZFS will take care
    # of loading they key using 'zfs load-key -L prompt' to ask for the key even with a missing file for keylocation. 
    # This path will be used by quick_loadkey to temporarily store the key so that it can be loaded by the chainloaded 
    # kernel (i.e. proxmox, or another OS)
    keydir=${1%/*}
    keyfile=${1##/*}
    xspin zfs set "keylocation=file:///root/$keydir/$keyfile.key" "$1"
}

ensure_ROOT() {
    if ! zfs list "${POOLNAME}"/ROOT &>/dev/null; then
        gum style "Boot Environment Holder"
        if confirm "All Boot Environments are located under ${POOLNAME}/ROOT. Create it?"; then
            if confirm --default=no "Do you want to encrypt "${POOLNAME}/ROOT"? "; then
                create_encrypted_dataset "${POOLNAME}/ROOT" "-o mountpoint=none"
            else 
                xspin zfs create -o mountpoint=none "${POOLNAME}/ROOT"
            fi
        else
            echo "Aborted"
            exit 1
        fi
    fi
}

has_roots() {
    local datasets roots ret
    datasets=$(zfs list | grep ^"$POOLNAME"/ROOT | wc | awk '{print $1}')
    roots=$(( datasets - 1))
    ret=$(( roots<=0 ))
    return $ret
}

is_writable() {
  local pool roflag

  pool="${1}"
  if [ -z "${pool}" ]; then
    zerror "pool is undefined"
    return 1
  fi

  # Pool is not writable if the property can't be read
  roflag="$( zpool get -H -o value readonly "${pool}" 2>/dev/null )" || return 1

  if [ "${roflag}" = "off" ]; then
    return 0
  fi

  # Otherwise, pool is not writable
  return 1
}

be_has_encroot() {
  local fs pool encroot

  fs="${1%@*}"
  if [ -z "${fs}" ]; then
    return 1
  fi

  pool="${fs%%/*}"

  if [ "$( zpool list -H -o feature@encryption "${pool}" )" != "active" ]; then
    echo ""
    return 1
  fi

  if encroot="$( zfs get -H -o value encryptionroot "${fs}" 2>/dev/null )"; then
    if [ "${encroot}" != "-" ]; then
      echo "${encroot}"
      return 0
    fi
  fi

  echo ""
  return 1
}

be_is_locked() {
  local fs keystatus encroot

  fs="${1}"
  if [ -z "${fs}" ]; then
    echo "fs is undefined"
    return 1
  fi

  if encroot="$( be_has_encroot "${fs}" )"; then
    keystatus="$( zfs get -H -o value keystatus "${encroot}" )"
    case "${keystatus}" in
      unavailable)
        return 0;
        ;;
      *)
        ;;
    esac
  fi

  return 1
}

create_dataset() {
    gum style "Boot Environment Creation"
    local set 
    set=$(input --value=pve1 --prompt="Enter name for boot environment, without paths > ")

    if encroot="$( be_has_encroot "${POOLNAME}/ROOT" )"; then
        if confirm --affirmative="Inherit" --negative="New Passphrase" "${POOLNAME}/ROOT is encrypted. Do you want to inherit encryption or set a new passphrase?"; then
            xspin zfs create ${STDOPTS[@]} "${POOLNAME}/ROOT/${set}"
        else
            create_encrypted_dataset "${POOLNAME}/ROOT/${set}" "${STDOPTS[*]}"
        fi
    else
        if confirm  --default=no "Do you want to encrypt ${POOLNAME}/ROOT/${set}"?; then
            create_encrypted_dataset "${POOLNAME}/ROOT/${set}" "${STDOPTS[*]}"
        else
            xspin zfs create ${STDOPTS[@]} "${POOLNAME}/ROOT/${set}"
        fi
    fi
    xspin zpool set bootfs="${POOLNAME}/ROOT/${set}" "${POOLNAME}"
    DATASET="${POOLNAME}/ROOT/${set}"

    zpool_export "${POOLNAME}"
    import_tmproot_pool
    mount_dataset
}

import_tmproot_pool_dataset() {
    zpool_export "${POOLNAME}"
    import_tmproot_pool
    mount_dataset
}

choose_dataset() {
    gum style "* Boot Environment Selection"
    local datasets
    datasets=$(zfs list -H | grep ${1:-^"$POOLNAME"/ROOT/} | awk '{print $1}')
    readarray -t choices <<<"$datasets"
    DATASET=$(choose "${choices[@]}" | awk '{print $1}')
    POOLNAME="${DATASET%%/*}"
}

pick_or_create_dataset() {
    gum style "* Create new ZFS Boot Environment"
    if has_roots; then
        if confirm  --affirmative="Create" --negative="Overwrite" "Create a new root dataset under $POOLNAME/ROOT or overwrite existing one?"; then
            create_dataset
        else
            EXISTING=1
            choose_dataset
            import_tmproot_pool_dataset
        fi
    else
        ensure_ROOT
        create_dataset
    fi
}

exec_chroot_script() {
    # Make sure the chroot script exists
    mkdir -p "${CHROOT_MNT}/root"
    cp "${CHROOT_SCRIPT}" "${CHROOT_MNT}/root/"

    local code=
    (set +x; exec_chroot "/root/${CHROOT_SCRIPT##*/}")
    code=$?
    ((code==0)) && rm "${CHROOT_MNT}"/root/"${CHROOT_SCRIPT##*/}"
    return $code
}

exec_chroot() {
    mount -m -t proc proc "${CHROOT_MNT}/proc"
    mount -m -t sysfs sys "${CHROOT_MNT}/sys"
    mount -m -B /dev "${CHROOT_MNT}/dev" && mount --make-slave "${CHROOT_MNT}/dev"
    mount -m -t devpts pts "${CHROOT_MNT}/dev/pts"
    if [ -d "/mnt/cache" ]; then
        mount -m -B "/mnt/cache" "${CHROOT_MNT}/tmp/cache" && mount --make-slave "${CHROOT_MNT}/tmp/cache"
    fi
    # Launch the chroot script
    local cmd=
    cmd=(chroot "${CHROOT_MNT}")
    cmd+=("$@")
    if ! "${cmd[@]}"; then
        echo "ERROR: '${cmd[*]}' failed"
        exit 1
    fi
}

install() {

    gum style "* OS Configuration"
    local passwd='' hostname=''
    passwd=$(input --value=root --prompt="Enter root password > ")
    hostname=$(input --value=proxmox --prompt="Enter hostname > ")
    mkdir -p "${CHROOT_MNT}"/root
    echo "${passwd}" > "${CHROOT_MNT}"/root/passwd.conf
    echo "${hostname}" > "${CHROOT_MNT}"/root/hostname.conf
    echo 
    if ! confirm "Ready to start installation?"; then
        echo Aborted
        exit 1
    fi

    snap="${DATASET}@prebootstrap_$(date -u +%Y%m%d-%H%M%S)"
    gum style "* Snapshot pre bootstrap: $snap"
    zfs snapshot -r "$snap"
    if (( EXISTING==1 )); then
        gum style "* Deleting existing data in ${DATASET}"
        rm --one-file-system -rf "${CHROOT_MNT:?}"/{..?*,.[!.]*,*}
    fi
    gum style "* Running bootstrap"
    if ! env INSTALLER_DIR="$INSTALLER_DIR" "${INSTALL_SCRIPT}"; then
        echo "ERROR: bootstrap script '${INSTALL_SCRIPT}' failed"
        exit 1
    fi

    gum style ""

    # Make sure the zpool information is cached
    mkdir -p "${CHROOT_MNT}/etc/zfs"
    zpool set cachefile="${CHROOT_MNT}/etc/zfs/zpool.cache" "${POOLNAME}"

    snap="${DATASET}@preinstall_$(date -u +%Y%m%d-%H%M%S)"
    gum style "* Snapshot pre install: $snap"
    zfs snapshot -r "$snap"
    gum style "* Running install"
    if ! exec_chroot_script; then
        echo "ERROR: chroot script '${CHROOT_SCRIPT}' failed"
        exit 1
    fi

    if ! env INSTALLER_DIR="$INSTALLER_DIR" "${POSTINSTALL_SCRIPT}"; then
        echo "ERROR: install script '${POSTINSTALL_SCRIPT}' failed"
        exit 1
    fi

    snap="${DATASET}@postinstall_$(date -u +%Y%m%d-%H%M%S)"
    gum style "* Snapshot post install: $snap"
    zfs snapshot -r "$snap"
    gum style ""
    gum style --bold --border double --align center \
                --width 50 --margin "1 2" --padding "0 2" "INSTALL SUCCESSFUL!"
    gum style ""
}

# unneeded for now, since its done as part of boot
mountLVM() {
    if command -v lvm >/dev/null 2>&1; then

        echo "Scanning for LVM"
        lvm vgscan -v 2>/dev/null
        lvm vgchange -a y 2>/dev/null

        lvm_volumes=$(lvm lvscan 2>/dev/null | awk '{print $2}' | tr -d "'")
        for volume in $lvm_volumes; do
            # Get the logical volume path
            lv_path=$(lvm lvdisplay "${volume}" 2>/dev/null | grep "LV Path" | awk '{print $3}')

            if [[ $(lsblk -no FSTYPE  "${lv_path}") = "swap" ]]; then
                log "Skipping swap: ${lv_path}"
                continue;
            fi

            # Get the volume path
            volume=$(echo "${lv_path}" | awk -F'/' '{for(i=3;i<=NF;i++) printf "/%s", $i}')

            # Create the mount point directory
            mkdir -p "/mnt${volume}"

            # Mount the volume
            echo "Mounting ${lv_path} on /mnt${volume}"
            mount "${lv_path}" "/mnt${volume}"
        done
    else
        echo "Skipping LVM setup, lvm not part of this image"
    fi
}

convertLVM() {
    # first we need a temp root dataset, so pick or create one
    gum style "To convert a boot drive from LVM to ZFS, this script will: " \
        "1) Create new encrypted ZFS dataset on a ZFS pool (not on the boot device)" \
        "2) Copy the LVM filesystem to this ZFS dataset" \
        "3) Partition the boot device (GPT style with 3 partitions: BIOS, ESP, ZFS)" \
        "4) Create a new ZFS ROOT pool on the boot device" \
        "5) Copy ZFS dataset to boot device, keeping encryption or replace with inherited encryption." \
        "" \
        "CAUTION: This script will only copy the root partition. If you are using LVM-thin" \
        "stop now and manually migrate them from the boot devices" \
        "" \
        "NOTE: If you are using swap on the LVM partition, this will be removed. The /etc/fstab" \
        "file will be updated to comment out the LVM mounts including swap." \
        ""
    if ! confirm "Ready to start converting LVM boot to ZFS boot?"; then
        exit 1
    fi
    if confirm "Do you need to copy LVM to temporary ZFS pool?"; then
        gum style "1) First, select a temporary ZFS pool - DO NOT select one on the boot drive" 
        select_pool

        gum style "2) Create a new ecrypted dataset: In a later step, you can keep this" \
            "encryption key or replace it with one inherited from the parent" \
            "ROOT dataset." \
            ""
        set=$(input --value=pve-1 --prompt="Enter name for dataset (on ${POOLNAME}) > ")
        create_encrypted_dataset "${POOLNAME}/${set}" "${STDOPTS[*]}"

        xspin mkdir -p "/mnt/${set}"
        xspin mount -t zfs -o zfsutil "${POOLNAME}/${set}" "/mnt/${set}"
        dataset_mnt="/mnt/${set}"

        # save the pool name for later use
        tmppool="${POOLNAME}"
        gum style "Select the LVM partition to copy:" 
        readarray -t choices <<<"$(mount -t ext4 | awk '{print $3}')"
        if (( ${#choices[@]} == 0 )); then
                gum style "No ext4 filesystems found!"
                exit 1
        fi
        filesystem=$(choose "${choices[@]}")
        files=$(find "${filesystem}" | wc -l)
        gum style "3) Copying ${filesystem} to ${dataset_mnt}" 
        gum style --faint -- "rsync -avxHAX ${filesystem}/ ${dataset_mnt}"
        rsync -avxHAX "${filesystem}/" "${dataset_mnt}" | pv -lep -s "${files}" > /dev/null

        gum style "Commenting out LVM mounts in /etc/fstab"
        xspin "sed -i 's|^/dev/pve|# Removed by zquickinit: &|' ${dataset_mnt}/etc/fstab"
        gum style "Commenting out /boot/efi mounts in /etc/fstab"
        xspin "sed -i 's|.*/boot/efi|# Removed by zquickinit: &|' ${dataset_mnt}/etc/fstab"

        gum style "Unmounting ${POOLNAME}/${set}"
        xspin zfs unmount "${POOLNAME}/${set}"
        xspin zfs set mountpoint=/ canmount=noauto "${POOLNAME}/${set}"
        
        gum style "Unmounting and deactiving all LVM volumes"
        xspin umount "${filesystem}"
        xspin lvm vgchange -an
    else
        gum style "1) First, select the temporary LVM dataset to be copied back to boot drive"
        choose_dataset .
        tmppool="${POOLNAME}"
        set="${DATASET#*/}"
    fi

    pick_or_create_pool

    if ! has_roots; then
        ensure_ROOT
    fi
    
    recv=()
    send=()
    if encroot="$( be_has_encroot "${POOLNAME}/ROOT" )"; then
        if confirm --affirmative="Inherit encryption from ${POOLNAME}/ROOT" --negative="Use existing encryption from ${tmppool}/${set}" "The target ${POOLNAME}/ROOT is encrypted. Do you want to inherit encryption or use existing?"; then
            recv+=(-o encryption=on "${STDOPTS[@]}")
            gum style "Dataset will inherit ${POOLNAME}/ROOT encryption"
            if be_is_locked "${POOLNAME}/ROOT"; then
                zfs load-key -L prompt "${encroot}"
            fi
            if encroot="$( be_has_encroot "${tmppool}/${set}" )" && be_is_locked "${tmppool}/${set}"; then
                zfs load-key -L prompt "${encroot}"
            fi
        else
            send+=(-cewp)
            gum style "Dataset will be copied with original encryption (raw)"
        fi
    else
        gum style "NOTE: ${POOLNAME}/ROOT is not encrypted"
        gum style "Dataset will be copied with original encryption"
        send+=(-cewp)
    fi
    
    if ! zfs list "${tmppool}/${set}@snapshot" > /dev/null; then
        gum style "Creating snapshot for transfer: ${tmppool}/${set}@snapshot"
        xspin zfs snapshot -r "${tmppool}/${set}@snapshot"
    else 
        gum style "Using existing snapshot: ${tmppool}/${set}@snapshot"
    fi

    size=$(zfs send -vnP ${send[@]} "${tmppool}/${set}@snapshot" | tail -n1 | awk '{print $NF}')
    log "zfs send ${send[@]} ${tmppool}/${set}@snapshot | pv -Wpbafte -s $size -i 1 | zfs receive ${recv[@]} ${POOLNAME}/ROOT/${set}"
    zfs send ${send[@]} "${tmppool}/${set}@snapshot" | pv -Wpbafte -s "$size" -i 1 | zfs receive ${recv[@]} "${POOLNAME}/ROOT/${set}"
    xspin zpool set bootfs="${POOLNAME}/ROOT/${set}" "${POOLNAME}"
    zpool_export -a

    devs=$(lsblk --nodeps -n -o path)
    for dev in ${devs}; do
        log kpartx -u "$dev" 
        kpartx -u "$dev" || :
    done
    xspin zpool import -a || :
    for dev in ${devs}; do
        # dmsetup will try to map these drives, so remove them
        if command -v dmsetup >/dev/null 2>&1; then
            dev=/$(echo "$dev" | cut -d/ -f3-)
            log dmsetup remove /dev/mapper/"${dev}"*
            dmsetup remove /dev/mapper/"${dev}"* >/dev/null 2>&1 || :
        fi
    done
    gum style "Finished! Manually remove ${tmppool}/${set} and ${tmppool}/${set}@snapshot after you verified successful boot."
}

gum style --bold --border double --align center \
        --width 50 --margin "1 2" --padding "0 2" "ZFSQuickInit Proxmox Installer"

choices=("Install Proxmox 8.x" 
    "Chroot into ZFS root dataset" 
    "Encrypt existing dataset" 
    "Convert LVM root to ZFS root dataset"
    # "Rollback to pre install and run install" 
    "Exit")

choice=$(choose "${choices[@]}")
if [[ "$choice" =~ ^Install.* ]]; then
    gum style "* Install"
    pick_or_create_pool
    pick_or_create_dataset
    install 
fi
if [[ "$choice" =~ ^Chroot.* ]]; then
    gum style "* Chroot"
    zpool import -a || :
    select_pool
    choose_dataset
    import_tmproot_pool_dataset
    exec_chroot /bin/bash
fi
if [[ "$choice" =~ ^Encrypt.* ]]; then
    gum style "* Encrypt Existing Dataset"
    zpool import -a || :
    select_pool
    zpool_export "${POOLNAME}"
    zpool import "$POOLNAME"
    encrypt_ROOT
fi
if [[ "$choice" =~ ^Convert.* ]]; then
    gum style "* Convert LVM root"
    zpool_export -a
    zpool import -a || :
    convertLVM
fi
if [[ "$choice" =~ ^Rollback.* ]]; then  
    gum style "* Rollback and install"
    zpool import -a >/dev/null 2>&1
    select_pool
    choose_dataset
    import_tmproot_pool_dataset

    gum style "Choose a snapshot to rollback before resume install"
    readarray -t choices <<<"$(zfs list -t snapshot | grep ^"$POOLNAME"/ROOT/ | awk '{print $1}')"
    set=$(choose "${choices[@]}" | awk '{print $1}')
   
    zfs rollback -r "$set"
    exec_chroot_script
fi
if [[ "$choice" =~ ^Exit.* ]]; then  
    exit 0
fi

