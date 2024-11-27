# ZQuickInit - ZFS Quick Init, Rescue and Install initramfs customizeable image

A distribution based on ZFSBootMenu to securely remote boot, rescue, and install Proxmox. This is an ***opinionated***, but secure, and easy to use [ZFSBootMenu](https://zfsbootmenu.org)-based distribution. (maybe the first?)

### Too long, didn't read. 

From curl to VM Playgroud in 60 seconds...
[![asciicast](https://asciinema.org/a/CRDW6ZLC2naPBWPn2qVjb7DAS.svg)](https://asciinema.org/a/CRDW6ZLC2naPBWPn2qVjb7DAS)

Interactive customization...
<a href="https://asciinema.org/a/DSsDkrvLEO02lO5JNXrViG5Vq" target="_blank"><img src="https://asciinema.org/a/DSsDkrvLEO02lO5JNXrViG5Vq.svg" /></a>

Partition, Encrypt and Install Proxmox...
[![asciicast](https://asciinema.org/a/d7tSkr6pKpEX1NkjQ3rX5jOuN.svg)](https://asciinema.org/a/d7tSkr6pKpEX1NkjQ3rX5jOuN)


First boot of Proxmox on encrypted partition, after install...
[![asciicast](https://asciinema.org/a/Imru2MRFdKK4MxScGqNTxnNRj.svg)](https://asciinema.org/a/Imru2MRFdKK4MxScGqNTxnNRj)

Let me try! 
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/midzelis/zquickinit/main/zquickinit.sh)"
```

## Features
### NAT-piercing remote unlocks using Tailscale
`ZQuickInit` builds upon the foundations provided by `ZFSBootMenu` with missing functions. Noteably, being able to access a ZFS-based box that exists in an untrusted environment behind a NAT with no UPNP or NAT-PMP services. 

The box will use an encrypted root filesystem. The box itself may be stolen, so the encryption keys should not be stored in SecureBoot or TPM. In order to descrypt the drive, `ZFSBootMenu` will prompt to load they key at startup. However, if this server has been restarted, it may be inconvient for the operator to enter the password. 

This is solved by configuring the network interfaces and also adding Tailscale (SSH) to the `ZFSBootMenu` configuration. Tailscale will allow remote access and will allow accessing the box behind the NAT. Tailscale also allows us to totally lock down the network side of things as well - there will be no listening ports on the local network interfaces at all - all of server will be running on the internal Tailscale interface. 

However, `ZFSBootMenu` chainloads the selected rootfilesystem after prompting for the decryption key. It boots the decrypted target kernel/initramfs - but this environment no longer has the original decryption key - and you'd have to enter the encryption key again. 

Reprompting may just be merely inconvenient if you were in front of the box. But it is doubly inconvenient since this secondary kernel/initramfs environment would not have tailscale installed or even any network configuration at all. So this will stall out the remote boot process. 

### Securily passing key from `ZQuickInit`/ZBM environment into chained kernel/initramfs
`ZQuickInit` fixes this by 'injecting' the password into selected initramfs image. This takes advantage of the fact that Linux Kernel will continue to decompress initramfs images if it finds another initramfs image after the first one. So, to 'inject' the password, `ZQuickInit` literally just creates a new compressed initramfs image and concatenates it with the selected initramfs image, and then boots that using the kexec. 

Unfortunately, even with recent improvements to `ZFSBootMenu` (the loadkey.d and botsel hooks), I wasn't able to convincingly implement this behavior. `ZQuickInit` patches the entire `load_key` and `kexec_kernel` functions to implement this behavior. 

### Bare Metal Installs
`ZFSBootMenu` is great because it is a fully featured (although significantly trimmed) linux distribution. However, I found it lacking for my purposes. 

Instead of ending with secure decryption of the root filesystem - I saw potential as the basis of a full rescue utility, and installer for Proxmox to help bootstrap new machines. 

`ZQuickInit` can be started with no pools at all. In fact, you can drop the EFI on any FAT32 formatted USB stick and boot from it. You will be guided through a series of questions that will help you partition, create an (encrypted) pool, create a root dataset, configure a ESP partition (with `ZQuickInit` installed on it) and finally a way to Install Proxmox into the new root dataset. 

`ZquickInit` can also be used to convert a previously unecrypted ZFS root partition into an encrypted one. 

### Rescue Functions
`ZQuickInit` adds several useful programs that are useful when running a networked boot, specifally with disk/partitioning tasks in mind. This includes accessing LVM partitions, and ext3/4 and [ex]FAT[32] partitions. 

To rescue or install, image a USB drive, or copy the EFI to a USB stick. Or, my favorite, use [Ventoy](https://www.ventoy.net/en/index.html) to boot the EFI. 
### `tmux` by default
Since `ZQuickInit` is designed to be run with SSH, and the console may also be active, a shared `tmux` session is created between the local console and the remote SSH. 

### Quality of life improvements
Getting `tmux` running and also making the Installer and the various prompts pretty required a lot of trial and error to figure out keyboard mappings, unicode support, serial console, QEMU configuration, and so so many things. I'm proud to say that beatiful, colorful, unicode interfaces are supported however you access the `ZQuickinit` - local console, SSH console, or via QEMU (vnc, or serial console). 

### Easy to use!
`ZFSBootMenu` has a lot of documentation. A lot. Its generally useful but slow to get started. It took me weeks to figure everything out. I hope that `ZQuickInit` helps make ZFSBootMenu easier to try and use. 

#### mkinitcpio only
To support this goal, I make a lot of opinionated choices. Instead of supporting dracut and mkinitcpio, I choose to drop dracut. (I started with it at first, but it was hard to use, and slow, and cumbersome. Mkinitcpio is better in every single possible way - in my opinion!) 

#### OCI builds using Void Linux only
`ZFSBootMenu` supports being built by almost any Linux distribution under the sun. I choose to drop all of these, and stick with just one: Void Linux. I never used this distro before, but I was pleasently surprised by it. Really, I chose it because it was the default distribution used by the Dockerfiles within `ZFSBootMenu`. `ZQuickInit` is exclusivesly build via Docker (or Podman, once they have support for `syntax=docker/dockerfile:1`)

#### Recipes
So I structured all of my "packages" that built on top of `ZFSBootMenu` into a 'recipe' format. This is a simple convention-based package structure. First, it lives under `/recipes` in the source tree. 

It contains an optional `recipe.yaml` metadata file. This file lists 2 things: 
1. the xbps dependencies
2. help text

It contains an optional `setup.sh` file. This file is invoked while the `ZQuickInit` is being assembled/built. The main point of this file is to load additional data (configuration, secrets) into the image. 

Then it creates a directory called `initcpio` this folder contains all of the 'hooks' for `mkinitcpio` - most importantly you'll want to use `install` hook. The `run` hook is used by `ZFSBootMenu` itself, and probably shouldn't be used. Rather, you should use the existing hooks that `ZFSBootMenu` exposes to add functionality. 

# Getting started

You know how I said that the Linux Kernel will continue decompressing any cpio images found after the first one? Well, you can leverage this for `ZQuickInit` itself! 

That right, you don't even need to build anything to use `ZQuickInit` - you can just download, and 'inject' your secrets of customizations directly into that image and then use it. 

## zquickinit.sh
The main script is runnable directly from curl/bash. However, if you want more customization, or just hate this trend of random github repos asking you to blindly execute scripts from weird URLs, you can also just clone this repo and run it that way. 

### Running from curl: 
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/midzelis/zquickinit/main/zquickinit.sh)"
```

It will ask you if you want to download the EFI image, or run a "playground" that will boot the image in a QEMU VM. 

### Building from source
```
git clone https://github.com/midzelis/zquickinit.git
cd zquickinit
./zquickinit.sh # this will show help screen
```

### Help Manual
#### zquickinit.sh
    ZQuickInit image functions!

####  Usage
    zquickinit.sh initramfs [--noask]
    zquickinit.sh inject [target_efi] [source_efi]
    zquickinit.sh iso [target_iso] [source_efi]
    zquickinit.sh playground [--sshonly]

####  Advanced Usage
    zquickinit.sh builder
    zquickinit.sh tailscale

####  Commands
    initramfs     Build a zquickinit.efi image using docker or podman.
    builder       Advanced: Create the OCI builder image for ZQuickInit
    tailscale     Login to tailscale and save to tailscaled.conf
    iso           Build an iso image (for playground, or to write to USB)
    playground    Start a QEMU VM on the zquickinit.sh image in order to
                  play around with zquickinit.efi

####  Options
    --noask       Do not ask any questions for building image.
                  Just use files in the current directory, if present.
    --release     Do not add QEMU debug
    -d,--debug    Advanced: Turn on tracing
    -e,--enter    Advanced: Do not build an image. Execute bash and
                  enter the builder image.
    source_efi    The zquickinit source image or download from GitHub image
                  if not specified.
    target_efi    Where the results of the image after injection will
                  be stored. Default is zquickinit.efi in the current folder

### How to build

1. First, you need to build the builder, which is the Void Linux based Docker image used to run mkinicpio. 
```bash
./zquickinit.sh builder
```
2. Then, you need to build ZQuickInit (this will be interactive), you can instead just use local files in the current directory instead, by passing `--noask`
```bash
./zquickinit.sh initramfs
```
3. When your ready to test, you can start the Playground in a QEMU VM. If you are going to be trying out the Proxmox installer (zquick_installer.sh) you can save bandwith by creating a folder `cache` in the top level source folder. This will be shared using 9p to the guest and will be used to cache downloaded apt packages. 
```bash
./zquickinit.sh playground
```

## Architecture

## Goals
- Secure
- Easy to build, customize
- Remote access to enter/load encryption keys
- Box must work behind NAT 
- Support Proxmox as a first class environment
- Rescue/Install scenarios
## Non-Goals
- Speed
  - it boots in less than <5 seconds (in QEMU at least)
    - it doesn't need to be faster
- Size 
  - its currently producing images around ~80MB
    - could be smaller, but its 2023. 
- Memory efficiency 
  - the initramfs is loaded into RAM at least twice
    - but I don't care ;-)

## Security Considerations
**Important!**

Anything you put in an initramfs image like `ZFSBootMenu` will be stored unencrypted. What this means is that you should treat these keys as untrusted. 

For Tailscale, you should create a new node dedicated to `ZFSBootMenu`, and then configure ACLs to only allow incoming access to that node. Note: even tho this node won't be able to access the rest of your network, Tailscale will leak information about the status and tailnet IPs of the nodes on your network. 

### To create a new tailscale node: 
```bash
zquickinit.sh tailscale
```

Here's an example ACL: 
```jsonc
{
	"nodeAttrs": [
		{
			"target": ["tag:allowfunnel"],
			"attr":   ["funnel"],
		},
	],
	"tagOwners": {
		"tag:incomingonly": ["autogroup:admin"],
		"tag:allaccess":    ["autogroup:admin"],
		"tag:allowfunnel":  ["autogroup:admin"],
	},
	"acls": [
		# only allow nodes tagged with allaccess to egress
		{"action": "accept", "src": ["tag:allaccess"], "dst": ["*:*"]},
		# to allow webttyd ingress
		{"action": "accept", "src": ["*"], "dst": ["*:80"]}
	],
	"ssh": [
		{
			"action": "accept",
			"src":    ["tag:allaccess"],
			"dst":    ["tag:incomingonly"],
			"users":  ["autogroup:nonroot", "root"],
		},
		{
			"action": "accept",
			"src":    ["tag:allaccess"],
			"dst":    ["tag:allaccess"],
			"users":  ["autogroup:nonroot", "root"],
		},
	],
}

```
## Recipes

### zquick_core
Required dependencies, you can't remove this. 

### zquick_loadkey
 * Patches `zfsbootmenu-core.sh`
   * Prompts to unlock encrypted ZFS dataset. 
   * Then injects the passphrase into the boot environment to prevent prompting twice.
 
### zquick_net
Defines Hooks: 
  * `/zquick/hooks/ifup.d`
  * `/zquick/hooks/ifdown.d`

Uses Hooks: 
  * `/zquick/hooks/reboot.d`
    * Brings down interfaces
  * `/libexec/hooks/early-setup.d`
    * Starts network interfaces/DHCP

### zquick_tailscale
  * Installs `tailscale` configured as SSH server

Uses Hooks: 
  * `/zquick/hooks/ifup.d`
	* Starts tailscale
  * `/zquick/hooks/ifdown.d`
	* Kills ssh sessions

Config Files: 
* `tailscaled.state` -> `/var/lib/tailscale/tailscaled.state`
* `tailscaled.conf` -> `/etc/tailscale/tailscaled.conf`

### zquick_sshd
  * Installs `sshd` configured as a server running on a local interface

Uses Hooks: 
  * `/zquick/hooks/ifup.d`
	* Starts sshd

Config Files: 
* `ssh_host_ed25519_key` -> `/etc/ssh/ssh_host_ed25519_key`
* `ssh_host_ecdsa_key` -> `/etc/ssh/ssh_host_ecdsa_key`
* `ssh_host_rsa_key` -> `/etc/ssh/ssh_host_rsa_key`
* `authorized_keys` -> `/root/.ssh/authorized_keys`

### zquick_tmux
  * Patches `zfsbootmenu-preinit.sh` to run the entire `zfsbootmenu` script within a `tmux` session. 
  * The tmux status bar will display status like hostname, tailnet name, and webttyd status. 

Uses Hooks: 
  * `/zquick/hooks/bash.d`
    * Starting bash will automatically join the existing session (excluding nested sessions).
 
### zquick_ttyd
  * Runs a web-based `ttyd` over tailscale [funnel](https://tailscale.com/kb/1223/tailscale-funnel/). 
  * Wait, what? You serious??  
	* Its "secure-enough" in my opinion
	* Generates a random 32 character URL
	* Sets up `ttyd` to only respond to that URL
	* Send push notification to your phone using [Pushover](https://pushover.net/)
	* Notification has a link to random URL
	* `ttyd` server will be killed after 30 minutes

Uses Hooks: 
  * `/zquick/hooks/ifup.d`
  * `/zquick/hooks/ifdown.d`

Config Properties (in zquickinit.conf) 
`
PUSHOVER_APP_TOKEN=aabbccddaabbccddaabbccdd
PUSHOVER_USER_KEY=aabbccddaabbccddaabbccdd
`

### zquick_installer
  * Provides script `zquick_installer.sh` 
    * Partitioning
    * Creating ZFS root pools/datasets
    * Installs proxmox
  * Encrypting existing uncrypted ZFS root pool/dataset

### zquick_qemu
  * Should only be used for testing. Not present in release image. 
  * Will mount `cache` and `.` to `/mnt/cache` and `/mnt/qemu-host` over 9p filesystem

### zquick_reboot
Defines Hooks: 
  * `/zquick/hooks/reboot.d`
* Reboot command. 
  * Unmounts filesystems. 
  * Invokes hooks in `/zquick/hooks/reboot.d*`

### zquick_hostname
Sets hostname.

Config files: 
  * `hostname` -> `/etc/hostname`

### zquick_editors
  * vim
  * nano

### zquick_netextras
  * ssh
  * sshd
  * curl
  * wget
  * nc
  * w
  * nmap
  * ncat

### zquick_consolefont
  * Sets font to ter-v16b, local console only.

### zquick_fsextras
Bunch of filesystem related utilities, including partitioning, efibootmgr, disk usage, etc. 
