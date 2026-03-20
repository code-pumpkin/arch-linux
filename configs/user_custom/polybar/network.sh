#!/bin/bash

case $1 in
menu)
  ~/.config/polybar/network-menu.sh
  exit 0
  ;;
esac

# Check VPN status
VPN_STATUS=""
if pgrep -x openvpn >/dev/null 2>/dev/null || ip link show | grep -q tun0; then
  VPN_STATUS=$' %{T2}\uef82\uac%{T-}'
fi

ICON_ETH=$'%{T2}\uf796%{T-}'
ICON_WIFI=$'%{T2}\uf1eb%{T-}'
ICON_OFF=$'%{T2}\uf00d%{T-}'

# Check ethernet FIRST (desktop priority)
if nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | grep -q 'ethernet.*connected'; then
  echo "${ICON_ETH} ETH${VPN_STATUS}"
elif nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | grep -q 'wifi.*connected'; then
  SSID=$(nmcli -g NAME connection show --active 2>/dev/null | head -1)
  [ -z "$SSID" ] && SSID="WiFi"

  # Get signal strength percentage from wifi list
  STRENGTH=$(nmcli dev wifi list 2>/dev/null | grep "$SSID" | awk '{print $(NF-2)}' | head -1)

  if [ -z "$STRENGTH" ]; then
    echo "${ICON_WIFI} ${SSID}${VPN_STATUS}"
  else
    echo "${ICON_WIFI} ${SSID} ${STRENGTH}%${VPN_STATUS}"
  fi
else
  echo "${ICON_OFF} OFF"
fi
