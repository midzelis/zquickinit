#!/bin/bash

name="${0##*/}"
log() {
   logger -p user.notice -t "${name}" "$1"
}

cd /usr/share/zfsbootmenu/fonts/ || exit 0
#fonts=ter-v32b ter-v28b ter-v24b ter-v20b ter-v14b ter-v12n
# just use v20b for now
fonts=ter-v20b
for font in $fonts; do
    [ -f "${font}.psf" ] && setfont "${font}" >/dev/null 2>&1
    # need a little time to process
    sleep .1

    cols=$(LC_ALL=C stty -a  | grep columns | sed -e 's/.*columns //' -e 's/;.*$//' -e 's/= //')
    rows=$(LC_ALL=C stty -a  | grep columns | sed -e 's/.*rows //' -e 's/;.*$//' -e 's/= //')
    # 110 columns is the current minimum to show both the sort key and a note on the snapshot screen
    if ((cols>110)); then
        log "set font to ${font}, screen is ${cols}x${rows}"
        break
    fi
done