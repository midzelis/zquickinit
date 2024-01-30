#!/bin/bash

# shellcheck disable=SC1091
. /zquick/libexec/utils.sh

qinitlog "Initializing ZFSBootMenu" 
sed -ri '/zfsbootmenu-init/ s/(.*)/# disabled-by-zquick: \1/'  /lib/zfsbootmenu-preinit.sh

for hook in /lib/zfsbootmenu-parse-commandline.sh /lib/zfsbootmenu-preinit.sh; do
    # shellcheck disable=SC1090
    [ -r "${hook}" ] && . "${hook}" && continue
    qinitlog "ERROR: failed to load hook \"${hook}\""
done