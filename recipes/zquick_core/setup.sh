#!/bin/bash
set -euo pipefail


help_text=$(cat <<-EOF
	# \`zquick_core\` base configuration. 
	<br>
	EOF
	)
gum format "${help_text}" " "

root_password=
if [[ -f "${zquickinit_config}/etc/zquickinit.conf" ]]; then
    root_password=$(sed -rn '/^root_password=/s/.*=(.*)/\1/p' "${zquickinit_config}/etc/zquickinit.conf")
fi

gum format "Enter root password." "* Empty value will configure no password: zfsbootmenu will start automatically on boot on all consoles." "* Non-empty value will require a login before starting zfsbootmenu." "Please note, the initramfs env is not encrypted, so it is trivial to access the initramfs env and all of its contents. Configuring a root password would only stop casual onlookers." 
echo
out=$(gum input --placeholder="password" --value="${root_password}")

mkdir -p "${zquickinit_config}/etc"
touch "${zquickinit_config}/etc/zquickinit.conf"
entry="root_password=${out}"
sed -i -r "/^root_password/{h;s/.*\$/${entry}/};\${x;/^$/{s//${entry}/;H};x}" "${zquickinit_config}/etc/zquickinit.conf"
