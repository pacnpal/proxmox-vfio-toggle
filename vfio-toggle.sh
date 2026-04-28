#!/bin/bash
# vfio-toggle.sh - toggle Proxmox AMD GPU between VFIO passthrough and amdgpu modes.
#
# Usage:
#   vfio-toggle.sh                run interactive menu
#   vfio-toggle.sh --enable       enable VFIO passthrough (GPU dedicated to VM)
#   vfio-toggle.sh --disable      disable VFIO (load amdgpu, GPU shared with LXCs)
#   vfio-toggle.sh --status       print current mode and exit
#   vfio-toggle.sh --install      install self to /usr/local/sbin/vfio-toggle.sh
#   vfio-toggle.sh --uninstall    remove installed copy from /usr/local/sbin
#   vfio-toggle.sh --help         this help
#
# Run-on-the-fly one-liners (no install needed):
#   curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --enable
#   curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --disable
#   curl -fsSL https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh | sudo bash -s -- --install
#
# Enable and disable rebuild initramfs and reboot after a 10 second countdown.

set -e

VFIO_CONF=/etc/modprobe.d/vfio.conf
VFIO_OFF_CONF=/etc/modprobe.d/vfio-off.conf
BLACKLIST=/etc/modprobe.d/blacklist.conf

SELF_URL="https://pacnpal.github.io/proxmox-vfio-toggle/vfio-toggle.sh"
INSTALL_PATH="/usr/local/sbin/vfio-toggle.sh"

print_help() {
    cat <<'EOF'
vfio-toggle.sh - toggle Proxmox AMD GPU between VFIO passthrough and amdgpu modes.

Usage:
  vfio-toggle.sh                run interactive menu
  vfio-toggle.sh --enable       enable VFIO passthrough (GPU dedicated to VM)
  vfio-toggle.sh --disable      disable VFIO (load amdgpu, GPU shared with LXCs)
  vfio-toggle.sh --status       print current mode and exit
  vfio-toggle.sh --install      install self to /usr/local/sbin/vfio-toggle.sh
  vfio-toggle.sh --uninstall    remove installed copy from /usr/local/sbin
  vfio-toggle.sh --help         this help

Both --enable and --disable rebuild initramfs and reboot after a 10 second
countdown. Press Ctrl+C during the countdown to abort the reboot.

The script is self contained: you can run it once via curl without installing,
or use --install (or option 3 in interactive mode) to drop it into
/usr/local/sbin/vfio-toggle.sh for repeated use.
EOF
}

current_mode() {
    if [[ -f "$VFIO_CONF" && -f "$VFIO_OFF_CONF" ]] && \
       grep -Eq '^[[:space:]]*blacklist[[:space:]]+amdgpu' "$BLACKLIST" 2>/dev/null; then
        echo enabled
        return
    fi
    if [[ -f "${VFIO_CONF}.disabled" && -f "${VFIO_OFF_CONF}.disabled" ]] && \
       grep -Eq '^[[:space:]]*#[[:space:]]*blacklist[[:space:]]+amdgpu' "$BLACKLIST" 2>/dev/null; then
        echo disabled
        return
    fi
    echo unknown
}

print_status() {
    case "$(current_mode)" in
        enabled)  echo "VFIO passthrough: ENABLED  (vfio.conf active, amdgpu blacklisted)" ;;
        disabled) echo "VFIO passthrough: DISABLED (vfio*.conf.disabled, amdgpu loadable)" ;;
        *)        echo "VFIO passthrough: UNKNOWN  (state files not in the expected layout)" ;;
    esac
}

countdown_and_reboot() {
    local msg="$1"
    echo
    echo "============================================================"
    echo "$msg SYSTEM WILL REBOOT IN 10 SECONDS."
    echo "Press Ctrl+C to abort."
    echo "============================================================"
    for i in 10 9 8 7 6 5 4 3 2 1; do
        echo -n "$i... "
        sleep 1
    done
    echo
    echo "[+] rebooting now"
    reboot
}

do_enable() {
    echo "[+] restoring vfio modprobe configs..."
    [[ -f "${VFIO_OFF_CONF}.disabled" ]] && \
        mv "${VFIO_OFF_CONF}.disabled" "${VFIO_OFF_CONF}"
    [[ -f "${VFIO_CONF}.disabled" ]] && \
        mv "${VFIO_CONF}.disabled" "${VFIO_CONF}"

    echo "[+] re-blacklisting amdgpu..."
    sed -i 's|^#\s*blacklist amdgpu|blacklist amdgpu|' "$BLACKLIST"
    sed -i 's|^#\s*softdep amdgpu pre: vfio-pci|softdep amdgpu pre: vfio-pci|' "$BLACKLIST"

    echo "[+] rebuilding initramfs..."
    update-initramfs -u

    countdown_and_reboot "VFIO passthrough enabled."
}

