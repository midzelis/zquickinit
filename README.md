# EZ-ZFSBootMenu Recipes

This is an ***opinionated*** but ***extrememly*** easy to use ZFSBootMenu builder (in my opinion). You can just download the image directly and get started, orproduce customized ZFSBootMenu images using independent, composeable modules that I'm calling recipes. 

[ZFSBootMenu](https://zfsbootmenu.org/) is great! Its really flexible. Supports two different initramfs generators, and it can build on dozens of distributions. All of this flexibility was overwhelming when I was getting started writing my own customized ZFSBootMenu. So, I made it simple. 

Instead of dozens of dependencies, there is only one. Docker (or Podman). 

To build an image, you need need one command: 

```
docker run -it -v .:/output midzelis/ez-zfsbootmenu-builder
```

This will take you through an interactive configuration screen and drop the newly generated images in your current directory. 

Thats it! You can stop reading here. 

## Specifics

The Hero Recipe is `ez_tailscale`

### ez_tailscale: Tailscale Enabled Remote Unlocker 
#### ZFS Natively Encrypted Root Pools with initrd key injection

* Secure remote unlocking - Never stores keys anywhere! Handles Evil Maid Attacks!
* Uses Tailscale to support NAT'ed locations
* Supports ProxMox - Uses a generic build (Using existing void linux configuration) - which chainloads the proxmox initramfs. 
  * It decrypts the pool containing ProxMox initrd and kernel images, and then injects the manually user-intered key into the ProxMox initrd image (completely in memory) - before loading it. 
* Uses Tailscale SSH - no need to have your own SSHd server running. 

#### Configuration - Important Security Consideration!
The installer will prompt you for your tailscale node identifier, which is stored in the file 'tailscaled.state'. I highly recommend creating a dedicated tailscale node for this `ZFSBootMenu` - because this node identifier is stored encrypted, and if anyone got a hold of it, they can impersonate you on your tailnet. 

Here's an example ACL: 
```

{
	"tagOwners": {
		"tag:incomingonly": ["autogroup:admin"],
		"tag:allaccess":    ["autogroup:admin"],
	},
	"acls": [
		{"action": "accept", "src": ["tag:allaccess"], "dst": ["*:*"]},
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

The configuration wizard will prompt your for your tailscaled.state file. If you need to generate one, use this 1 liner. 

```
mkdir -p state ; docker run -it -e TS_EXTRA_ARGS=--ssh -e TS_STATE_DIR=/state -v "$(pwd)"/state:/state tailscale/tailscale ; mv state/tailscaled.state "$(pwd)" ; rm -rf state
```



  
