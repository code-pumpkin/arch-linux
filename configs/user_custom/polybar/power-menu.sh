#!/bin/bash

# Power menu for polybar
choice=$(echo -e "Shutdown\nReboot\nSuspend\nLock\nLogout" | rofi -dmenu -p "Power: ")

case "$choice" in
    Shutdown)
        systemctl poweroff
        ;;
    Reboot)
        systemctl reboot
        ;;
    Suspend)
        systemctl suspend
        ;;
    Lock)
        i3lock -c 000000
        ;;
    Logout)
        i3-msg exit
        ;;
esac