do_disable() {
    echo "[+] disabling vfio modprobe configs..."
    [[ -f "${VFIO_OFF_CONF}" ]] && \
        mv "${VFIO_OFF_CONF}" "${VFIO_OFF_CONF}.disabled"
    [[ -f "${VFIO_CONF}" ]] && \
        mv "${VFIO_CONF}" "${VFIO_CONF}.disabled"

    echo "[+] commenting out amdgpu blacklist..."
    sed -i 's|^blacklist amdgpu|#blacklist amdgpu|' "$BLACKLIST"
    sed -i 's|^softdep amdgpu pre: vfio-pci|#softdep amdgpu pre: vfio-pci|' "$BLACKLIST"

    echo "[+] rebuilding initramfs..."
    update-initramfs -u

    countdown_and_reboot "VFIO passthrough disabled."
}

# Try to find a real local copy of this script. Returns the path on stdout
# (or empty when running via curl|bash where $0 is "bash" or "-").
self_source() {
    if [[ -n "${BASH_SOURCE[0]:-}" && -r "${BASH_SOURCE[0]}" && -f "${BASH_SOURCE[0]}" ]]; then
        if head -n 1 "${BASH_SOURCE[0]}" 2>/dev/null | grep -q '^#!'; then
            printf '%s\n' "${BASH_SOURCE[0]}"
            return
        fi
    fi
    printf ''
}

do_install() {
    local target_dir
    target_dir=$(dirname "$INSTALL_PATH")

    if [[ ! -d "$target_dir" ]]; then
        echo "install dir $target_dir does not exist" >&2
        return 1
    fi

    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/vfio-toggle.XXXXXX")
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN

    local src
    src=$(self_source)
    if [[ -n "$src" ]]; then
        echo "[+] installing from local source: $src"
        cp "$src" "$tmp"
    else
        echo "[+] fetching latest from $SELF_URL"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$SELF_URL" -o "$tmp"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$tmp" "$SELF_URL"
        else
            echo "need curl or wget to fetch the script" >&2
            return 1
        fi
    fi

    if ! head -n 1 "$tmp" | grep -q '^#!'; then
        echo "fetched/copied file does not look like a script (no shebang)" >&2
        return 1
    fi

    install -m 0755 "$tmp" "$INSTALL_PATH"
    echo "[+] installed $INSTALL_PATH"
    echo
    echo "Run as root:"
    echo "  vfio-toggle.sh                  # interactive menu"
    echo "  vfio-toggle.sh --enable         # enable VFIO passthrough"
    echo "  vfio-toggle.sh --disable        # disable VFIO (load amdgpu)"
    echo "  vfio-toggle.sh --status         # show current mode"
}

do_uninstall() {
    if [[ -f "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
        echo "[+] removed $INSTALL_PATH"
    else
        echo "nothing to remove at $INSTALL_PATH"
    fi
}

interactive_menu() {
    echo "proxmox-vfio-toggle"
    echo
    print_status
    echo

    local installed_marker installed=0
    if [[ -f "$INSTALL_PATH" ]]; then
        installed=1
        installed_marker="installed at $INSTALL_PATH"
    else
        installed_marker="not installed at $INSTALL_PATH"
    fi

    local src
    src=$(self_source)
    if [[ -n "$src" && "$src" != "$INSTALL_PATH" ]]; then
        echo "Running on the fly from: $src"
    elif [[ -z "$src" ]]; then
        echo "Running on the fly (piped via curl | bash, no on-disk copy)."
    else
        echo "Running from installed copy: $src"
    fi
    echo "Status: $installed_marker"
    echo

    echo "Choose action:"
    echo "  1) Enable  VFIO passthrough  (GPU dedicated to VM)"
    echo "  2) Disable VFIO passthrough  (amdgpu loaded, GPU shared with LXCs)"
    if [[ $installed -eq 0 ]]; then
        echo "  3) Install to $INSTALL_PATH"
    else
        echo "  3) Reinstall (overwrite $INSTALL_PATH with this version)"
    fi
    echo "  4) Uninstall ($INSTALL_PATH)"
    echo "  q) Quit without changes"
    echo

    local choice
    read -rp "> " choice
    case "$choice" in
        1|e|E|enable)    do_enable ;;
        2|d|D|disable)   do_disable ;;
        3|i|I|install)   do_install ;;
        4|u|U|uninstall) do_uninstall ;;
        q|Q|quit|"")     echo "aborted, no changes made" ; exit 0 ;;
        *)               echo "unknown choice: $choice" >&2 ; exit 2 ;;
    esac
}

# --- args ---
ACTION=interactive
for arg in "$@"; do
    case "$arg" in
        --enable|-e)    ACTION=enable ;;
        --disable|-d)   ACTION=disable ;;
        --status|-s)    ACTION=status ;;
        --install|-i)   ACTION=install ;;
        --uninstall|-u) ACTION=uninstall ;;
        --help|-h)      ACTION=help ;;
        *)
            printf 'vfio-toggle: unknown argument: %s (try --help)\n' "$arg" >&2
            exit 2
            ;;
    esac
done

if [[ "$ACTION" == help ]]; then
    print_help
    exit 0
fi

if [[ "$ACTION" == status ]]; then
    print_status
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
fi

case "$ACTION" in
    enable)      do_enable ;;
    disable)     do_disable ;;
    install)     do_install ;;
    uninstall)   do_uninstall ;;
    interactive) interactive_menu ;;
esac
