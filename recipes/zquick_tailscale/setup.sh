#!/bin/bash
gum format "# \`zquick_tailscale\` configures tailscale for remote pool unlock on reboots." "" "Enter the contents of tailscale.state file." "" "To create one, run \`zquickinit.sh tailscale\` or install a new tailscale in a VM or container and copy the contents of /var/lib/tailscale/tailscaled.state into this textbox" "" "Empty string will leave unconfigured." ""
cols="$(tput cols 2>/dev/null)"
cols=$((cols - 5))
out=$(gum write --width="$cols" --placeholder="tailscale state")
if [[ -n $out ]]; then
	mkdir -p "${zquickinit_config}/var/lib/tailscale"
	echo "$out" >"${zquickinit_config}/var/lib/tailscale/tailscaled.state"
fi
