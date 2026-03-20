#!/bin/bash

ICON_DISK=$'%{T2}\uf0a0%{T-}'

case "$1" in
notify)
    info=$(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null | tail -n +2 | awk '{printf "<b>%s</b> %s/%s (%s free) → %s\n", $1, $3, $2, $4, $6}')
    notify-send "Storage" "$info" -t 8000
    ;;
*)
    usage=$(df -h /home 2>/dev/null | awk 'NR==2 {print $5}')
    echo "${ICON_DISK} ${usage}"
    ;;
esac
