#!/bin/bash
# Disable VFIO passthrough for AMD Phoenix1 iGPU
# Allows amdgpu driver to bind so the GPU can be shared with LXCs

set -e

if [[ $EUID -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
fi

echo "[+] disabling vfio modprobe configs..."
[[ -f /etc/modprobe.d/vfio-off.conf ]] && \
    mv /etc/modprobe.d/vfio-off.conf /etc/modprobe.d/vfio-off.conf.disabled
[[ -f /etc/modprobe.d/vfio.conf ]] && \
    mv /etc/modprobe.d/vfio.conf /etc/modprobe.d/vfio.conf.disabled

echo "[+] commenting out amdgpu blacklist..."
sed -i 's|^blacklist amdgpu|#blacklist amdgpu|' /etc/modprobe.d/blacklist.conf
sed -i 's|^softdep amdgpu pre: vfio-pci|#softdep amdgpu pre: vfio-pci|' /etc/modprobe.d/blacklist.conf

echo "[+] rebuilding initramfs..."
update-initramfs -u

echo
echo "============================================================"
echo "VFIO passthrough disabled. SYSTEM WILL REBOOT IN 10 SECONDS."
echo "Press Ctrl+C to abort."
echo "============================================================"
for i in 10 9 8 7 6 5 4 3 2 1; do
    echo -n "$i... "
    sleep 1
done
echo
echo "[+] rebooting now"
reboot
