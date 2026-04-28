#!/bin/bash
# Enable VFIO passthrough for AMD Phoenix1 iGPU
# Restores /etc/modprobe.d/vfio*.conf and blacklists amdgpu

set -e

if [[ $EUID -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
fi

echo "[+] restoring vfio modprobe configs..."
[[ -f /etc/modprobe.d/vfio-off.conf.disabled ]] && \
    mv /etc/modprobe.d/vfio-off.conf.disabled /etc/modprobe.d/vfio-off.conf
[[ -f /etc/modprobe.d/vfio.conf.disabled ]] && \
    mv /etc/modprobe.d/vfio.conf.disabled /etc/modprobe.d/vfio.conf

echo "[+] re-blacklisting amdgpu..."
sed -i 's|^#\s*blacklist amdgpu|blacklist amdgpu|' /etc/modprobe.d/blacklist.conf
sed -i 's|^#\s*softdep amdgpu pre: vfio-pci|softdep amdgpu pre: vfio-pci|' /etc/modprobe.d/blacklist.conf

echo "[+] stopping and removing GPU passthrough from CT 200 (if exists)..."
if pct status 200 &>/dev/null; then
    pct stop 200 2>/dev/null || true
    pct set 200 --delete dev0 2>/dev/null || true
    pct set 200 --delete dev1 2>/dev/null || true
fi

echo "[+] rebuilding initramfs..."
update-initramfs -u

echo
echo "============================================================"
echo "VFIO passthrough enabled. SYSTEM WILL REBOOT IN 10 SECONDS."
echo "Press Ctrl+C to abort."
echo "============================================================"
for i in 10 9 8 7 6 5 4 3 2 1; do
    echo -n "$i... "
    sleep 1
done
echo
echo "[+] rebooting now"
reboot
