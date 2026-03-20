#!/bin/bash

BAT_PATH="/sys/class/power_supply/BAT0"
CAPACITY=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo 0)
STATUS=$(cat "$BAT_PATH/status" 2>/dev/null || echo "Unknown")
ENERGY_NOW=$(cat "$BAT_PATH/energy_now" 2>/dev/null || echo 0)
ENERGY_FULL=$(cat "$BAT_PATH/energy_full" 2>/dev/null || echo 1000000)
POWER_NOW=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo 0)

# Safe time calculation
if [ "$POWER_NOW" -gt 0 ] 2>/dev/null && [ "$ENERGY_NOW" -gt 0 ] 2>/dev/null; then
  TIME_SEC=$(((ENERGY_NOW * 3600) / POWER_NOW))
  HOURS=$((TIME_SEC / 3600))
  MINS=$(((TIME_SEC % 3600) / 60))
  TIME="${HOURS}h${MINS}m"
else
  TIME=""
fi

case "$STATUS" in
"Charging")
  echo "%{T2}%{T-} C ${CAPACITY}% ${TIME}"
  ;;
"Discharging")
  echo "%{T2}%{T-} D ${CAPACITY}% ${TIME}"
  ;;
"Not charging"|"Full")
  echo "%{T2}%{T-} F ${CAPACITY}%"
  ;;
*)
  echo "%{T2}%{T-} ${CAPACITY}%"
  ;;
esac
