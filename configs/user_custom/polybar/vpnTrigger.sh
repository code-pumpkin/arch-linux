#!/bin/bash
# Save as vpn-control.sh

DEBUG_LOG="/tmp/vpn-debug.log"
DAEMON_SCRIPT="/home/hafeezh/scripts/polybar/vpnConnect.exp"

debug() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$DEBUG_LOG"
}

check_vpn() {
    if pgrep -x "openvpn" > /dev/null; then
        echo "vpn ON"
        debug "VPN is running"
        return 0
    else
        echo "vpn OFF"
        debug "VPN is not running"
        return 1
    fi
}

case "$1" in
    "status")
        check_vpn
        ;;
    *)
        if check_vpn; then
            debug "Stopping VPN..."
            killall openvpn
            echo "VPN OFF"
        else
            debug "Starting VPN..."
            nohup expect $DAEMON_SCRIPT >/dev/null 2>&1 &
            sleep 2
            check_vpn
        fi
        ;;
esac
