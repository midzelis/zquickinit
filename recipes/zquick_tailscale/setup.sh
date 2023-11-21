#!/bin/bash
help_text=$(cat <<-EOF
	# \`zquick_tailscale\` requires a tailsaled.state. 
	<br>
	EOF
	)
gum format "${help_text}" "Press ctrl-d to finish. Empty string will leave unconfigured."
cols="$( tput cols 2>/dev/null )"
cols=$((cols-5))
out=$(gum write --width="$cols" --placeholder="tailscale state")
if [[ -n $out ]]; then
	mkdir -p /var/lib/tailscale
	echo "$out" > /var/lib/tailscale/tailscaled.state
fi

