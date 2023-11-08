#!/usr/bin/env bash
set -euo pipefail

if [ "${BASH_VERSINFO:-0}" -lt 5 ]; then
	echo "Bash version 5 or greater required"
	if [[ "$OSTYPE" == "darwin"* ]]; then
		echo "On MacOS, use brew to install bash"
		echo "Note: brew uses /usr/local/bin on Intel, and /opt/homebrew/bin on Apple"
	fi
	exit 1
fi

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
SOURCE=${BASH_SOURCE[0]:-}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done



DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
SRC_ROOT=${DIR}
ZBM_ROOT=${SRC_ROOT}/../zfsbootmenu
RECIPES_ROOT=${RECIPES_ROOT:-${SRC_ROOT}/recipes}
RECIPE_BUILDER="ghcr.io/midzelis/zquickinit"
ZQUICKEFI_URL="https://github.com/midzelis/zquickinit/releases/latest"
# if empty, use latest release tag
ZBM_TAG=
# if specified, takes precedence over ZBM_TAG
ZBM_COMMIT_HASH=f23fc698c42220593a011cf6b58a0220452225f0
KERNEL_BOOT=
ENGINE=
OBJCOPY=
FIND=
YG=
NOASK=0
DEBUG=0
ENTER=0
RELEASE=0
GITHUBACTION=0
SSHONLY=
NOQEMU=
DRIVE1=1
DRIVE1_GB=8
DRIVE2=0
DRIVE2_GB=3

CLEANUP=()

# shellcheck disable=SC2317
cleanup() {
	ret=$?
	for c in "${CLEANUP[@]}"; do
		if [[ -e "${c}" ]]; then
			rm -rf "${c}"
		fi
	done
	exit $ret
}

trap cleanup EXIT INT TERM

tmpdir() {
	# shellcheck disable=SC2155
	local tmp="$( mktemp -d )" || exit 1
	CLEANUP+=("${tmp}")
	echo "${tmp}"
}

check() {
	if [[ $1 == docker || $1 == podman ]]; then
		if command -v docker &>/dev/null; then
			ENGINE=docker
			return 0
		elif command -v podman  &>/dev/null; then
			ENGINE=podman
			return 0
		fi
		if [[ -z "$ENGINE" ]]; then
			echo "docker or podman not found."
			echo "see https://docs.docker.com/engine/install/ or"
			echo "https://podman.io/docs/installation"
			exit 1
		fi
	fi
	if [[ $1 == yq ]]; then
		if which yq-go >/dev/null; then
			YG=yq-go
			return 0
		elif which yq >/dev/null; then
			YG=yq
			return 0
		else
			echo "yq (or yq-go) is required"
			echo "try wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"
			exit 1
		fi
	fi
	if [[ $1 == objcopy && -z "${OBJCOPY}" ]]; then
		if [[ "$OSTYPE" == "darwin"* ]]; then
			OBJCOPY=$(find /opt/homebrew /usr/local -name gobjcopy -print -quit 2>/dev/null || true)
			if [[ -z ${OBJCOPY} ]]; then
				echo "$1 not found. usually part of the $2 package"
				echo "On MacOS, use brew to install binutils"
				echo "Note: brew uses /usr/local/bin on Intel, and /opt/homebrew/bin on Apple"
				exit 1
			fi
			return 0
		else
			OBJCOPY=objcopy
		fi
	fi
	if ! command -v "$1" &>/dev/null; then
		echo "$1 not found. usually part of the $2 package"
		exit 1
	fi
	if [[ $1 == find ]] && [[ -z "${FIND}" ]]; then
		if command -v gfind &>/dev/null; then
			FIND="gfind"
		else 
			FIND="find"
		fi
		if [[ ! "$(${FIND} . --version 2>&1 | head -n1)" == *GNU* ]]; then
			echo "find must be GNU flavored. Update or install findutils package. "
			if [[ "$OSTYPE" == "darwin"* ]]; then
				echo "On MacOS, use brew to install findutils"
				echo "Note: brew uses /usr/local/bin on Intel, and /opt/homebrew/bin on Apple"
			fi
			exit 1
		fi
	fi
}

