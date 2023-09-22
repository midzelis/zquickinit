#!/bin/bash

help_text=$(cat <<-EOF
	# \`ez_webttyd\` can send your phone a push notification with a link to unlock. 
	Please enter your pushoever USER token:
	<br>
	EOF
	)
gum format "${help_text}" " "
user_token=$(gum input)
mkdir -p /var/lib/ez_webttyd
echo "PUSHOVER_USER_KEY=$user_token" >> /var/lib/ez_webttyd/ez_webttyd_pushover.conf
help_text=$(cat <<-EOF
	Please enter your pushoever APP token:
	<br>
	EOF
	)
gum format "${help_text}" " "
app_token=$(gum input)
echo "PUSHOVER_APP_TOKEN=$app_token" >> /var/lib/ez_webttyd/ez_webttyd_pushover.conf