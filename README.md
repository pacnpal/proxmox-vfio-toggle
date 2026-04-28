# proxmox-vfio-toggle

[![shellcheck](https://github.com/pacnpal/proxmox-vfio-toggle/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/pacnpal/proxmox-vfio-toggle/actions/workflows/shellcheck.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![shell: bash](https://img.shields.io/badge/shell-bash-success)
![platform: Proxmox VE](https://img.shields.io/badge/platform-Proxmox%20VE-orange)

One bash script that toggles a Proxmox host between **VFIO passthrough mode** (GPU dedicated to a VM) and **shared mode** (amdgpu loaded so the GPU can be passed to LXCs).

Homepage: <https://pacnpal.github.io/proxmox-vfio-toggle/>

## Why this exists

Proxmox AMD homelabs often need to swap between dedicating the iGPU to a Windows or gaming VM and sharing it with LXCs for workloads like Ollama, Jellyfin, or Frigate. Doing it by hand means renaming modprobe files, editing the blacklist, rebuilding initramfs, and rebooting in the right order. Easy to forget a step. This script makes the switch one command.

## Tested on

- Proxmox VE 9.x
- AMD Ryzen 7040 series (Phoenix1) with Radeon 780M iGPU
- Kernel 6.17.13-1-pve

Should work on any AMD GPU once the PCI IDs in your existing modprobe configs match your card.

## Quick start

Pick your flavor. All of these run as root on the Proxmox host.

### Run on the fly (no install)

Interactive menu:

```sh
curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh -o /tmp/vfio-toggle.sh \
  && sudo bash /tmp/vfio-toggle.sh
```

Direct enable / disable:

```sh
curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --enable
curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --disable
```

### Install for repeated use

```sh
curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --install
```

This drops the script at `/usr/local/sbin/vfio-toggle.sh` and chmods it `0755`. After that:

```sh
sudo vfio-toggle.sh                # interactive menu
sudo vfio-toggle.sh --enable       # enable VFIO passthrough
sudo vfio-toggle.sh --disable      # disable VFIO (load amdgpu)
sudo vfio-toggle.sh --status       # print current mode (read-only)
```

### Uninstall

```sh
curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --uninstall
# or, if you've installed it
sudo vfio-toggle.sh --uninstall
```

## What it does

`--enable` (switch to VFIO passthrough):

- Renames `/etc/modprobe.d/vfio.conf.disabled` back to `vfio.conf`
- Renames `/etc/modprobe.d/vfio-off.conf.disabled` back to `vfio-off.conf`
- Uncomments `blacklist amdgpu` in `/etc/modprobe.d/blacklist.conf`
- Uncomments `softdep amdgpu pre: vfio-pci` in `/etc/modprobe.d/blacklist.conf`
- Runs `update-initramfs -u`
- Reboots after a 10 second countdown

`--disable` (switch to amdgpu / LXC):

- Renames `/etc/modprobe.d/vfio.conf` to `vfio.conf.disabled`
- Renames `/etc/modprobe.d/vfio-off.conf` to `vfio-off.conf.disabled`
- Comments out `blacklist amdgpu` in `/etc/modprobe.d/blacklist.conf`
- Comments out `softdep amdgpu pre: vfio-pci` in `/etc/modprobe.d/blacklist.conf`
- Runs `update-initramfs -u`
- Reboots after a 10 second countdown

`--status` reads those same files and prints `ENABLED`, `DISABLED`, or `UNKNOWN`. It does not write anything.

`--install` copies the running script to `/usr/local/sbin/vfio-toggle.sh`. When invoked through `curl | bash` (so there is no on-disk source to copy from), it re-fetches the script from the Pages URL.

`--uninstall` removes that copy.

## Verification

After the host comes back up, check which driver is bound to the GPU:

```sh
lspci -nnk -s <pci-addr>
```

Find the GPU PCI address with `lspci | grep VGA`. In VFIO mode you should see `Kernel driver in use: vfio-pci`. In shared mode you should see `Kernel driver in use: amdgpu`.

## Customization

The script assumes a working VFIO setup is already in place. To adapt it:

- **PCI device IDs**: hardcoded inside your existing `/etc/modprobe.d/vfio.conf`. The script does not edit IDs, it just enables or disables that file. Make sure your `vfio.conf` has the right `options vfio-pci ids=...` for your card.
- **LXC GPU passthrough**: if you pass the GPU to a container, stop the container and remove its `dev*` entries before running `--enable`, since the GPU cannot be bound to vfio-pci while a container is holding it.

## Caveats

- Assumes you already have a working VFIO setup with `/etc/modprobe.d/vfio.conf` and `/etc/modprobe.d/vfio-off.conf` in place. This is not a from-scratch VFIO configurator.
- Assumes amdgpu blacklist lines already exist in `/etc/modprobe.d/blacklist.conf`. The script toggles them on and off, it does not create them.
- `--enable` and `--disable` reboot automatically. Do not run them on a host with workloads that cannot tolerate a reboot.

## Idempotent

Safe to run repeatedly. Running `--enable` when already in VFIO mode (or `--disable` when already in shared mode) is a no-op aside from the initramfs rebuild and reboot.

## Development

Lint locally:

```sh
shellcheck --shell=bash vfio-toggle.sh
```

CI runs the same on every push to `main`.

Project layout:

```
.
├── vfio-toggle.sh            # the script
├── README.md                 # this file
├── index.html                # GitHub Pages landing page
├── assets/
│   └── logo.svg
├── .nojekyll                 # serve files raw, no Jekyll
└── .github/workflows/
    └── shellcheck.yml        # CI lint
```

## License

[MIT](LICENSE) © pacnpal
