#!/bin/bash

set -x

source /etc/zquickinit.conf

if [ ! -d /dev/pts ]; then
    mkdir -p /dev/pts
    mount -t devpts devpts /dev/pts
fi
function attach {
    # if ! tmux -2 -u new-session -A -s ZFSBootMenu /libexec/zfsbootmenu-init; then
    export HOME=/root
    if ! tmux -2 -u new-session -A -s ZFSBootMenu /libexec/zfsbootmenu-init; then
        echo "tmux exited badly"
        exec /bin/bash
    fi
}
# prevent badness if detaching tmux from real term
trap attach EXIT
while true; do
    sleep 2
    echo "waiting"
    attach
done

# > (exec setsid getty -n -L -l "/usr/sbin/tmux -2 -u a 0" /dev/tty0 &)