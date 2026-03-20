#!/bin/bash

# Default timezones for polybar display
UAE_TZ="Asia/Dubai"
NL_TZ="America/St_Johns"

# All available timezones for menu
declare -A TIMEZONES=(
  ["UAE"]="Asia/Dubai"
  ["Netherlands"]="Europe/Amsterdam"
  ["New York"]="America/New_York"
  ["Los Angeles"]="America/Los_Angeles"
  ["London"]="Europe/London"
  ["Tokyo"]="Asia/Tokyo"
  ["Sydney"]="Australia/Sydney"
  ["Singapore"]="Asia/Singapore"
  ["India"]="Asia/Kolkata"
  ["Brazil"]="America/Sao_Paulo"
)

case $1 in
menu)
  # Show rofi menu with all timezones
  SELECTED=$(printf '%s\n' "${!TIMEZONES[@]}" | sort | rofi -dmenu -i -p "Select Timezone:" 2>/dev/null)
  
  if [ -n "$SELECTED" ]; then
    TZ_VALUE="${TIMEZONES[$SELECTED]}"
    TZ_TIME=$(TZ="$TZ_VALUE" date +'%H:%M %a %m/%d')
    notify-send "🌍 $SELECTED" "$TZ_TIME" -u low -t 3000
  fi
  ;;
notify)
  # Show all timezones in notify-send
  NOTIFY_TEXT=""
  for country in "${!TIMEZONES[@]}"; do
    TZ_VALUE="${TIMEZONES[$country]}"
    TZ_TIME=$(TZ="$TZ_VALUE" date +'%H:%M')
    NOTIFY_TEXT="$NOTIFY_TEXT$country: $TZ_TIME\n"
  done
  notify-send "🌍 All Timezones" "$(echo -e "$NOTIFY_TEXT")" -u low -t 5000
  ;;
*)
  # Display UAE and NL by default with country names
  uae_time=$(TZ="$UAE_TZ" date +'%H:%M')
  nl_time=$(TZ="$NL_TZ" date +'%H:%M %m/%d')
  echo "${uae_time} | ${nl_time}"
  ;;
esac
