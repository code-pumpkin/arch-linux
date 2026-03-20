#!/bin/bash
# Dunst calls script with: appname summary body icon urgency
SUMMARY="$2"
URGENCY="$5"
SOUNDS="$HOME/.config/sounds"

# Skip sound for system-monitor notifications (they play their own)
case "$SUMMARY" in
    CPU*%|MEM*%) exit 0 ;;
esac

# Check if default output is headphones
VOL=""
if pactl get-default-sink 2>/dev/null | grep -qi "headphone"; then
    VOL="-af volume=0.3"
fi

case "$URGENCY" in
    CRITICAL)
        ffplay -nodisp -autoexit -loglevel quiet $VOL "$SOUNDS/warning.mp3" &
        ;;
    *)
        ffplay -nodisp -autoexit -loglevel quiet $VOL "$SOUNDS/chime.mp3" &
        ;;
esac
