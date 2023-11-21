#!/bin/bash
# vim: softtabstop=2 shiftwidth=2 expandtab
set -euo pipefail

: "${DEBUG:=}"
# If we are debugging, enable trace
if [ "${DEBUG,,}" = "true" ]; then
  set -x
fi

if [ -z "${CHROOT_MNT}" ] || [ ! -d "${CHROOT_MNT}" ]; then
  echo "ERROR: chroot mountpoint must be specified and must exist"
  exit 1
fi

if [ -d "/mnt/cache" ]; then
  _aptdir="${CHROOT_MNT}/etc/apt/apt.conf.d"
  mkdir -p "${_aptdir}"
  rm "${_aptdir}/00cache"
fi

