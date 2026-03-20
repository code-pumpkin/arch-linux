#!/bin/bash
VPN_DIR="${VPN_DIR:-$HOME/vpn}"
DEBUG_LOG="/tmp/vpn-debug.log"
CONNECT_SCRIPT="$HOME/.config/polybar/vpnConnect.exp"

debug() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$DEBUG_LOG"
}

check_vpn() {
    if pgrep -x "openvpn" > /dev/null; then
        echo "vpn ON"
        return 0
    else
        echo "vpn OFF"
        return 1
    fi
}

start_vpn() {
    # List .ovpn files in ~/vpn/
    local profiles
    profiles=$(find "$VPN_DIR" -maxdepth 1 -name '*.ovpn' -printf '%f\n' 2>/dev/null | sort)

    if [ -z "$profiles" ]; then
        notify-send "VPN" "No .ovpn profiles found in $VPN_DIR" -u critical
        return 1
    fi

    local count
    count=$(echo "$profiles" | wc -l)

    local selected
    if [ "$count" -eq 1 ]; then
        selected="$profiles"
    else
        selected=$(echo "$profiles" | rofi -dmenu -i -p "VPN Profile:" 2>/dev/null)
    fi

    [ -z "$selected" ] && return 1

    debug "Starting VPN with $selected"
    nohup expect "$CONNECT_SCRIPT" "$VPN_DIR/$selected" >/dev/null 2>&1 &
    sleep 2
    check_vpn
}

case "$1" in
    "status")
        check_vpn
        ;;
    *)
        if check_vpn; then
            debug "Stopping VPN..."
            sudo killall openvpn 2>/dev/null
            echo "VPN OFF"
        else
            start_vpn
        fi
        ;;
esac
