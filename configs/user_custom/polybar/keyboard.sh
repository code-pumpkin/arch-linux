#!/bin/bash

case "$1" in
select)
  SELECTED=$(echo -e "C-DH\nColemak\nUS" | rofi -dmenu -i -p "Keyboard:" -lines 3 2>/dev/null)

  case "$SELECTED" in
  "C-DH") setxkbmap -layout us -variant colemak_dh -option "" && notify-send "Keyboard" "Colemak-DH" ;;
  "Colemak") setxkbmap -layout us -variant colemak -option "" && notify-send "Keyboard" "Colemak" ;;
  "US") setxkbmap -layout us -option "" && notify-send "Keyboard" "US QWERTY" ;;
  esac
  ;;
esac

FULL_QUERY=$(setxkbmap -query 2>/dev/null)

ICON=$'%{T2}\uf11c%{T-}'

if echo "$FULL_QUERY" | grep -q "colemak_dh"; then
  echo "${ICON} C-DH"
elif echo "$FULL_QUERY" | grep -q "colemak"; then
  echo "${ICON} CMK"
elif echo "$FULL_QUERY" | grep -q "layout:.*us"; then
  echo "${ICON} US"
else
  echo "${ICON} ??"
fi
