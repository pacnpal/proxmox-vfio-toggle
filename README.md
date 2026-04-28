# proxmox-vfio-toggle

Two bash scripts that toggle a Proxmox host between VFIO passthrough mode (GPU dedicated to a VM) and shared mode (amdgpu driver loaded so the GPU can be passed to LXCs).

## Why this exists

Proxmox AMD homelabs often need to swap between dedicating the iGPU to a Windows/gaming VM and sharing it with LXCs for workloads like Ollama, Jellyfin, or Frigate. Doing it by hand means renaming modprobe files, editing the blacklist, rebuilding initramfs, removing container device entries, and rebooting in the right order. Easy to forget a step. These scripts make the switch one command.

## Tested on

- Proxmox VE 9.x
- AMD Ryzen 7040 series (Phoenix1) with Radeon 780M iGPU
- Kernel 6.17.13-1-pve

Should work on any AMD GPU once the PCI IDs in your existing modprobe configs match your card.

## Installation

```bash
cp vfio-enable.sh vfio-disable.sh /usr/local/sbin/
chmod +x /usr/local/sbin/vfio-enable.sh /usr/local/sbin/vfio-disable.sh
```

If `/usr/local/sbin` is not on your PATH, add it:

```bash
echo 'export PATH=$PATH:/usr/local/sbin' >> ~/.bashrc
source ~/.bashrc
```

## Usage

Switch to VFIO mode (GPU bound to vfio-pci, ready for VM passthrough):

```bash
sudo vfio-enable.sh
```

Switch to shared mode (amdgpu loaded, GPU available to LXCs):

```bash
sudo vfio-disable.sh
```

Both scripts reboot the host after a 10 second countdown. Press Ctrl+C during the countdown to abort.

## What each script changes

`vfio-enable.sh`:
- Renames `/etc/modprobe.d/vfio.conf.disabled` back to `vfio.conf`
- Renames `/etc/modprobe.d/vfio-off.conf.disabled` back to `vfio-off.conf`
- Uncomments `blacklist amdgpu` in `/etc/modprobe.d/blacklist.conf`
- Uncomments `softdep amdgpu pre: vfio-pci` in `/etc/modprobe.d/blacklist.conf`
- Stops CT 200 and removes its `dev0` and `dev1` passthrough entries if the container exists
- Runs `update-initramfs -u`
- Reboots

`vfio-disable.sh`:
- Renames `/etc/modprobe.d/vfio.conf` to `vfio.conf.disabled`
- Renames `/etc/modprobe.d/vfio-off.conf` to `vfio-off.conf.disabled`
- Comments out `blacklist amdgpu` in `/etc/modprobe.d/blacklist.conf`
- Comments out `softdep amdgpu pre: vfio-pci` in `/etc/modprobe.d/blacklist.conf`
- Runs `update-initramfs -u`
- Reboots

## Verification

After the host comes back up, check which driver is bound to the GPU:

```bash
lspci -nnk -s <pci-addr>
```

Find your GPU PCI address with `lspci | grep VGA`. In VFIO mode you should see `Kernel driver in use: vfio-pci`. In shared mode you should see `Kernel driver in use: amdgpu`.

## Customization

The scripts are tailored to one specific setup. If you want to use them, change the following:

- **PCI device IDs**: hardcoded inside your existing `/etc/modprobe.d/vfio.conf`. The scripts do not edit IDs, they just enable or disable that file. Make sure your `vfio.conf` has the right `options vfio-pci ids=...` for your card.
- **CT ID 200**: `vfio-enable.sh` references container 200 to strip the GPU passthrough entries before reboot. Change `200` in the script to your LXC ID, or remove that block if you do not pass the GPU to any LXC.

## Caveats

- Assumes you already have a working VFIO setup with `/etc/modprobe.d/vfio.conf` and `/etc/modprobe.d/vfio-off.conf` in place. This is not a from-scratch VFIO configurator.
- Assumes amdgpu blacklist lines already exist in `/etc/modprobe.d/blacklist.conf`. The scripts toggle them on and off, they do not create them.
- Reboots automatically. Do not run these on a host with workloads that cannot tolerate a reboot.

## Idempotent

Safe to run repeatedly. Running `vfio-enable.sh` when already in VFIO mode (or `vfio-disable.sh` when already in shared mode) is a no-op aside from the initramfs rebuild and reboot.

## License

MIT. See [LICENSE](LICENSE).
