#!/bin/bash

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

ZBM_ROOT=/LUNA/ALPHA/PERSONAL/git/zfsbootmenu
SRC_ROOT=${SRC_ROOT:-"$(dirname "$DIR")"}
RECIPES_ROOT=${RECIPES_ROOT:-${SRC_ROOT}/recipes}
RECIPE_BUILDER="midzelis/ez-zfsbootmenu-builder"
DOCKER=docker # or podman or buildah bud

# This will build the main docker image
# shellcheck disable=SC2317
init() {
	if which yq-go >/dev/null; then
		yg=yq-go
	elif which yq >/dev/null; then
		yg=yq
	else
		echo "yq (or yq-go) is required"
		exit 1
	fi
	( 
		packages=()
		# shellcheck disable=SC2016
		mapfile -t -O "${#packages[@]}" packages < <($yg eval-all '. as $item ireduce ({}; . *+ $item) | (... | select(type == "!!seq")) |= unique | .xbps-packages[] | .. style=""' "$RECIPES_ROOT"/*/recipe.yaml)

		echo "Building with Packages: ${packages[*]}"
		cd "$SRC_ROOT/build" || exit 1;
		cmd=("$DOCKER" build . 
			-t "$RECIPE_BUILDER" 
			--build-arg KERNELS=linux6.1 
			--build-arg "PACKAGES=${packages[*]}" 
			--progress=plain)
		echo "Build command: ${cmd[*]}"
		"${cmd[@]}"
		$DOCKER image ls "$RECIPE_BUILDER"
	)
}

# shellcheck disable=SC2317
create_tailscale_node() {
	mkdir -p state ; docker run -it -e TS_EXTRA_ARGS=--ssh -e TS_STATE_DIR=/state -v "$(pwd)"/state:/state tailscale/tailscale ; mv state/tailscaled.state "$(pwd)" ; rm -rf state
}

# This command is designed to be ONLY run from inside the running container
# shellcheck disable=SC2317
_internal_run() { 
	if [[ $@ =~ interactive ]]; then
		interactive=$1
	fi

	[[ -z $RUNNING_IN_CONTAINER ]] && echo _internal-run must be run from inside container && exit 1
	if [[ ! -d /input ]]; then
		echo "Downloading latest ez-zfsbootmenu-builder"
		git clone --quiet --depth 1 https://github.com/midzelis/ez-zfsbootmenu-builder.git /input
	fi
	if [[ ! -d /zbm ]]; then
		echo "Downloading latest zfsbootmenu"
		git clone --quiet --depth 1 https://github.com/zbm-dev/zfsbootmenu.git /zbm
	fi

	# echo "Merging configs for recipes"
	hooks=()
	hook_dirs=()

	system_hooks=(base udev modconf block filesystems keyboard zfsbootmenu strip)

	recipes=()
	for dir in /input/recipes/*/initcpio; do
		[[ ! -d $dir ]] && continue
		hook_dirs+=("${dir#"/recipes"}")
		recipes+=("$(basename "$(dirname "$dir")")")
	done

	if [[ -n "$interactive" ]]; then 

		if which yq-go >/dev/null; then
			yg=yq-go
		elif which yq >/dev/null; then
			yg=yq
		else
			echo "yq (or yq-go) is required"
			exit 1
		fi

		help=
		for recipe in /input/recipes/*/recipe.yaml; do
			[[ ! -r $recipe ]] && continue
			name=$(basename "$(dirname "$recipe")")
			help+=" - \`$name\` - $(yq-go e '.help ' "$recipe")\n"
		done

		IFS=$'\n' sorted=($(sort <<<"${recipes[*]}"))
		unset IFS
		help_text=$(cat <<-EOF
			**Welcome to EZ ZFSBootMenu (interactive mode)**
			# Which recipes do you want to include in this build?
			$(printf "%b" "$help")
			<br>
			EOF
			)
		# echo -n "${help_text}"
		gum format "${help_text}" " "
		selected=$(IFS=, ; echo "${sorted[*]}")
		recipes=($(gum choose ${sorted[*]} --height=20 --no-limit --selected="$selected"))
		
		help_text=$(cat <<-EOF
			# Which mkcpio system hooks would you like to include?
			You probably want all of these, especially zfsbootmenu ;-)
			<br>
			EOF
			)
		gum format "${help_text}" " "

		IFS=$'\n' sorted=($(sort <<<"${system_hooks[*]}"))
		unset IFS
		selected=$(IFS=, ; echo "${sorted[*]}")
		system_hooks=($(gum choose ${sorted[*]} --no-limit --selected="$selected"))

		# do some re-ordering
		if [[ ${system_hooks[@]} =~ strip ]]; then
			strip_sel=1
		fi
		if [[ ${system_hooks[@]} =~ zfsbootmenu ]]; then
			zfsbootmenu_sel=1
		fi

		for recipe in "${recipes[@]}"; do
			[[ ! -x /input/recipes/$recipe/setup.sh ]] && continue
			/input/recipes/"$recipe"/setup.sh
		done

	else
		strip_sel=1
		zfsbootmenu_sel=1
	fi

	# need to reorder strip/zfsbootmenu
	system_hooks=( ${system_hooks[@]/strip} ) 
	system_hooks=( ${system_hooks[@]/zfsbootmenu} ) 

	# first system hooks
	hooks+=(${system_hooks[@]})
	# then zfsbootmenu
	[[ -n $zfsbootmenu_sel ]] && hooks+=("zfsbootmenu")
	# the recipes
	hooks+=(${recipes[@]})
	# strip goes last
	[[ -n $strip_sel ]] && hooks+=("strip")

	build_time=$(date -u +"%Y-%m-%d_%H%M%S");

	mkdir -p /tmp
	rm -rf /tmp/*
	cat > /tmp/mkinitcpio.conf <<-EOF
		MODULES=()
		BINARIES=()
		FILES=()
		HOOKS=(${hooks[@]})
		COMPRESSION=(zstd)
		COMPRESSION_OPTIONS=(-9 --long)
		
		recipes_root="/input"

		zfsbootmenu_module_root="/zbm/zfsbootmenu"
		zfsbootmenu_early_setup=()
		zfsbootmenu_setup=()
		zfsbootmenu_teardown=()
		EOF

	echo "zfsbootmenu ro loglevel=4 zbm.autosize=0" > /tmp/cmdline

	cat > /tmp/os-release <<-EOF
		NAME="ZFSBootMenu; Void Linux"
		ID="zfsbootmenu"
		ID_LIKE="void"
		PRETTY_NAME="ZFSBootMenu (built on $build_time)"
		HOME_URL="https://github.com/zbm-dev/zfsbootmenu"
		DOCUMENTATION_URL="https://zfsbootmenu.org/"
		ANSI_COLOR="0;38;2;71;128;97"
		EOF

	hook_dirs+=("/zbm/initcpio")
	hook_dirs+=("/usr/lib/initcpio")
	hookdirs+=("${hook_dirs[@]/#/--hookdir }")

	output_img=/output/ez-zfsbootmenu-$build_time.img
	output_uki="/output/ez-zbm-$build_time.efi" 
	mkinitcpio --config /tmp/mkinitcpio.conf ${hookdirs[*]} \
		--kernel 6.1.51_1 \
		--osrelease /tmp/os-release \
		--cmdline /tmp/cmdline \
		--generate "$output_img" \
		-U "$output_uki" 
	cp /boot/vmlinuz-6.1.51_1 /output/vmlinuz-6.1.51_1
	ls -1 /output/*.img | sort -r | tail -n +4 | xargs -r rm
	ls -1 /output/*.efi | sort -r | tail -n +4 | xargs -r rm
}

# shellcheck disable=SC2317
ez_zbm() {
	cmd=("$DOCKER" run --rm -it 
		-e GENERATE_RAW_DISK_IMG="$GENERATE_RAW_DISK_IMG"
		-v "$SRC_ROOT/build/bake.sh:/bake.sh" 
		-v "$SRC_ROOT:/input" 
		-v "$ZBM_ROOT:/zbm" 
		-v "$SRC_ROOT/output:/output" 
		${1:-}
		"$RECIPE_BUILDER" ${2:-})

	"${cmd[@]}"
}
# shellcheck disable=SC2317
ez_zbm_debug() {
	ez_zbm --entrypoint=/bin/bash -i
}

cmds=(ez_zbm ez_zbm_debug init create_tailscale_node)

cmd=${1:-}
shift
if [ -n "$cmd" ] && [[ " ${cmds[*]} " =~ $cmd ]]; then
	$cmd "$@"
	exit $?
else	
	_internal_run "$cmd" "$@"
	exit $?
fi