# This will build the main ZquickInit Builder OCI image
# shellcheck disable=SC2317
builder() {
	echo "Creating ZQuickinit OCI build image..."
	echo
	check docker
	check yq 
	
	local packages=()
	# shellcheck disable=SC2016
	mapfile -t -O "${#packages[@]}" packages < <($YG eval-all '. as $item ireduce ({}; . *+ $item) | (... | select(type == "!!seq")) |= unique | .xbps-packages[] | .. style=""' "$RECIPES_ROOT"/*/recipe.yaml)

	if [[ -z "${ZBM_COMMIT_HASH}" ]]; then
		if [[ -z "$ZBM_TAG" ]]; then
			ZBM_TAG=$(curl --silent https://api.github.com/repos/zbm-dev/zfsbootmenu/releases/latest | $YG .tag_name)
		fi
		ZBM_COMMIT_HASH=$(curl --silent "https://api.github.com/repos/zbm-dev/zfsbootmenu/git/ref/tags/${ZBM_TAG}" | $YG .object.sha)
	fi
	ZQUICKINIT_COMMIT_HASH=$(git rev-parse HEAD)
	echo "ZQUICKINIT_COMMIT_HASH: $ZQUICKINIT_COMMIT_HASH"
	echo "ZBM_TAG: $ZBM_TAG"
	echo "ZBM_COMMIT_HASH: $ZBM_COMMIT_HASH"
	echo
	echo "Building with Packages: ${packages[*]}"
	echo
	cmd=("$ENGINE" build . 
		-t "$RECIPE_BUILDER" 
		--build-arg KERNELS=linux6.2
		--build-arg "PACKAGES=${packages[*]}" 
		--build-arg ZBM_COMMIT_HASH="${ZBM_COMMIT_HASH}"
		--build-arg ZQUICKINIT_COMMIT_HASH="${ZQUICKINIT_COMMIT_HASH}"
		--progress=plain)
	((GITHUBACTION==1)) && cmd+=(--cache-from type=gha)
	((GITHUBACTION==1)) && cmd+=(--cache-to type=gha,mode=max)
	cmd+=("$@")
	echo "Build command: ${cmd[*]}"
	"${cmd[@]}"
	$ENGINE image ls "$RECIPE_BUILDER"
}

# shellcheck disable=SC2317
tailscale_node() {
	mkdir -p state ; $ENGINE run -it -e TS_EXTRA_ARGS=--ssh -e TS_STATE_DIR=/state -v "$(pwd)"/state:/state tailscale/tailscale ; mv state/tailscaled.state "$(pwd)" ; rm -rf state
}

# This command is designed to be ONLY run from inside the running container
# shellcheck disable=SC2317
make_zquick_initramfs() { 
	gum style --bold --border double --align center \
		--width 50 --margin "1 2" --padding "0 2" "Welcome to ZQuickInit make initramfs"

	[[ -z $RUNNING_IN_CONTAINER ]] && echo _internal-run must be run from inside container && exit 1
	if [[ ! -d /input ]]; then
		local hash
		echo "Downloading zquickinit"
		rm -rf /input
		git clone --quiet --depth 1 https://github.com/midzelis/zquickinit.git /input
		hash=$(cat /etc/zquickinit-commit-hash || echo '')
		if [[ -n "${hash}" ]]; then
			(cd /input && git fetch --depth 1 origin "$hash" && git checkout FETCH_HEAD)
		fi
	fi
	(cd /input && git config --global --add safe.directory /input && git rev-parse HEAD > /etc/zquickinit-commit-hash && echo "ZQuickInit (https://github.com/midzelis/zquickinit) commit hash: $(git rev-parse --short HEAD) ($(git rev-parse HEAD))")

	if [[ ! -d /zbm ]]; then
		echo "Downloading latest zfsbootmenu"
		rm -rf /zbm
		git clone --quiet --depth 1 https://github.com/zbm-dev/zfsbootmenu.git /zbm
		hash=$(cat /etc/zbm-commit-hash)
		if [[ -n "${hash}" ]]; then
			(cd /zbm && git fetch --depth 1 origin "$hash" && git checkout FETCH_HEAD)
		fi
	fi

	(cd /zbm && git config --global --add safe.directory /zbm && git rev-parse HEAD > /etc/zbm-commit-hash && echo "ZBM (https://github.com/zbm-dev/zfsbootmenu) commit hash: $(git rev-parse --short HEAD) ($(git rev-parse HEAD))")

	hooks=()
	hook_dirs=()

	system_hooks=(autodetect base udev modconf block filesystems keyboard strip lvm2)

	recipes=()
	for dir in /input/recipes/*/initcpio; do
		[[ ! -d $dir ]] && continue
		hook_dirs+=("${dir#"/recipes"}")
		recipes+=("$(basename "$(dirname "$dir")")")
	done
	# zquick_core must always happen at the begining, so remove it and add it back later
	# shellcheck disable=SC2206
	recipes=( ${recipes[@]/zquick_core} )

	# zquick_end must always happen at the end, so remove it and add it back later
	# shellcheck disable=SC2206
	recipes=( ${recipes[@]/zquick_end} )
	
	strip_sel=
	if ((NOASK==0)); then 
		check yq

		help=
		for recipe in /input/recipes/*/recipe.yaml; do
			[[ ! -r $recipe ]] && continue
			name=$(basename "$(dirname "$recipe")")
			help+=" - \`$name\` - $(yq-go e '.help ' "$recipe")\n"
		done

		sorted=("$(sort <<<"${recipes[*]}")")
		
		gum style --bold --border double --align center \
                --width 50 --margin "1 2" --padding "0 2" "Welcome to zquickinit" "(interactive mode)"

		help_text=$(cat <<-EOF
			# Which recipes do you want to include in this build?
			$(printf "%b" "$help")
			<br>
			EOF
			)
		# echo -n "${help_text}"
		gum format "${help_text}" " "
		selected=$(IFS=, ; echo "${sorted[*]}")
		selected=("${selected[@]}")
		((RELEASE==1)) && selected=("${selected[@]/zquick_qemu}")

		# shellcheck disable=SC2207,SC2048,SC2086
		recipes+=($(gum choose ${sorted[*]} --height=20 --no-limit --selected="${selected[*]}"))
		
		help_text=$(cat <<-EOF
			# Which mkcpio system hooks would you like to include?
			See https://wiki.archlinux.org/title/mkinitcpio#Common_hooks for more info. 
			Note: autodetect won't work as expected when running within a container. 
			<br>
			EOF
			)
		gum format "${help_text}" " "

		sorted=("$(sort <<<"${system_hooks[*]}")")
		# shellcheck disable=SC2206
		sorted=( ${sorted[@]} )
		selected=$(IFS=, ; echo "${sorted[*]}")
		selected=("${selected[@]/autodetect}")
		((RELEASE==0)) && selected=("${selected[@]/strip}")
		# shellcheck disable=SC2207,SC2048,SC2086
		system_hooks=($(gum choose ${sorted[*]} --no-limit --selected="${selected[*]}"))

		# do some re-ordering
		if [[ ${system_hooks[@]} =~ strip ]]; then
			strip_sel=1
		fi

		for recipe in "${recipes[@]}"; do
			[[ ! -x /input/recipes/${recipe}/setup.sh ]] && continue
			"/input/recipes/${recipe}/setup.sh"
		done

	else
		system_hooks=("${system_hooks[@]/autodetect}")
		((RELEASE==1)) && recipes=("${recipes[@]/zquick_qemu}")
		((RELEASE==1)) && strip_sel=1 || system_hooks=("${system_hooks[@]/strip}")
		echo "zquickinit" > /etc/hostname
	fi

	# need to reorder strip
	[[ -n $strip_sel ]] && system_hooks=( ${system_hooks[@]/strip} ) 

	# zquick_core is first recipe, and always added
	recipes=( zquick_core ${recipes[@]/zquick_core} ) 

	# first system hooks
	hooks+=(${system_hooks[@]})

	# then zfsbootmenu
	hooks+=("zfsbootmenu")
	# then recipes
	hooks+=(${recipes[@]})
	# strip goes last
	[[ -n $strip_sel ]] && hooks+=("strip")

	hooks+=("zquick_end")

	build_time=$(date -u +"%Y-%m-%d_%H%M%S");

	mkdir -p /tmp
	rm -rf /tmp/*
	zquickinit=/input
	cat > /tmp/mkinitcpio.conf <<-EOF
		MODULES=()
		BINARIES=()
		FILES=()
		HOOKS=(${hooks[@]})
		COMPRESSION=(zstd)
		COMPRESSION_OPTIONS=(-9 --long)
		
		zquickinit_root="$zquickinit"

		function find_recipe { 
			local i=\${1:-1} size=\${#BASH_SOURCE[@]}
			for ((; i < size-1; i++)) ;do  
				local file=\${BASH_SOURCE[\$i]:-}
				if [[ \$file == $zquickinit/recipes/* ]]; then
					echo \$(basename \$file)
					break;
			 	fi
			done
		}

		zquick_add_secret() {
			if [[ $RELEASE = "1" ]]; then return 0; fi
			local filename=\$(basename \$1)
			local dirname=\$(dirname \$1)
			local file=
			# shellcheck disable=SC2154
			for path in "\$dirname" "$zquickinit"; do
				[[ -f "\$path/\$filename" ]] && file="\$path/\$filename" && break
			done

			if [ ! -r "\$file" ]; then
				warning "\$2 (\$filename) not found during build time"
				return 1
			else 
				echo "adding \$2 (\$file) to image"
				add_file "\$file" \$1
			fi
		}

		zquick_add_fs() {
			local recipe="\$(find_recipe)"
			[[ -n "\${recipe}" ]] && \
				add_full_dir "$zquickinit"/recipes/"\${recipe}"/fs "*" "$zquickinit"/recipes/"\${recipe}"/fs || \
				warning "Could not find recipe, not adding filesystem."
		}

		zfsbootmenu_module_root="/zbm/zfsbootmenu"
		zfsbootmenu_early_setup=()
		zfsbootmenu_setup=()
		zfsbootmenu_teardown=()
		EOF
	

	echo "zfsbootmenu ro loglevel=6 zbm.autosize=0" > /tmp/cmdline

	cat > /tmp/os-release <<-EOF
		NAME="ZFSQuickInit"
		ID="ZFSQuickInit"
		ID_LIKE="void"
		PRETTY_NAME="ZFSQuickInit (built on $build_time)"
		ANSI_COLOR="0;38;2;71;128;97"
		EOF

	hook_dirs+=("/zbm/initcpio")
	hook_dirs+=("/usr/lib/initcpio")
	hookdirs+=("${hook_dirs[@]/#/--hookdir }")

	output_img=/output/zquickinit-$build_time.img
	output_uki="/output/zquickinit-$build_time.efi" 
	kernel=$(basename "$(find "/lib/modules" -maxdepth 1 -type d| grep "/lib/modules/" | sort -V | tail -n 1)")

	mkinitcpio --config /tmp/mkinitcpio.conf ${hookdirs[*]} \
		--kernel "$kernel" \
		--osrelease /tmp/os-release \
		--cmdline /tmp/cmdline \
		--generate "$output_img" \
		-U "$output_uki" 
	cp "/boot/vmlinuz-$kernel" "/output/vmlinuz-$kernel"
	(cd output; rm -rf zquickinit.efi; ln -s zquickinit-$build_time.efi zquickinit.efi)
	chmod o+rw -R output/*
	chmod g+rw -R output/*
	env LC_ALL=en_US.UTF-8 printf "Kernel size: \t\t%'.0f bytes\n" "$(stat -c '%s' "output/vmlinuz-$kernel")"
	env LC_ALL=en_US.UTF-8 printf "initramfs size: \t%'.0f bytes\n" "$(stat -c '%s' "$output_img")"
	env LC_ALL=en_US.UTF-8 printf "EFI size: \t\t%'.0f bytes\n" "$(stat -c '%s' "$output_uki")"
	find output -name 'zquickinit*.img' | sort -r | tail -n +4 | xargs -r rm
	find output -name 'zquickinit*.efi' | sort -r | tail -n +4 | xargs -r rm
}

initramfs() {
	check docker
	echo
	echo "Launching $ENGINE..."
	cmd=("$ENGINE" run --rm)
	((NOASK==0)) && cmd+=(-it)
	
	[[ -f "$SRC_ROOT/zquickinit.sh" ]] && cmd+=(-v "$SRC_ROOT/zquickinit.sh:/zquickinit.sh:ro") && echo "bind-mount: zquickinit.sh (readonly)"
	[[ -d "$RECIPES_ROOT" ]] && cmd+=(-v "$SRC_ROOT:/input:ro") && echo "bind-mount: $RECIPES_ROOT to /input (readonly)"
	[[ -d "$ZBM_ROOT" ]] && cmd+=(-v "$ZBM_ROOT:/zbm:ro" ) && echo "bind-mount: $(readlink -f "${ZBM_ROOT}") to /zbm (readonly)"

	echo "bind-mount: $SRC_ROOT/output to /output (read-write)"
	mkdir -p "$SRC_ROOT/output"
	[[ -d "$SRC_ROOT/output" ]] && cmd+=(-v "$SRC_ROOT/output:/output")

	((ENTER==1)) && cmd+=(--entrypoint=/bin/bash -i)
	cmd+=("$RECIPE_BUILDER")
	((ENTER==0)) && cmd+=(make_zquick_initramfs)
	((ENTER==0 && NOASK==1)) && cmd+=(--no-ask)
	((DEBUG==1)) && cmd+=(--debug)
	((RELEASE==1)) && cmd+=(--release)
	echo
	"${cmd[@]}"
}

getefi() {
	source=$(${FIND} . -type f -name 'zquickinit*.efi' -printf '%f\t%p\n' | sort -k1 | cut -d$'\t' -f2 | tail -n1)
	if [[ -r "$source" ]]; then
		echo "Found EFI: ${source}"
	else
		source="${tmp}/zquickinit.efi"
		echo "No image found, finding latest release..."
		local version='' download=''
		version=$(curl --silent -qI "${ZQUICKEFI_URL}" | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}')
		download="https://github.com/midzelis/zquickinit/releases/download/$version/zquickinit.efi"
		echo "Downloading from ${download} to ${source}..."
		curl -o "$source" --progress-bar -L "${download}" 
	fi
}

inject() {

	inject_secret() {
		local filename='' file='' dir=''
		filename=$(basename "$1")
		[[ -n "${INSTALLER_MODE:-}" ]] && dir=$(dirname "$1") || dir="."
		# shellcheck disable=SC2154
		for path in "$dir" "$1"; do
			[[ -f "$path/$filename" ]] && file="$path/$filename" && break
		done

		if [ ! -r "$file" ]; then
			echo "$2 ($filename) not found"
			return 1
		else 
			echo "INJECTING $2 ($file) to image @ $1"
			mkdir -p "$(dirname "${tmp}/$1")"
			cp "${file}" "${tmp}/$1"
		fi
		return 0
	}

	local target=${1:-zquickinit.efi}
	local source=${2:-}
	[[ -e "${target}" ]] && echo "${target} already exists." && exit 1

	# shellcheck disable=SC2155
	local tmp=$(tmpdir)
	
	echo "Injecting secrets into ZFSQuickInit EFI image"
	if [[ ! -r "$source" ]]; then
		echo "No source_efi specified  - searching for image..."
		check curl curl
		check find findutils
		getefi
	fi
	
	local injected=0
	[[ -z "${INSTALLER_MODE:-}" ]] && inject_secret "/zquick/etc/ttyd_pushover.conf"         "pushover ttyd config" && injected=1
	[[ -z "${INSTALLER_MODE:-}" ]] && inject_secret "/etc/tailscale/tailscaled.conf"         "tailscale config" && injected=1
	[[ -z "${INSTALLER_MODE:-}" ]] && inject_secret "/var/lib/tailscale/tailscaled.state"    "tailscale node identity" && injected=1
	inject_secret "/root/.ssh/authorized_keys"             "sshd authorized_keys for root" && injected=1
	[[ -z "${INSTALLER_MODE:-}" ]] && inject_secret "/etc/ssh/ssh_host_rsa_key"              "sshd host rsa key" && injected=1
	[[ -z "${INSTALLER_MODE:-}" ]] && inject_secret "/etc/ssh/ssh_host_ecdsa_key"            "sshd host ecdsa key" && injected=1
	[[ -z "${INSTALLER_MODE:-}" ]] && inject_secret "/etc/ssh/ssh_host_ed25519_key"          "sshd host ed25519 key" && injected=1

	if ((injected==1)); then
		check pax "pax or pax-utils"
		check objcopy binutils
		check truncate coreutils
		check find findutils

		local initrd="${tmp}/zquickinit.img.zst"
		echo "Extracting initramfs from EFI ${source} to ${initrd}"
		$OBJCOPY -O binary --only-section=.initrd "${source}" "${initrd}"

		# To append an additional initrd segment, the new archive must aligned to a
		# 4-byte boundary: https://unix.stackexchange.com/a/737219

		initrd_size=$(stat -c '%s' "${initrd}")
		initrd_size=$(((initrd_size + 3) / 4 * 4))
		truncate -s "${initrd_size}" "${initrd}"

		# shellcheck disable=SC2094
		${FIND} "${tmp}" -not -path "${initrd}" -not -path "${source}" -print | \
			pax -x sv4cpio -wd -s#"${tmp}"## | zstd >> "${initrd}"

		echo "Copying new initramfs ${source} to EFI ${target}..."
		cp "${source}" "${target}"
		$OBJCOPY --remove-section .initrd "${target}"
		$OBJCOPY --add-section .initrd="${initrd}" --change-section-vma .initrd=0x3000000 "${target}"
	else
		echo "No secrets to inject."
		echo "Copying ${source} to ${target}..."
		cp "${source}" "${target}"
		echo "Created ${target}"
	fi
	echo "Done"
}

iso() {
	# Here we generate a FAT-partioned image and copy the EFI to
	# the standard boot image location (/EFI/BOOT/BOOTX64.EFI) 
	# This iso can be booted directly by QEMU or other VMs

	check mformat mtools
	check mmd mtools
	check mcopy mtools
	check xorriso xorriso
	check truncate coreutils
	check find findutils

	local target=${1:-zquickinit.iso}
	local source=${2:-}
	# shellcheck disable=SC2155
	local tmp=$(tmpdir)

	echo "Generating ISO to ${target}" 
	if [[ ! -r "$source" ]]; then
		echo "No EFI UKI source specified  - searching for image..."
		getefi
	fi

	local isoroot="${tmp}/iso"
	mkdir -p "${isoroot}"
	local size
	read -ra size <<<"$(du --apparent-size --block-size=1M "$source")"
	local padded=$((size[0]+12))
	local part_img="${tmp}/efs_partition.img"
	rm -rf "${part_img}"
	echo "Generating raw file image for VM as $part_img"
	truncate -s "${padded}"MiB "$part_img"

	mformat -F -i "$part_img" :: 
	mmd -i "$part_img" ::/EFI
	mmd -i "$part_img" ::/EFI/BOOT
	mcopy -i "$part_img" "$source" ::/EFI/BOOT/BOOTX64.EFI

	# mkdir -p "${isoroot}/EFI/BOOT"
	# cp "$source" "${isoroot}/EFI/BOOT/BOOTX64.EFI"
	xorriso -as mkisofs -r -V 'ZQINIT' -append_partition 2 0xef "${part_img}" -e --interval:appended_partition_2:all:: -no-emul-boot -partition_offset 16 --no-pad -o "${target}" "${isoroot}"
}

playground() {
	echo
	echo "Starting QEMU playground..."
	echo

	check truncate coreutils
	check qemu-system-x86_64 qemu
	check find findutils

	# shellcheck disable=SC2155
	local tmp=$(tmpdir)
	local source='' kernel='' initrd='' iso='' tmpiso='' ovmf=''
	echo "Searching for zquickinit kernel/initramfs pair" 
	# shellcheck disable=SC2155
	kernel=$(${FIND} . -type f -name 'vmlinuz*' -printf '%f\t%p\n' | sort -k1 | cut -d$'\t' -f2 | tail -n1)
	# shellcheck disable=SC2155
	initrd=$(${FIND} . -type f -name 'zquickinit*.img' -printf '%f\t%p\n' | sort -k1 | cut -d$'\t' -f2 | tail -n1)
	if [[ -z "${kernel}" || -z "${initrd}" ]]; then 
		echo "Kernel/initramfs pair not found: searching for ISO zquickinit.iso"
		iso=$(${FIND} . -type f -name 'zquickinit.iso' -printf '%f\t%p\n' | sort -k1 | cut -d$'\t' -f2 | tail -n1)
		if [[ -z "$iso" ]]; then
			echo "ISO zquickinit.iso not found: searching for EFI image"
			check objcopy binutils
			getefi
			if [[ ! "${source}" -ef "zquickinit.efi" ]]; then 
				echo "Moving $source to zquickinit.efi"
				mv "$source" zquickinit.efi
				source=zquickinit.efi
			fi
			initrd=${tmp}/zquickinit.img
			echo "Extracting initramfs from ${source} to ${initrd}"
			$OBJCOPY -O binary --only-section=.initrd "${source}" "${initrd}"
			kernel=${tmp}/vmlinuz
			echo "Extracting kernel rom EFI ${source} to ${kernel}"
			$OBJCOPY -O binary --only-section=.linux "${source}" "${kernel}"
		fi
	fi
	if [[ -n "$iso" ]]; then
		echo "Found iso: ${iso}"
		tmpiso="${tmp}/$(basename "${iso}")"
		cp "${iso}" "${tmpiso}"
	else
		echo "Found kernel: ${kernel}"
		echo "Found initrd: ${initrd}"
	fi

	if ((DRIVE1==1)); then
		if [[ ! -e /tmp/disk.raw ]]; then
			echo "Drive1: Creating ${DRIVE1_GB}GiB file at /tmp/disk.raw as a disk image"
			truncate -s ${DRIVE1_GB}GiB /tmp/disk.raw
		else
			echo "Drive1: Using file /tmp/disk.raw as a disk image"
		fi
	fi

	if ((DRIVE2==1)); then
		if [[ ! -e /tmp/disk2.raw ]]; then
			echo "Drive2: Creating ${DRIVE2_GB}GiB file at /tmp/disk2.raw as a disk image"
			truncate -s ${DRIVE2_GB}GiB /tmp/disk2.raw
		else
			echo "Drive2: Using file /tmp/disk2.raw as a disk image"
		fi
	fi

	APPEND=("loglevel=6 zbm.show")
	SSH_PORT=2222
	aoi=''
	if [[ "$OSTYPE" == "darwin"* ]]; then
		aoi=''
	else 
		aoi=",aio=io_uring"
	fi
	# shellcheck disable=SC2054
	args=(qemu-system-x86_64 
		-m 16G 
		-smp "$(nproc)"
		-object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0 
		-object iothread,id=iothread0
		-netdev user,id=n1,hostfwd=tcp::"${SSH_PORT}"-:22,hostfwd=tcp::8006-:8006 -device virtio-net-pci,netdev=n1 
		-device virtio-scsi-pci,id=scsi0,iothread=iothread0
		-device scsi-hd,drive=drive1,bus=scsi0.0,bootindex=1,rotation_rate=1
		-device scsi-hd,drive=drive2,bus=scsi0.0,bootindex=2,rotation_rate=1
		-drive file=/tmp/disk.raw,format=raw,if=none,discard=unmap${aoi},cache=writeback,id=drive1,unit=0
		-drive file=/tmp/disk2.raw,format=raw,if=none,discard=unmap${aoi},cache=writeback,id=drive2,unit=1
		-serial "mon:stdio"
	)
	if [[ -z "${NOQEMU}" ]]; then
		args+=(-fsdev local,id=f1,path=.,security_model=none -device virtio-9p-pci,fsdev=f1,mount_tag=qemuhost)
		cachedir=$(find . -name cache -type d)
		[[ -n "$cachedir" ]] && args+=(-fsdev "local,id=f2,path=${cachedir},security_model=none" -device virtio-9p-pci,fsdev=f2,mount_tag=qemucache)
	fi
	if [[ "$OSTYPE" == "darwin"* ]]; then
		args+=(-cpu host,-pdpe1gb -machine q35,accel=hvf)
	else
		if [ -e /dev/kvm ] && sh -c 'echo -n > /dev/kvm' &> /dev/null; then
			args+=(-cpu host -machine q35,accel=kvm)
		else
			args+=(-cpu qemu64 -machine q35)
			echo "/dev/kvm not found, or user does not have access - performance will be significantly worse"
			echo "If the kvm group exists, this may help 'sudo usermod --append --groups kvm $(whoami)'"
			sleep 1
		fi
	fi

	if [[ -n "${SSHONLY}" ]]; then
		if [[ -n "$iso" ]]; then
			echo "zquickinit ISO images may not be configured for serial console, not setting -display none"
		else 
			args+=(-display none)
		fi
	else
		# args+=(-nographic)
		args+=(-display none)
	fi

	ovmf=$(${FIND} /usr -name edk2-x86_64-code.fd 2>/dev/null | head -n1 || true)
	if [[ -n "${ovmf}" ]]; then
		echo "Using UEFI firmware: ${ovmf}"
		args+=(-drive "file=${ovmf},if=pflash,format=raw,readonly=on")
	else 
		ovmf=$(${FIND} /usr | grep OVMF.fd | head -n1 || true)
		if [[ -n "${ovmf}" ]]; then
			echo "Using UEFI firmware: ${ovmf}"
			args+=(-bios "${ovmf}")
		else
			echo "OVMF (UEFI) BIOS not detected, maybe install the ovmf package?"
			ovmf=''
		fi
	fi
	if [[ -n "$iso" ]]; then
		args+=(-drive "file=${tmpiso},media=cdrom")
		echo "ISO images automatically configure QEMU vnc server" 
		if [[ -z "${ovmf}" ]]; then
			echo "EFI firmware is required for ISO images!"
			exit 1;
		fi
	else
		[[ -z "$KERNEL_BOOT" ]] && KERNEL_BOOT=1
		if [[ -z "${SSHONLY}" ]]; then
			LINES="$(tput lines)"
			COLUMNS="$(tput cols)"
			[ -n "${LINES}" ] && APPEND+=( "zbm.lines=${LINES}" )
			[ -n "${COLUMNS}" ] && APPEND+=( "zbm.columns=${COLUMNS}" )
			# shellcheck disable=SC2054
			APPEND+=(console=ttyS0,115200n8);
		fi
	fi
	if ((KERNEL_BOOT==1)); then
		args+=(-kernel "$kernel")
		args+=(-initrd "$initrd")
		args+=(-append "${APPEND[*]}")
	else
		args+=(-display vnc=0.0.0.0:0)
		echo "Not using serial console, VNC is running on 0.0.0.0:5900"
	fi
	echo
	echo "Hint: to quit QEMU, press ctrl-a, x"
	[[ -n "${SSHONLY}" ]] && echo Running in SSH only mode, to enter SSH use command: ssh root@localhost -p 2222
	echo
	echo 	"${args[@]}"
	read -n 1 -s -r -p "Press any key to launch QEMU"
	echo
	echo "Starting..."
	"${args[@]}"
}

command=${1:-}
shift || true
if [[ $(type -t "$command") == function ]]; then
	ARGS=()
	while (($# > 0)); do
		key="$1"
		case $key in
			--no-ask)
				NOASK=1
			;;
			-e|--enter)
				ENTER=1
			;;
			-d|--debug)
				DEBUG=1
				set -x
			;;
			--release)
				RELEASE=1
			;;
			--ssh-only)
				SSHONLY=1
			;;
			--no-qemu)
				NOQEMU=1
			;;
			--githubaction)
				GITHUBACTION=1
			;;
			--no-kernel)
				KERNEL_BOOT=0
			;;
			--drive2)
				DRIVE2=1
				if [[ ${2:-} =~ ^[0-9]+$ ]]; then
					DRIVE2_GB=$2
					shift
				fi
			;;
			*)
			ARGS+=("$1")
			;;
		esac
		shift
	done
	"$command" "${ARGS[@]}" 
elif [[ -z "${SOURCE}" ]]; then
	# probably running from curl
	set -o posix
	echo
	echo "ZQuickinit.sh" 
	echo "Super Quick mode: running from curl; probably"
	echo
	echo "Select what you'd like to do, ctrl-c to abort"
	echo
	options=(
		"ZQuickInit Playground: Download (or find) ZQuickInit and launch Virtual Machine)"
		"Download ZQuickInit: Retrieve EFI image to current directory, inject config files" 
		"Build ZQuickInit: Use Docker/Podman to create custom ZQuickInit EFI image"
	)
	COLUMNS=1
	select ITEM in "${options[@]}"; do
		if [[ $ITEM = Download* ]]; then
			echo
			echo "If any of the folowing files are present in the current directory, they will be injected into the image"
			echo "after it is downloaded. If none are present, then ZQuickInit EFI image will downloaded without any changes."
			echo
			echo "ttyd_pushover.conf tailscaled.conf tailscaled.state authorized_keys ssh_host_rsa_key ssh_host_ecdsa_key ssh_host_ed25519_key"
			echo
			echo "For a more interactive customization, choose 'Build ZQuickInit' from the previous menu"
			echo
			read -n 1 -s -r -p "Press any key to continue"
			echo
			inject "$@"
			exit $?
		elif [[ $ITEM = ZQuickInit* ]]; then
			playground "$@"
			exit $?
		elif [[ $ITEM = Build* ]]; then
			initramfs  "$@"
			exit $?
		else 
			echo "Invalid option, exiting"
			exit 1
		fi
	done
	set +o posix
else
	echo "  zquickinit.sh"
	echo "    ZQuickInit image functions!"
	echo
	echo "  Usage"
	echo "    zquickinit.sh initramfs [--no-ask]"
	echo "    zquickinit.sh inject [target_efi] [source_efi]"
	echo "    zquickinit.sh iso [target_iso] [source_efi] "
	echo "    zquickinit.sh playground [--ssh-only] [--no-kernel] [--drive2]"
	echo
	echo "  Advanced Usage"
	echo "    zquickinit.sh builder"
	echo "    zquickinit.sh tailscale"
	echo
	echo "  Commands"
	echo "    initramfs     Build a zquickinit.efi image using docker or podman."
	echo "    builder       Advanced: Create the OCI builder image for ZQuickInit"
	echo "    tailscale     Login to tailscale and save to tailscaled.conf"
	echo "    iso           Build an iso image (for playground)"
	echo "    playground    Start a QEMU VM on the zquickinit.sh image in order to"
	echo "                  play around with zquickinit.efi" 
	echo 
	echo "  Options"
	echo "    --no-ask      Do not ask any questions for building image. "
	echo "                  Just use files in the current directory, if present."
	echo "    --release     Do not add QEMU debug, or any secrets" 
	echo "    -d,--debug    Advanced: Turn on tracing"
	echo "    -e,--enter    Advanced: Do not build an image. Execute bash and"
	echo "                  enter the builder image."
	echo "    source_efi    The zquickinit source image or download from GitHub image"
	echo "                  if not specified."
	echo "    target_efi    Where the results of the image after injection will"
	echo "                  be stored. Default is zquickinit.efi in the current folder"
	echo "   --ssh-only		Will launch playground without console output on ttyS0, you"
	echo "                  must connect to playground using ssh on localhost:2222"
	echo "   --no-kernel	Do not launch playground with kernel image, boot from"
	echo "                  configured drives instead"
	echo "   --drive2 <GB>  Configure with an additional drive of size <GB>. (3 GiB default) "
fi
