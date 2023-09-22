#!/bin/bash

help_text=$(cat <<-EOF
	Enter the name of this system
	<br>
	EOF
	)
gum format "${help_text}" " "
name=$(gum input)
echo "$name" > /etc/hostname