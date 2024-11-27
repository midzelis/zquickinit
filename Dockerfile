# syntax=docker/dockerfile:1
#
# This Dockerfile creates a container that will create an EFI executable and
# separate kernel/initramfs components from a ZFSBootMenu repository. The
# container will pre-populate its /zbm directory with a clone of the master
# branch of the upstream ZFSBootMenu branch and build the images from that.
#
# To use a different ZFSBootMenu repository or version, bind-mound the
# repository you want on /zbm inside the container.

# Use the official Void Linux container
FROM ghcr.io/void-linux/void-glibc-full 
LABEL org.opencontainers.image.source=https://github.com/midzelis/zquickinit

ARG XBPS_REPOS="https://repo-fastly.voidlinux.org/current https://repo-fastly.voidlinux.org/current/nonfree"

# Include the specified Void Linux kernel series in the image; kernel
# series take the form <major>.<minor> and correspond to Void packages
# linux<kver> and linux<kver>-headers
#
# Default: install 5.10, 5.15, 6.1 and 6.2
#
# (multiple entries must be seperated by spaces)
ARG KERNELS="linux5.10 linux5.15 linux6.1 linux6.2 linux6.6 linux6.8" 

# Run the following within an external cache (/var/cache/xbps) for the 
# package manager; so when this layer is rebuilt, at least you save 
# some bandwidth. 
RUN --mount=type=cache,target=/var/cache/xbps <<-EOF
	# Update repos and install kernels and base dependencies.
	[ -n "${KERNELS}" ] || { echo "ARG KERNELS must contain a value"; exit 1; }

	mkdir -p /etc/xbps.d
	for repo in ${XBPS_REPOS}; do
		echo "repository=$repo" >> /etc/xbps.d/00-custom-repos.conf
	done
	
	# Ensure everything is up-to-date
	xbps-install -Suy xbps && xbps-install -uy
	
	# Prefer an LTS version over whatever Void thinks is current
	cat > /etc/xbps.d/10-nolinux.conf <<-CAT
		ignorepkg=linux
		ignorepkg=linux-headers
	CAT

	# Prevent initramfs kernel hooks from being installed
	cat > /etc/xbps.d/15-noinitramfs.conf <<-CAT
		noextract=/usr/libexec/mkinitcpio/*
		noextract=/usr/libexec/dracut/*
	CAT
	
	for _kern in ${KERNELS}; do
		kern_headers="$kern_headers ${_kern}-headers"
	done
	
	# Install ZFSBootMenu dependencies and components necessary to build images
	zbm_deps="$(xbps-query -Rp run_depends zfsbootmenu | tr '\n' ' ')"

	xbps-install -y ${KERNELS} ${kern_headers} ${zbm_deps} \
  		zstd gummiboot-efistub curl yq-go bash kbd terminus-font \
  		mkinitcpio gptfdisk iproute2 iputils parted \
  		curl dosfstools e2fsprogs efibootmgr cryptsetup openssh util-linux kpartx git
	
	# Remove headers and development toolchain, but keep binutils for objcopy
	echo "ignorepkg=dkms" > /etc/xbps.d/10-nodkms.conf
	xbps-pkgdb -m manual binutils
	xbps-remove -Roy dkms ${kern_headers}
	
	EOF

RUN <<-EOF
	echo "en_US.UTF-8 UTF-8" > /etc/default/libc-locales
	xbps-reconfigure -f glibc-locales
	EOF

# Include the specified Void Linux package in the image
#
# (multiple entries must be seperated by spaces)
ARG PACKAGES=
# Run ${PACKAGES} install in seperate layer so that the zfs dkms packages 
# are not rebuilt when ${PACKAGES} change. reuse. Additionally: use xbps cache. 
RUN --mount=type=cache,target=/var/cache/xbps <<-EOF 

	# Install ZFSBootMenu dependencies and components necessary to build images
	xbps-install -S
	xbps-install -y ${PACKAGES}
	EOF

# Free space in image
RUN rm -f /var/cache/xbps/*

# ZFSBootMenu commit hash, tag or branch name used by
# default to build ZFSBootMenu images (default: master)
ARG ZBM_COMMIT_HASH
RUN <<-EOF 
	# Record a commit hash if one was provided
	if [ -n "${ZBM_COMMIT_HASH}" ]; then
		echo "Using zfsbootmenu commit hash: ${ZBM_COMMIT_HASH}"
		echo "${ZBM_COMMIT_HASH}" > /etc/zbm-commit-hash
		mkdir -p /zbm
		echo "Cloning https://github.com/zbm-dev/zfsbootmenu.git"
		git clone --quiet --depth 1 ${branch} https://github.com/zbm-dev/zfsbootmenu.git /zbm
		(cd /zbm && git fetch --depth 1 origin "${ZBM_COMMIT_HASH}" && git checkout FETCH_HEAD)
	fi
	EOF

COPY . /input/
# ZQuickInit source 
ARG ZQUICKINIT_COMMIT_HASH
RUN <<-EOF 
	if [ -n "${ZQUICKINIT_COMMIT_HASH}" ]; then
		echo "Using zquickinit commit hash: ${ZQUICKINIT_COMMIT_HASH}"
		echo "${ZQUICKINIT_COMMIT_HASH}" > /etc/zquickinit-commit-hash
	fi
	EOF

COPY --chmod=755 zquickinit.sh /

RUN ls /usr/bin 
# use busybox-huge version (vs busybox.static) (for syslogd support)
RUN [ -x /usr/bin/busybox ] && cp -f /usr/bin/busybox /usr/lib/initcpio/busybox || true

# Run the build script with no arguments by default
ENTRYPOINT [ "/zquickinit.sh" ]
ENV RUNNING_IN_CONTAINER=1
ENV TERM=xterm-256color