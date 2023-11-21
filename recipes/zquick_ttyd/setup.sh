#!/bin/bash
set -euo pipefail
help_text=$(cat <<-EOF
	# \`zquick_ttyd\` can send your phone a push notification with a link to unlock when ZQuickInit boots. 
	If you'd like to enable this function, please answer the following questions. 
	Pushover USER token:
	<br>
	EOF
	)
gum format "${help_text}" " "
user_token=$(gum input)
if [[ -n "${user_token}" ]]; then
	mkdir -p /zquick/etc
	
	help_text=$(cat <<-EOF
		Pushover APP token:
		<br>
		EOF
		)
	gum format "${help_text}" " "
	app_token=$(gum input)

	if [[ -n "${app_token}" ]]; then
		echo "PUSHOVER_USER_KEY=$user_token" > /zquick/etc/ttyd_pushover.conf
		echo "PUSHOVER_APP_TOKEN=$app_token" >> /zquick/etc/ttyd_pushover.conf
	fi
fi

