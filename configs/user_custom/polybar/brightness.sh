#!/bin/bash

# Get current brightness percentage
get_brightness() {
  if command -v brightnessctl >/dev/null 2>&1; then
    brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,"",$4); print $4}'
  else
    echo "0"
  fi
}

case $1 in
up)
  brightnessctl set +5% 2>/dev/null
  ;;
down)
  brightnessctl set 5%- 2>/dev/null
  ;;
shift)
  brightnessctl set 70% 2>/dev/null

  if ! pgrep -x redshift >/dev/null; then
    redshift -l 0:0 -t 3500:3500 -b 0.7 &
  fi

  notify-send "Shift Mode" "3500K + 0.7 brightness"
  ;;
normal)
  brightnessctl set 100% 2>/dev/null

  DISPLAYS=$(xrandr | grep " connected" | awk '{print $1}')
  for display in $DISPLAYS; do
    xrandr --output $display --brightness 1.0 2>/dev/null
  done

  killall redshift 2>/dev/null

  notify-send "Normal Mode" "100% brightness"
  ;;
menu)
  SELECTED=$(echo -e "Displays\nRedshift\nVibrant" | rofi -dmenu -i -p "Display:" -lines 3 2>/dev/null)

  case "$SELECTED" in
  *"Redshift")
    REDSHIFT_STATE_FILE="/tmp/redshift_state"
    if [ "$(cat "$REDSHIFT_STATE_FILE" 2>/dev/null)" = "enabled" ]; then
      killall redshift 2>/dev/null
      echo "disabled" > "$REDSHIFT_STATE_FILE"
      notify-send "Redshift" "Disabled"
    else
      redshift -l 0:0 -t 3500:3500 -b 0.7 &
      echo "enabled" > "$REDSHIFT_STATE_FILE"
      notify-send "Redshift" "Enabled (3500K, 0.7 brightness)"
    fi
    ;;
  *"Vibrant")
    if command -v vibrant-cli >/dev/null; then
      DISPLAYS=$(xrandr | grep " connected" | awk '{print $1}')
      VIBRANT_STATE_FILE="/tmp/vibrant_state"
      CURRENT_STATE=$(cat "$VIBRANT_STATE_FILE" 2>/dev/null || echo "disabled")

      if [ "$CURRENT_STATE" = "enabled" ]; then
        for display in $DISPLAYS; do
          vibrant-cli $display 1 2>/dev/null
        done
        echo "disabled" > "$VIBRANT_STATE_FILE"
        notify-send "Vibrant" "Disabled"
      else
        for display in $DISPLAYS; do
          vibrant-cli $display 0 2>/dev/null
        done
        echo "enabled" > "$VIBRANT_STATE_FILE"
        notify-send "Vibrant" "Enabled"
      fi
    else
      notify-send "Vibrant" "vibrant-cli not installed"
    fi
    ;;
  *"Displays")
    DISPLAY_INFO=$(xrandr | grep " connected" | awk '{print $1": "$3}')
    echo -e "$DISPLAY_INFO" | rofi -dmenu -i -p "Connected Displays:" -lines 5 2>/dev/null
    ;;
  esac
  exit 0
  ;;
esac

# Display current brightness
BRIGHTNESS=$(get_brightness)

REDSHIFT_STATUS=""
REDSHIFT_STATE_FILE="/tmp/redshift_state"
if [ "$(cat "$REDSHIFT_STATE_FILE" 2>/dev/null)" = "enabled" ]; then
  REDSHIFT_STATUS="[RS]"
fi

VIBRANT_STATUS=""
VIBRANT_STATE_FILE="/tmp/vibrant_state"
if [ "$(cat "$VIBRANT_STATE_FILE" 2>/dev/null)" = "enabled" ]; then
  VIBRANT_STATUS="[VB]"
fi

if [ -n "$REDSHIFT_STATUS" ] && [ -n "$VIBRANT_STATUS" ]; then
  echo "%{T2}%{T-} ${BRIGHTNESS}% ✓"
else
  echo "%{T2}%{T-} ${BRIGHTNESS}%${REDSHIFT_STATUS:+ $REDSHIFT_STATUS}${VIBRANT_STATUS:+ $VIBRANT_STATUS}"
fi
