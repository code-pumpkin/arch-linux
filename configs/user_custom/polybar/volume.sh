#!/bin/bash

# FAST actions
[ "$1" = "up" ] && pactl set-sink-volume @DEFAULT_SINK@ +3% 2>/dev/null && exit 0
[ "$1" = "down" ] && pactl set-sink-volume @DEFAULT_SINK@ -3% 2>/dev/null && exit 0
[ "$1" = "mute" ] && pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null && exit 0

# CLEAN parsing
VOLUME=$(pactl get-sink-volume @DEFAULT_SINK@ 2>&1 | grep -o '[0-9]\+%' | head -1 | sed 's/%//')
MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ 2>&1 | grep -q yes && echo "yes")

# Detect output type (headphones or speaker)
ACTIVE_PORT=$(pactl get-sink-mute @DEFAULT_SINK@ 2>&1 | grep -i "active port" || pactl list sinks 2>&1 | grep -A 20 "State: RUNNING" | grep "active port" | head -1)

if echo "$ACTIVE_PORT" | grep -qi "headphone"; then
  ICON="%{T2}%{T-}"
else
  ICON="%{T2}%{T-}"
fi

VOLUME=${VOLUME:-50}

if [ "$MUTED" = "yes" ]; then
  echo "%{T2}%{T-} MUTE"
else
  echo "${ICON} ${VOLUME}%"
fi
