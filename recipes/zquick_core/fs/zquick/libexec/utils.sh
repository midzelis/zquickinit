#!/bin/bash

# this will prevent the command stout from being buffered
unbuffer() {
   /usr/sbin/script -q /dev/null sh -c "${1}"
}

name="${0##*/}"
ts=1
qinitlog() {
    logger -p user.notice -t "${name}" "$1"
    [[ -n $ts ]] && printf "% (%b %d %H:%M:%S)T [ZquickInit] %s\n" -1 "$1"
    [[ -z $ts ]] && printf "[ZquickInit] %s\n" "$1"
}

qinitlog_start() {
    logger -p user.notice -t "${name}" "$1"
    [[ -n $ts ]] && printf "% (%b %d %H:%M:%S)T [ZquickInit] %s" -1 "$1"
    [[ -z $ts ]] && printf "[ZquickInit] %s" "$1"
}

qinitlog_end() {
    logger -p user.notice -t "${name}" "$1"
    printf "%s\n" "$1"
}

qlog() {
    logger -p user.notice -t "${name}" "$1"
    [[ -n $ts ]] && printf "% (%b %d %H:%M:%S)T %s" -1 "$1"
    [[ -z $ts ]] && printf "%s" "$1"
}

qdebug() {
    logger -p user.notice -t "${name}" "$1"
}
