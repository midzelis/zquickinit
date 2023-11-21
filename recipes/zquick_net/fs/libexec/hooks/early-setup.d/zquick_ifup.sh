#!/bin/bash
(exec setsid /zquick/libexec/net/ifup.sh &)

# > (exec setsid getty -n -L -l "/usr/sbin/tmux -2 -u a 0" /dev/tty0 &)

