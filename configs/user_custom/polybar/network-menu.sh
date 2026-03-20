#!/bin/bash

# WiFi connection
connect_wifi() {
  NETWORKS=$(nmcli -t -f SSID dev wifi list 2>/dev/null | sort -u | grep -v '^$')
  SELECTED=$(echo "$NETWORKS" | rofi -dmenu -i -p "📶 Select WiFi:" 2>/dev/null)
  
  if [ -n "$SELECTED" ]; then
    PASSWORD=$(rofi -dmenu -i -p "Password for $SELECTED:" -password 2>/dev/null)
    if [ -n "$PASSWORD" ]; then
      nmcli device wifi connect "$SELECTED" password "$PASSWORD" 2>/dev/null
      notify-send "WiFi" "Connected to $SELECTED"
    fi
  fi
}

# Ethernet connection
connect_ethernet() {
  ETH_DEVICE=$(nmcli -t -f DEVICE dev status 2>/dev/null | grep ethernet | head -1)
  if [ -n "$ETH_DEVICE" ]; then
    nmcli device connect "$ETH_DEVICE" 2>/dev/null
    notify-send "Ethernet" "Connected to $ETH_DEVICE"
  fi
}

# VPN toggle
toggle_vpn() {
  if pgrep -x openvpn >/dev/null 2>/dev/null; then
    killall openvpn 2>/dev/null
    notify-send "VPN" "Disconnected"
  else
    if [ -f ~/.config/polybar/vpnTrigger.sh ]; then
      ~/.config/polybar/vpnTrigger.sh
      notify-send "VPN" "Connecting..."
    else
      notify-send "VPN" "vpnTrigger.sh not found"
    fi
  fi
}

# Show IPs
show_ips() {
  IP_INFO=$(ip -br addr | grep -v lo | awk '{print $1": " $3}')
  notify-send "Network IPs" "$IP_INFO" -t 5000
}

# Show public IP
show_public_ip() {
  PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "Unable to fetch")
  notify-send "Public IP" "$PUBLIC_IP" -u critical
}

# Show network traffic
show_traffic() {
  # Show loading message
  echo "Measuring for 5 seconds..." | rofi -dmenu -i -p "📊 Network Traffic:" 2>/dev/null &
  ROFI_PID=$!
  
  INTERFACES=$(ip -br link | grep -v lo | awk '{print $1}')
  
  TRAFFIC_INFO=""
  
  for iface in $INTERFACES; do
    RX1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    TX1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
  done
  
  sleep 5
  
  for iface in $INTERFACES; do
    RX2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    TX2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    
    RX_DIFF=$((RX2 - RX1))
    TX_DIFF=$((TX2 - TX1))
    
    # Calculate speed (KB/s)
    RX_SPEED=$(awk "BEGIN {printf \"%.2f\", $RX_DIFF / 5 / 1024}")
    TX_SPEED=$(awk "BEGIN {printf \"%.2f\", $TX_DIFF / 5 / 1024}")
    
    # Show all interfaces with status
    if [ $RX_DIFF -gt 0 ] || [ $TX_DIFF -gt 0 ]; then
      STATUS="🟢"
    else
      STATUS="⚪"
    fi
    
    TRAFFIC_INFO="${TRAFFIC_INFO}${STATUS} ${iface}: ↓${RX_SPEED}KB/s ↑${TX_SPEED}KB/s\n"
  done
  
  kill $ROFI_PID 2>/dev/null
  echo -e "$TRAFFIC_INFO" | rofi -dmenu -i -p "📊 Last 5 seconds:" -lines 10 2>/dev/null
}

# Rescan WiFi
rescan_wifi() {
  nmcli device wifi rescan 2>/dev/null
  notify-send "WiFi" "Rescanning..."
}

# Main menu
SELECTED=$(echo -e "📶 Connect WiFi\n🔌 Ethernet\n🌐 VPN Toggle\n📋 Show IPs\n🌍 Public IP\n📊 Network Traffic\n🔄 Rescan" | rofi -dmenu -i -p "Network:" -lines 7 2>/dev/null)

case "$SELECTED" in
*"Connect WiFi")
  connect_wifi
  ;;
*"Ethernet")
  connect_ethernet
  ;;
*"VPN Toggle")
  toggle_vpn
  ;;
*"Show IPs")
  show_ips
  ;;
*"Public IP")
  show_public_ip
  ;;
*"Network Traffic")
  show_traffic
  ;;
*"Rescan")
  rescan_wifi
  ;;
esac
