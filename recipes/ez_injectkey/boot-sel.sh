#!/bin/bash

set -x
if [ ! -d /run/ez_injectkey ] || [[ ! "$(ls /run/ez_injectkey)" ]]; then
    exit 0
fi

sources=(
  /lib/profiling-lib.sh
  /etc/zfsbootmenu.conf
  /lib/zfsbootmenu-core.sh
  /lib/kmsg-log-lib.sh
)

for src in "${sources[@]}"; do
  # shellcheck disable=SC1090
  if ! source "${src}" > /dev/null 2>&1 ; then
    echo -e "\033[0;31mWARNING: ${src} was not sourced; unable to proceed\033[0m"
    exit 1
  fi
done

fs=$ZBM_SELECTED_BE
kernel=$ZBM_SELECTED_KERNEL
initramfs=$ZBM_SELECTED_INITRAMFS
hook_envs=(
    ZBM_SELECTED_BE="${fs}"
    ZBM_SELECTED_KERNEL="${kernel}"
    ZBM_SELECTED_INITRAMFS="${initramfs}"
)

tput cnorm
tput clear

if ! mnt=$( mount_zfs "${fs}" ); then
    exit 1
fi

cli_args="$( load_be_cmdline "${fs}" )"
root_prefix="$( find_root_prefix "${fs}" "${mnt}" )"
initrd="${mnt}${initramfs}"

mkdir -p /tmp
mount -t tmpfs tmpfs /tmp
cp "${initrd}" /tmp
initrd="/tmp/$(basename "${initrd}")"
find /run/ez_injectkey -depth -print | pax -s "/\/run\/ez_injectkey//" -x sv4cpio -wd | zstd >> "${initrd}"

bash
if ! output="$( kexec -a -l "${mnt}${kernel}" \
    --initrd="${initrd}" \
    --command-line="${root_prefix}${fs} ${cli_args}" 2>&1 )"
then
    zerror "unable to load ${mnt}${kernel} and ${mnt}${initramfs} into memory"
    zerror "${output}"
    umount "${mnt}"
    timed_prompt -d 10 \
        -m "$( colorize red 'Unable to load kernel or initramfs into memory' )" \
        -m "$( colorize orange "${mnt}${kernel}" )" \
        -m "$( colorize orange "${mnt}${initramfs}" )"
    emergency_shell "oh no"
else
    if zdebug ; then
        zdebug "loaded ${mnt}${kernel} and ${mnt}${initramfs} into memory"
        zdebug "kernel command line: '${root_prefix}${fs} ${cli_args}'"
        zdebug "${output}"
    fi
fi

umount "${mnt}"

while read -r _pool; do
if is_writable "${_pool}"; then
    zdebug "${_pool} is read/write, exporting"
    export_pool "${_pool}"
fi
done <<<"$( zpool list -H -o name )"

# Run teardown hooks, if they exist
env "${hook_envs[@]}" /libexec/zfsbootmenu-run-hooks "teardown.d"

if ! output="$( kexec -e -i 2>&1 )"; then
    zerror "kexec -e -i failed!"
    zerror "${output}"
    timed_prompt -d 10 \
        -m "$( colorize red "kexec run of ${kernel} failed!" )"
    exit 1
fi
