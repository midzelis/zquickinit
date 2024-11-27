#!/bin/bash
set -euo pipefail

confirm() {
	local code=
	gum confirm "$@" && code=$? || code=$?
	((code > 2)) && exit $code
	return $code
}

help_text=$(
	cat <<-EOF
		# \`zquick_sshd\` sets up sshd server. 
		<br>
	EOF
)
gum format "${help_text}" " "

cols="$(tput cols 2>/dev/null)"
cols=$((cols - 5))

msg=
value=
if [[ -f "${zquickinit_config}/etc/ssh/sshd_config" ]]; then
	IFS= read -rd '' value <"${zquickinit_config}/etc/ssh/sshd_config" || :
else
	msg="(Autogenerated default configuration to allow root login)"
	IFS= read -rd '' value <<-EOF || :
		Port 22
		PermitRootLogin yes
		PubkeyAuthentication yes
		IgnoreUserKnownHosts yes
		MaxAuthTries 10
	EOF
fi
echo
gum format "Edit sshd_config. ${msg}" "See https://man.openbsd.org/sshd_config" "" "Empty string will leave unconfigured."
echo
out=$(gum write --char-limit=0 --height=10 --width="$cols" --placeholder="sshd_config" --value="${value}")
if [[ -n $out ]]; then
	mkdir -p "${zquickinit_config}/etc/ssh"
	echo "$out" >"${zquickinit_config}/etc/ssh/sshd_config"
else
	gum format "No SSHd configuration, SSHd server will not start until configuration is injected into image."
fi

count=
if [[ -d "${zquickinit_config}/etc/ssh" ]]; then
	count=$(find "${zquickinit_config}"/etc/ssh/ssh_host* | wc -l)
fi
if ((count > 0)); then
	if confirm --default="no" "Found existing sshd host keys in ${zquickinit_config}/etc/ssh. Overwrite with autogenerated sshd keys?"; then
		find "${zquickinit_config}"/etc/ssh/ssh_host* -delete
		ssh-keygen -A -f "${zquickinit_config}"
	fi
elif confirm "Enable sshd and autogenerate host keys?"; then
	ssh-keygen -A -f "${zquickinit_config}"
fi

value=
msg=
if [[ -f "${zquickinit_config}/root/.ssh/authorized_keys" ]]; then
	set +e
	while IFS= read -r line || [ -n "$line" ]; do
		value="${value}${line}"$'\n'
	done <"${zquickinit_config}/root/.ssh/authorized_keys"
	set -e
fi
gum format "Edit root authorized_keys." "See [Keys Format](https://man.openbsd.org/sshd.8#AUTHORIZED_KEYS_FILE_FORMAT)" "" "Empty string will leave unconfigured." ""
out=$(gum write --char-limit=0 --height=10 --width="$cols" --placeholder="ssh-ed25519 AAAA..." --value="${value}")
if [[ -n $out ]]; then
	mkdir -p "${zquickinit_config}/root/.ssh"
	echo "$out" >"${zquickinit_config}/root/.ssh/authorized_keys"
	chmod 644 "${zquickinit_config}/root/.ssh/authorized_keys"
fi
