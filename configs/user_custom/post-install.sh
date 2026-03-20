#!/bin/bash
# Post-install script for AUR/optional packages
# Run this after first boot: ~/post-install.sh

set -e

AUR_HELPER=""
for helper in paru yay; do
    if command -v "$helper" &>/dev/null; then
        AUR_HELPER="$helper"
        break
    fi
done

if [ -z "$AUR_HELPER" ]; then
    echo "ERROR: No AUR helper found (paru/yay). Install one first."
    exit 1
fi

echo "Using AUR helper: $AUR_HELPER"
echo ""

install_optional() {
    local pkg="$1"
    local desc="$2"
    read -rp "Install $pkg ($desc)? [y/n]: " ans
    if [ "$ans" = "y" ]; then
        $AUR_HELPER -S --noconfirm "$pkg"
    fi
}

# Voice dictation
install_optional "nerd-dictation-git" "Offline voice-to-text using VOSK"

# Input sharing (KVM-like)
install_optional "input-leap-git" "Share keyboard/mouse across machines (latest git)"

# RustDesk remote desktop
install_optional "rustdesk-bin" "Open-source remote desktop"

echo ""
echo "Done! Reboot if any kernel modules were installed."
