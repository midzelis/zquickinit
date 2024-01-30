#!/bin/bash
set -euo pipefail

input() {
    local code=0
    var=$(gum input "$@") || code=$?
    ((code>0)) && exit $code
    echo "$var"
} 

help_text=$(cat <<-EOF
	# \`zquick_hostname\` 
	Enter the hostname for this system
	<br>
	EOF
	)
gum format "${help_text}" " "
value=
set +e
[[ -f "${zquickinit_config}/etc/hostname" ]] && read -r value < "${zquickinit_config}/etc/hostname"
set -e
name=$(input --value zquickinit --placeholder hostname --value "${value}")
if [[ -n $name ]]; then
	echo "$name" > "${zquickinit_config}/etc/hostname"
else
	echo "zquickinit" > "${zquickinit_config}/hostname"
fi

