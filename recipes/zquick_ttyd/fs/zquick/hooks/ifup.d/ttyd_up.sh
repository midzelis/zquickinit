#!/bin/bash

# shellcheck disable=SC1091
. /zquick/libexec/utils.sh

qinitlog_start "ttyd.sh"
(exec setsid /zquick/libexec/ttyd/ttyd.sh &)
qinitlog_end "[ OK ]"
