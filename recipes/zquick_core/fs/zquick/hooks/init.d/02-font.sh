#!/bin/bash
# shellcheck disable=SC1091
. /zquick/libexec/utils.sh

qinitlog "Setting font" 

fonts=/usr/share/zfsbootmenu/fonts/ter-v20b
for font in $fonts; do
    [ -f "${font}.psf" ] && setfont "${font}" >/dev/null 2>&1
    # need a little time to process
    sleep .1

    cols=$(LC_ALL=C stty -a  | grep columns | sed -e 's/.*columns //' -e 's/;.*$//' -e 's/= //')
    rows=$(LC_ALL=C stty -a  | grep columns | sed -e 's/.*rows //' -e 's/;.*$//' -e 's/= //')
    # 110 columns is the current minimum to show both the sort key and a note on the snapshot screen
    if ((cols>110)); then
        qinitlog "Set font to ${font}, screen is ${cols}x${rows}"
        break
    fi
done

