#!/bin/bash
help_text=$(cat <<-EOF
	# \`ez_tailscale\` requires a tailsaled.state. Enter it now, ctrl-d to finish. 
	<br>
	EOF
	)
gum format "${help_text}" " "
gum write > /var/lib/tailscale/tailscaled.state