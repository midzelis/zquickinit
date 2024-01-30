#!/bin/bash
set -euo pipefail

existing_userkey=
existing_apptoken=
if [[ -f "${zquickinit_config}/etc/zquickinit.conf" ]]; then
	existing_userkey=$(sed -n 's/^PUSHOVER_USER_KEY=//p' "${zquickinit_config}/etc/zquickinit.conf")
	existing_apptoken=$(sed -n 's/^PUSHOVER_APP_TOKEN=//p' "${zquickinit_config}/etc/zquickinit.conf")
fi

help_text=$(cat <<-EOF
	# \`zquick_ttyd\` can send your phone a push notification with a link to unlock when ZQuickInit boots. 
	If you'd like to enable this function, please answer the following questions. 
	Pushover USER token:
	<br>
	EOF
	)
gum format "${help_text}" " "
user_token=$(gum input --value "${existing_userkey}")
if [[ -n "${user_token}" ]]; then
	mkdir -p "${zquickinit_config}/etc"

	help_text=$(cat <<-EOF
		Pushover APP token:
		<br>
		EOF
		)
	gum format "${help_text}" " "
	
	app_token=$(gum input --value "${existing_apptoken}")

	if [[ -n "${app_token}" ]]; then
		mkdir -p "${zquickinit_config}/etc"
		touch "${zquickinit_config}/etc/zquickinit.conf"
		entry="PUSHOVER_USER_KEY=$user_token"
		sed -i -r "/^PUSHOVER_USER_KEY/{h;s/.*\$/${entry}/};\${x;/^$/{s//${entry}/;H};x}" "${zquickinit_config}/etc/zquickinit.conf"
		entry="PUSHOVER_APP_TOKEN=$app_token"
		sed -i -r "/^PUSHOVER_APP_TOKEN/{h;s/.*\$/${entry}/};\${x;/^$/{s//${entry}/;H};x}" "${zquickinit_config}/etc/zquickinit.conf"
	fi
fi
