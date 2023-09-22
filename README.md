# EZ-ZFSBootMenu Recipes

This is an ***opinionated*** but ***extrememly*** easy to use ZFSBootMenu builder. You can easily produce customized ZFSBootMenu images using independent, composeable modules that I'm calling recipes. 

[ZFSBootMenu](https://zfsbootmenu.org/) is great! Its really flexible. Supports two different initramfs generators, and it can build on dozens of distributions. All of this flexibility was overwhelming when I was getting started writing my own customized ZFSBootMenu. So, I made it simple. 

Instead of dozens of dependencies, there is only one. Docker (or Podman). 

To build an image, you need need one command: 

```
docker run -it -v .:/output midzelis/ez-zfsbootmenu-builder
```

This will take you through an interactive configuration screen and drop the newly generated images in your current directory. 

Thats it! You can stop reading here. 

## Goals
- Secure
- Easy to build, customize
- Support ProxMox as a first class environment
- Remote unlocks that support server behind NAT 

## Non-Goals
- Speed, it boots in less than 2 seconds, and it doesn't need to be faster. 
- Size - its currently producing images around ~71MB
- Memory efficiency - the initramfs is loaded into RAM at least twice. 

## Security Considerations
***Important*** 
Anything you put in an initramfs image like ZFSBootMenu will be stored unencrypted. What this means is that you should treat these keys as untrusted. 

For Tailscale, you should create a new node dedicated to ZFSBootMenu, and then configure ACLs to only allow incoming access to that node. Note: even tho this node won't be able to access the rest of your network, Tailscale will leak information about the status and tailnet IPs of the nodes on your network. 

To create a node: 
```
mkdir -p state ; docker run -it -e TS_EXTRA_ARGS=--ssh -e TS_STATE_DIR=/state -v "$(pwd)"/state:/state tailscale/tailscale ; mv state/tailscaled.state "$(pwd)" ; rm -rf state
```

Here's an example ACL: 
```

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

### ez_core
Required dependencies.

### ez_loadkey
Prompts to unlock encrypted ZFS dataset. Then injects the passphrase into the boot environment to prevent prompting twice. Note: patches ZFSBootMenu source. 

### ez_net
Brings up all network interfaces, starts DHCP, invokes hooks in `/ez_recipes/ez_ifup.d/*` (which include starting tailscale, webttyd)

### ez_tailscale
Installs `tailscale` and uses it as exclusive SSH server, and Funnel capabilities. (Funnel requires ca-certificates)

### ez_tmux
Runs the entire zfsbootmenu script within a tmux session. Modifies the .bashrc to automatically join the existing session (excluding nested sessions). The tmux status bar will display status like hostname, tailnet name, and webttyd status. Note: patches ZFSBootMenu source. 

### ez_webttyd
Runs a web-based TTYD over tailscale funnel. Wha?? Its "secure-enough" in my opinion. The way it works is that is generates a random 32 character URL, and then sets up `ttyd` to only respond to that URL. It then pushes a notification to your phone using pushover with a link to this randomly generated path. The ttyd server will automatically be killed after 30 minutes. 

### ez_reboot
Reboot command. Unmounts filesystems. Invokes hooks in `/ez_recipes/reboot.d/*`, which include shutting down SSH sessions nicely. 

### ez_hostname
Sets hostname.

### ez_misc
Includes vim and nano.

### ez_netextras
Includes ssh client, curl, wget, nc, and w.

### ez_consolefont
Sets font to lat1-16, which includes cp437 box-drawing characters. 

### ez_fsextras
Bunch of filesystem related utilities, including partitioning, efibootmgr, disk usage, etc. 
