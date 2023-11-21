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
name=$(input --value zquickinit --placeholder hostname)
[[ -n $name ]] && echo "$name" > /etc/hostname ||  echo "zquickinit" > /etc/hostname

