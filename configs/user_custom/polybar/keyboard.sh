#!/bin/bash

case "$1" in
select)
  SELECTED=$(echo -e "C-DH\nUS\nFR\nFR-B\nAR" | rofi -dmenu -i -p "Keyboard:" -lines 4 2>/dev/null)

  case "$SELECTED" in

  "C-DH") setxkbmap -layout us -variant colemak_dh -option "" && notify-send "Keyboard" "Colemak-DH" ;;
  "US") setxkbmap -layout us -option "" && notify-send "Keyboard" "US QWERTY" ;;
  "FR") setxkbmap -layout fr -option "" && notify-send "Keyboard" "French AZERTY" ;;
  "FR-B") setxkbmap -layout fr -variant bepo -option "" && notify-send "Keyboard" "French bepo" ;;
  "AR") setxkbmap -layout ara -option "" && notify-send "Keyboard" "Arabic" ;;
  esac
  ;;
esac

# FIXED: Colemak check FIRST (before US)
FULL_QUERY=$(setxkbmap -query 2>/dev/null)

if echo "$FULL_QUERY" | grep -q "colemak_dh"; then
  echo "%{T2}%{T-} C-DH"
elif echo "$FULL_QUERY" | grep -q "layout:.*us"; then
  echo "%{T2}%{T-} US"
elif echo "$FULL_QUERY" | grep -q "layout:.*fr"; then
  echo "%{T2}%{T-} FR"
elif echo "$FULL_QUERY" | grep -q "bepo"; then
  echo "%{T2}%{T-} FR-B"
elif echo "$FULL_QUERY" | grep -q "layout:.*ara"; then
  echo "%{T2}%{T-} AR"
else
  echo "%{T2}%{T-} ??"
fi
