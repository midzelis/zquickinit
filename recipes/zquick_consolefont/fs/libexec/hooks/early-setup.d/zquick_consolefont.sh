#!/bin/bash

# Ensure that control_term is not a serial console
tty_re='/dev/tty[0-9]'
[[ ${control_term} =~ ${tty_re} ]] || exit 0

setfont ter-v16b
