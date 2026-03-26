#!/bin/bash

# Read timezones from zshrc config, fall back to defaults
TZ1="${POLYBAR_TZ1:-America/New_York}"
TZ2="${POLYBAR_TZ2:-Asia/Tokyo}"

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
  SELECTED=$(printf '%s\n' "${!TIMEZONES[@]}" | sort | rofi -dmenu -i -p "Select Timezone:" 2>/dev/null)
  if [ -n "$SELECTED" ]; then
    TZ_VALUE="${TIMEZONES[$SELECTED]}"
    TZ_TIME=$(TZ="$TZ_VALUE" date +'%H:%M %a %m/%d')
    notify-send "🌍 $SELECTED" "$TZ_TIME" -u low -t 3000
  fi
  ;;
notify)
  NOTIFY_TEXT=""
  for country in "${!TIMEZONES[@]}"; do
    TZ_VALUE="${TIMEZONES[$country]}"
    TZ_TIME=$(TZ="$TZ_VALUE" date +'%H:%M')
    NOTIFY_TEXT="$NOTIFY_TEXT$country: $TZ_TIME\n"
  done
  notify-send "🌍 All Timezones" "$(echo -e "$NOTIFY_TEXT")" -u low -t 5000
  ;;
*)
  tz1_time=$(TZ="$TZ1" date +'%H:%M')
  tz2_time=$(TZ="$TZ2" date +'%H:%M %m/%d')
  echo "${tz1_time} | ${tz2_time}"
  ;;
esac
