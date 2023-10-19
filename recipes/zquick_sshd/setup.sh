#!/bin/bash
set -euo pipefail

confirm() {
    local code=
    gum confirm "$@" && code=$? || code=$? 
    ((code>2)) && exit $code
    return $code
}

help_text=$(cat <<-EOF
	# \`zquick_sshd\` sets up sshd server. 
	<br>
	EOF
	)
gum format "${help_text}" " "

if confirm "Enable sshd and autogenerate host keys?"; then
	ssh-keygen -A
	mkdir -p /root/.ssh
	gum format "Enter authorized user's public keys (will be stored in /root/.ssh/authorized_keys)." "Press ctrl-d to finish. Empty string will leave unconfigured."
	cols="$( tput cols 2>/dev/null )"
	cols=$((cols-5))
	out=$(gum write --width="$cols" --placeholder="ssh-ed25519 AAAA...")
	if [[ -n $out ]]; then
		echo "$out" > /root/.ssh/authorized_keys
	fi
fi
