#!/bin/bash
# Dunst calls script with: appname summary body icon urgency
SUMMARY="$2"
URGENCY="$5"
SOUNDS="$HOME/.config/sounds"

# Skip sound for system-monitor notifications (they play their own)
case "$SUMMARY" in
    CPU*%|MEM*%) exit 0 ;;
esac

# Play at 30% of current system volume
CURRENT_VOL=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
PLAY_VOL=$(( ${CURRENT_VOL:-100} * 30 / 100 ))
VOL="-af volume=$(awk "BEGIN{printf \"%.2f\", $PLAY_VOL/100}")"

case "$URGENCY" in
    CRITICAL)
        ffplay -nodisp -autoexit -loglevel quiet $VOL "$SOUNDS/warning.mp3" &
        ;;
    *)
        ffplay -nodisp -autoexit -loglevel quiet $VOL "$SOUNDS/chime.mp3" &
        ;;
esac
