#!/bin/bash

fs="$ZBM_LOCKED_FS"
encroot="$ZBM_ENCRYPTION_ROOT"

sources=(
  /lib/profiling-lib.sh
  /etc/zfsbootmenu.conf
  /lib/zfsbootmenu-core.sh
  /lib/kmsg-log-lib.sh
)

for src in "${sources[@]}"; do
  # shellcheck disable=SC1090
  if ! source "${src}" > /dev/null 2>&1 ; then
    echo -e "\033[0;31mWARNING: ${src} was not sourced; unable to proceed\033[0m"
    exit 1
  fi
done

# if lazy_tailscale is installed, start it up
if [ ! -f /var/run/ez_ifup ] && which ez_ifup >dev/null; then
    ez_ifup
    touch /var/run/ez_ifup
fi

keyformat=$( zfs get -H -o value keyformat "${encroot}" )
[[ ! "$keyformat" == passphrase ]] && exit 0

# If something goes wrong discovering key location, just prompt
if ! keylocation="$( zfs get -H -o value keylocation "${encroot}" )"; then
    zdebug "failed to read keylocation on ${encroot}"
    keylocation="prompt"
fi

if [[ $keylocation = file://* ]]; then
    gum style --bold --border rounded --align center \
            --width 50 --margin "1 2" --padding "2 4" "Found encrypted filesystem" "" "$fs" "encryptionroot=$encroot"

    # shellcheck disable=SC2034
    for i in $(seq 1 3); do
        keyinput=$(gum input \
            --placeholder="Type your key" \
            --header="Enter passphrase for $encroot:" \
            --password \
            --timeout=10s)
        if [ -z "$keyinput" ]; then
            printf "\n\n"
            exit 1
        fi
        echo "$keyinput" | zfs load-key -L prompt "${encroot}"
        ret=$?
        printf "\n\n"
        if (( ret == 0 )); then
            key="${keylocation#file://}"
            key="${key#/}"
            keydir=$(dirname "$key")
            keyfile=$(basename "$key")
            mkdir -p "/run/ez_injectkey/$keydir"
            if [[ -e "/run/ez_injectkey/$keydir/$keyfile" ]]; then
                if ! gum confirm "The keylocation $keylocation is already in use. Overwrite?" --default="no"; then exit 1; fi
            fi
            echo "$keyinput" > "/run/ez_injectkey/$keydir/$keyfile"
            exit 0
        fi
    done
fi

exit 1
