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

[ -z "${INSTALLER_DIR}" ] && echo "env var INSTALLER_DIR must be set" && exit 1

debootstrap() {

  : > "${DEBOOTSTRAP_STYLE:=TAR}"

  if ! DEBROOT="$( mktemp -d )"; then
    echo "ERROR: unable to create working directory for debootstrap"
    exit 1
  fi

  export DEBROOT

  cleanup() {
    ret=$?
    if [ -n "${DEBROOT:-}" ]; then
      rm -rf "${DEBROOT:-}"
      unset DEBROOT
    fi

    exit $ret
  }

  trap cleanup EXIT INT TERM

  get_from_git() {
    (cd "${DEBROOT}" && \
      git clone --depth=1 https://salsa.debian.org/installer-team/debootstrap.git)

    if [ ! -x "${DEBROOT}/debootstrap/debootstrap" ]; then
      echo "ERROR: unable to find local clone of debootstrap"
      exit 1
    fi
  }

  get_from_tar() {
    (cd "${DEBROOT}" && \
      wget https://ftp.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.137.tar.gz && \
      tar zxf debootstrap_1.0.137.tar.gz
    )
  }

  DEBARCH=
  case "$(uname -m)" in
    x86_64) DEBARCH=amd64 ;;
    i686) DEBARCH=i386 ;;
    aarch64) DEBARCH=arm64 ;;
    armv7l) DEBARCH=armhf ;;
    *) ;;
  esac

  if [ -z "${DEBARCH}" ]; then
    echo "ERROR: unable to find supported architecture"
    exit 1
  fi

  if [[ ${DEBOOTSTRAP_STYLE} == "GIT" ]]; then
    get_from_git
    export DEBOOTSTRAP_DIR="${DEBROOT}/debootstrap"
    "${DEBOOTSTRAP_DIR}/debootstrap" --arch="${DEBARCH}" "$@"
  elif [[ ${DEBOOTSTRAP_STYLE} == "TAR" ]]; then
    get_from_tar
    export DEBOOTSTRAP_DIR="${DEBROOT}/debootstrap"
    "${DEBOOTSTRAP_DIR}/debootstrap" --arch="${DEBARCH}" "$@"
  fi

}

SUITE="${RELEASE:-bookworm}"
MIRROR="http://ftp.us.debian.org/debian/"

DBARGS=("--include=ca-certificates,wget")
if [ -d "/mnt/cache" ]; then
  DBARGS+=( "--cache-dir=/mnt/cache" )
fi

debootstrap "${DBARGS[@]}" "${SUITE}" "${CHROOT_MNT}" "${MIRROR}"

echo "done with boostrap"
cp /etc/hostid "${CHROOT_MNT}/etc/"
cp /etc/resolv.conf "${CHROOT_MNT}/etc/"

if [ -d "/mnt/cache" ]; then
  _aptdir="${CHROOT_MNT}/etc/apt/apt.conf.d"
  mkdir -p "${_aptdir}"
  echo "Dir::Cache::Archives /tmp/cache;" > "${_aptdir}/00cache"
fi
